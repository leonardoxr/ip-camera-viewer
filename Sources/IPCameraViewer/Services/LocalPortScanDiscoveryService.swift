import Darwin
import Foundation

struct LocalPortScanDiscoveryService {
    func discover(timeout: TimeInterval = 4) async -> [DiscoveredCamera] {
        await Task.detached(priority: .utility) {
            Self.scan(timeout: timeout)
        }.value
    }

    private static func scan(timeout: TimeInterval) -> [DiscoveredCamera] {
        let hosts = localIPv4Ranges().flatMap(\.hosts)
        guard !hosts.isEmpty else { return [] }

        let ports = [80, 81, 88, 443, 554, 5000, 8000, 8080, 8081, 8554, 8899, 37777]
        let deadline = Date().addingTimeInterval(timeout)
        let queue = DispatchQueue(label: "CameraPortScan", attributes: .concurrent)
        let group = DispatchGroup()
        let lock = NSLock()
        var discoveredByHost: [String: DiscoveredCamera] = [:]

        for host in hosts.prefix(512) {
            guard Date() < deadline else { break }

            group.enter()
            queue.async {
                defer { group.leave() }

                var bestCamera: DiscoveredCamera?
                for port in ports where Date() < deadline {
                    if isLikelyCamera(host: host, port: port, timeout: 0.28) || isPossibleCamera(host: host, port: port, timeout: 0.22) {
                        guard let camera = camera(host: host, port: port) else { return }
                        bestCamera = preferred(bestCamera, camera)
                    }
                }

                guard let bestCamera else { return }
                lock.lock()
                discoveredByHost[host] = preferred(discoveredByHost[host], bestCamera)
                lock.unlock()
            }
        }

        _ = group.wait(timeout: .now() + timeout + 1)
        return Array(discoveredByHost.values)
    }

    private static func camera(host: String, port: Int) -> DiscoveredCamera? {
        let scheme = port == 443 ? "https" : (port == 554 || port == 8554 ? "rtsp" : "http")
        let portSuffix = (scheme == "http" && port == 80) || (scheme == "https" && port == 443) ? "" : ":\(port)"
        guard let serviceURL = URL(string: "\(scheme)://\(host)\(portSuffix)") else { return nil }
        let suggestedURL = suggestedStreamURL(host: host, port: port, fallback: serviceURL)

        let notes = port == 37777 ? ["Dahua-style TCP service port detected. Try RTSP on port 554 if streaming is enabled."] : []
        return DiscoveredCamera(
            id: "portscan://\(host):\(port)",
            name: "Network Camera \(host)",
            host: host,
            serviceURL: serviceURL,
            suggestedURL: suggestedURL,
            discoveryMethod: "Port Scan",
            scopes: ["port:\(port)"] + notes
        )
    }

    private static func isLikelyCamera(host: String, port: Int, timeout: TimeInterval) -> Bool {
        guard LocalPortProbe.canConnect(to: host, port: port, timeout: timeout) else { return false }

        if port == 554 || port == 8554 || port == 37777 {
            return true
        }

        guard port != 443 else { return false }
        return httpFingerprintLooksCameraLike(host: host, port: port, timeout: timeout)
    }

    private static func suggestedStreamURL(host: String, port: Int, fallback: URL) -> URL {
        if port == 554 || port == 37777 {
            return URL(string: "rtsp://\(host):554/cam/realmonitor?channel=1&subtype=0") ?? fallback
        }

        return fallback
    }

    private static func isPossibleCamera(host: String, port: Int, timeout: TimeInterval) -> Bool {
        guard !host.hasSuffix(".1") else { return false }
        guard port != 443 else { return false }
        return LocalPortProbe.canConnect(to: host, port: port, timeout: timeout)
    }

    private static func preferred(_ existing: DiscoveredCamera?, _ candidate: DiscoveredCamera) -> DiscoveredCamera {
        guard let existing else { return candidate }

        let rank = [554: 0, 8554: 1, 80: 2, 443: 3, 8080: 4, 8081: 5, 37777: 6]
        let existingRank = rank[existing.serviceURL.port ?? defaultPort(for: existing.serviceURL.scheme)] ?? 99
        let candidateRank = rank[candidate.serviceURL.port ?? defaultPort(for: candidate.serviceURL.scheme)] ?? 99
        return candidateRank < existingRank ? candidate : existing
    }

    private static func defaultPort(for scheme: String?) -> Int {
        switch scheme {
        case "https":
            443
        case "rtsp":
            554
        default:
            80
        }
    }

    private static func httpFingerprintLooksCameraLike(host: String, port: Int, timeout: TimeInterval) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(host))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else { return false }

        let request = "GET / HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nUser-Agent: IPCameraViewer\r\n\r\n"
        _ = request.withCString { pointer in
            send(socketDescriptor, pointer, strlen(pointer), 0)
        }

        var pollDescriptor = pollfd(fd: socketDescriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, Int32(timeout * 1_000)) > 0 else { return false }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let byteCount = recv(socketDescriptor, &buffer, buffer.count, 0)
        guard byteCount > 0 else { return false }

        let response = String(decoding: buffer.prefix(byteCount), as: UTF8.self).lowercased()
        return cameraFingerprints.contains { response.contains($0) }
    }

    private static func localIPv4Ranges() -> [IPv4Range] {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }

        var ranges: [IPv4Range] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface

        while let interface = current {
            defer { current = interface.pointee.ifa_next }

            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK
            guard isUp, !isLoopback,
                  let addressPointer = interface.pointee.ifa_addr,
                  let netmaskPointer = interface.pointee.ifa_netmask,
                  addressPointer.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }

            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let netmask = netmaskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            ranges.append(IPv4Range(address: UInt32(bigEndian: address), netmask: UInt32(bigEndian: netmask)))
        }

        return ranges
    }

}

private let cameraFingerprints = [
    "ip camera",
    "ip-camera",
    "ipcam",
    "webcam",
    "network camera",
    "onvif",
    "rtsp",
    "nvr",
    "dvr",
    "hikvision",
    "dahua",
    "axis",
    "foscam",
    "amcrest",
    "reolink",
    "ubnt",
    "unifi video",
    "blue iris",
    "go2rtc",
    "mjpeg",
    "live view"
]

private struct IPv4Range {
    let address: UInt32
    let netmask: UInt32

    var hosts: [String] {
        let local24Mask: UInt32 = 0xff_ff_ff_00
        let network = address & local24Mask
        let hostCount = 254

        return (1...hostCount).compactMap { offset in
            let candidate = network + UInt32(offset)
            guard candidate != address else { return nil }
            return [
                String((candidate >> 24) & 0xff),
                String((candidate >> 16) & 0xff),
                String((candidate >> 8) & 0xff),
                String(candidate & 0xff)
            ].joined(separator: ".")
        }
    }
}
