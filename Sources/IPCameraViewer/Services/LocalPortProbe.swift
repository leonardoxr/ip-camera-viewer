import Darwin
import Foundation

enum LocalPortProbe {
    static func canConnect(to host: String, port: Int, timeout: TimeInterval) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        let flags = fcntl(socketDescriptor, F_GETFL, 0)
        _ = fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr(host))

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if result == 0 {
            return true
        }

        guard errno == EINPROGRESS else { return false }

        var pollDescriptor = pollfd(fd: socketDescriptor, events: Int16(POLLOUT), revents: 0)
        let selected = poll(&pollDescriptor, 1, Int32(timeout * 1_000))
        guard selected > 0, (pollDescriptor.revents & Int16(POLLOUT)) == Int16(POLLOUT) else { return false }

        var socketError: Int32 = 0
        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(socketDescriptor, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength)
        return socketError == 0
    }
}
