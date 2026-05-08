import Darwin
import Foundation

struct SSDPDiscoveryService {
    func discover(timeout: TimeInterval = 4) async -> [DiscoveredCamera] {
        await Task.detached(priority: .userInitiated) {
            Self.discoverBlocking(timeout: timeout)
        }.value
    }

    private static func discoverBlocking(timeout: TimeInterval) -> [DiscoveredCamera] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { return [] }
        defer { close(socketDescriptor) }

        let flags = fcntl(socketDescriptor, F_GETFL, 0)
        _ = fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK)

        for searchTarget in ["urn:schemas-upnp-org:device:Basic:1", "upnp:rootdevice", "ssdp:all"] {
            sendSearch(searchTarget: searchTarget, using: socketDescriptor)
        }

        let deadline = Date().addingTimeInterval(timeout)
        var discoveredByID: [String: DiscoveredCamera] = [:]

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            var remoteAddress = sockaddr_storage()
            var remoteLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let byteCount = withUnsafeMutablePointer(to: &remoteAddress) { remotePointer in
                remotePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    buffer.withUnsafeMutableBytes { bytes in
                        recvfrom(socketDescriptor, bytes.baseAddress, bytes.count, 0, socketAddress, &remoteLength)
                    }
                }
            }

            if byteCount > 0 {
                let response = String(decoding: buffer.prefix(byteCount), as: UTF8.self)
                if let camera = parse(response: response, fallbackHost: host(from: remoteAddress)) {
                    discoveredByID[camera.id] = camera
                }
            } else {
                usleep(100_000)
            }
        }

        return Array(discoveredByID.values)
    }

    private static func sendSearch(searchTarget: String, using socketDescriptor: Int32) {
        let search = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 2\r
        ST: \(searchTarget)\r
        \r

        """

        var multicastAddress = sockaddr_in()
        multicastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        multicastAddress.sin_family = sa_family_t(AF_INET)
        multicastAddress.sin_port = in_port_t(1900).bigEndian
        multicastAddress.sin_addr = in_addr(s_addr: inet_addr("239.255.255.250"))

        let bytes = Array(search.utf8)
        _ = withUnsafePointer(to: &multicastAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bytes.withUnsafeBytes { buffer in
                    sendto(
                        socketDescriptor,
                        buffer.baseAddress,
                        buffer.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }
    }

    private static func parse(response: String, fallbackHost: String?) -> DiscoveredCamera? {
        let headers = response
            .split(separator: "\r\n")
            .compactMap { line -> (String, String)? in
                guard let separator = line.firstIndex(of: ":") else { return nil }
                let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                return (key, value)
            }
            .reduce(into: [String: String]()) { headers, pair in
                headers[pair.0] = pair.1
            }

        guard let location = headers["location"],
              let serviceURL = URL(string: location),
              let host = serviceURL.host(percentEncoded: false) ?? fallbackHost else {
            return nil
        }

        let lowercasedFingerprint = [
            headers["server"],
            headers["st"],
            headers["usn"],
            headers["x-user-agent"]
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        let looksCameraLike = ["camera", "ipcam", "onvif", "rtsp", "nvr", "dvr", "hikvision", "dahua", "axis", "foscam", "amcrest", "reolink"]
            .contains { lowercasedFingerprint.contains($0) }

        guard looksCameraLike || serviceURL.port.map(commonCameraPorts.contains) == true else {
            return nil
        }

        let suggestedURL = URL(string: "\(serviceURL.scheme ?? "http")://\(host):\(serviceURL.port ?? 80)") ?? serviceURL
        return DiscoveredCamera(
            id: serviceURL.absoluteString,
            name: "UPnP Camera \(host)",
            host: host,
            serviceURL: serviceURL,
            suggestedURL: suggestedURL,
            discoveryMethod: "SSDP/UPnP",
            scopes: []
        )
    }

    private static let commonCameraPorts = [80, 81, 88, 443, 5000, 554, 8000, 8080, 8081, 8554, 8899, 37777]

    private static func host(from storage: sockaddr_storage) -> String? {
        guard storage.ss_family == sa_family_t(AF_INET) else { return nil }

        var address = storage
        var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { socketAddress in
                var sinAddress = socketAddress.pointee.sin_addr
                guard inet_ntop(AF_INET, &sinAddress, &hostBuffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }

                let hostBytes = hostBuffer
                    .prefix { $0 != 0 }
                    .map { UInt8(bitPattern: $0) }
                return String(decoding: hostBytes, as: UTF8.self)
            }
        }
    }
}
