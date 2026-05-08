import Darwin
import Foundation

struct ONVIFDiscoveryService {
    func discover(timeout: TimeInterval = 4) async -> [DiscoveredCamera] {
        await Task.detached(priority: .userInitiated) {
            Self.discoverBlocking(timeout: timeout)
        }.value
    }

    private static func discoverBlocking(timeout: TimeInterval) -> [DiscoveredCamera] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { return [] }
        defer { close(socketDescriptor) }

        var reuse: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var ttl: UInt8 = 2
        setsockopt(socketDescriptor, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout.size(ofValue: ttl)))

        let flags = fcntl(socketDescriptor, F_GETFL, 0)
        _ = fcntl(socketDescriptor, F_SETFL, flags | O_NONBLOCK)

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = 0
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return [] }

        sendProbe(using: socketDescriptor)

        let deadline = Date().addingTimeInterval(timeout)
        var discoveredByID: [String: DiscoveredCamera] = [:]

        while Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 65_535)
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
                let data = Data(buffer.prefix(byteCount))
                let remoteHost = host(from: remoteAddress)
                for camera in ONVIFProbeParser.parse(data: data, fallbackHost: remoteHost) {
                    discoveredByID[camera.id] = camera
                }
            } else {
                usleep(100_000)
            }
        }

        return discoveredByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func sendProbe(using socketDescriptor: Int32) {
        let messageID = UUID().uuidString.lowercased()
        let probe = """
        <?xml version="1.0" encoding="UTF-8"?>
        <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
          <e:Header>
            <w:MessageID>uuid:\(messageID)</w:MessageID>
            <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
            <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
          </e:Header>
          <e:Body>
            <d:Probe>
              <d:Types>dn:NetworkVideoTransmitter</d:Types>
            </d:Probe>
          </e:Body>
        </e:Envelope>
        """

        var multicastAddress = sockaddr_in()
        multicastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        multicastAddress.sin_family = sa_family_t(AF_INET)
        multicastAddress.sin_port = in_port_t(3702).bigEndian
        multicastAddress.sin_addr = in_addr(s_addr: inet_addr("239.255.255.250"))

        let bytes = Array(probe.utf8)
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

private final class ONVIFProbeParser: NSObject, XMLParserDelegate {
    private var currentElement = ""
    private var currentText = ""
    private var xAddrs: [String] = []
    private var scopes: [String] = []

    static func parse(data: Data, fallbackHost: String?) -> [DiscoveredCamera] {
        let parserDelegate = ONVIFProbeParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else { return [] }

        return parserDelegate.xAddrs.compactMap { urlString in
            guard let serviceURL = URL(string: urlString),
                  let host = serviceURL.host(percentEncoded: false) ?? fallbackHost,
                  let suggestedURL = URL(string: "\(serviceURL.scheme ?? "http")://\(host)") else {
                return nil
            }

            let name = parserDelegate.cameraName(host: host)
            return DiscoveredCamera(
                id: serviceURL.absoluteString,
                name: name,
                host: host,
                serviceURL: serviceURL,
                suggestedURL: suggestedURL,
                discoveryMethod: "ONVIF WS-Discovery",
                scopes: parserDelegate.scopes
            )
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = localName(elementName)
        currentText = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let element = localName(elementName)
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if element == "XAddrs" {
            xAddrs.append(contentsOf: trimmedText.split(separator: " ").map(String.init))
        } else if element == "Scopes" {
            scopes.append(contentsOf: trimmedText.split(separator: " ").map(String.init))
        }

        currentElement = ""
        currentText = ""
    }

    private func cameraName(host: String) -> String {
        for scope in scopes {
            guard let url = URL(string: scope),
                  url.host(percentEncoded: false) == "www.onvif.org" else {
                continue
            }

            let path = url.path(percentEncoded: false)
            if path.hasPrefix("/name/") {
                let name = String(path.dropFirst("/name/".count)).replacingOccurrences(of: "_", with: " ")
                if !name.isEmpty {
                    return name
                }
            }
        }

        return "Camera \(host)"
    }

    private func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }
}
