import Darwin
import Foundation

enum LocalHLSHTTPServer {
    static func start(serving directory: URL, logPrefix: String) throws -> (process: Process, baseURL: URL) {
        let port = try availableLocalPort()
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/python3")
        process.arguments = [
            "-m", "http.server",
            "\(port)",
            "--bind", "0.0.0.0",
            "--directory", directory.path
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()

        let host = reachableIPv4Address() ?? "127.0.0.1"
        AppLoggers.streams.info("\(logPrefix, privacy: .public) HLS server on \(host, privacy: .public):\(port, privacy: .public)")
        return (process, URL(string: "http://\(host):\(port)")!)
    }

    private static func availableLocalPort() throws -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else {
            throw POSIXError(.EIO)
        }
        defer { close(socketDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var socketAddress = sockaddr_in()
        var socketAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &socketAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(socketDescriptor, reboundPointer, &socketAddressLength)
            }
        }
        guard nameResult == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        return Int(UInt16(bigEndian: socketAddress.sin_port))
    }

    private static func reachableIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }

        var fallback: String?
        var cursor = interfaces
        while let interface = cursor?.pointee {
            defer { cursor = interface.ifa_next }

            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET),
                  (interface.ifa_flags & UInt32(IFF_UP)) != 0,
                  (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else {
                continue
            }

            var address = interface.ifa_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                continue
            }

            let ipAddress = String(cString: buffer)
            let interfaceName = String(cString: interface.ifa_name)
            if interfaceName == "en0" || interfaceName == "en1" {
                return ipAddress
            }
            fallback = fallback ?? ipAddress
        }

        return fallback
    }
}
