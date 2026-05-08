import Foundation

struct KnownHostProbeService {
    func probe(host rawHost: String, timeout: TimeInterval = 0.35) async -> [DiscoveredCamera] {
        await Task.detached(priority: .userInitiated) {
            let host = Self.normalizedHost(rawHost)
            guard !host.isEmpty else { return [] }

            let ports = [80, 81, 88, 443, 554, 5000, 5001, 6667, 6668, 6669, 6789, 7447, 8000, 8001, 8080, 8081, 8090, 8554, 8555, 8899, 9000, 9527, 10_000, 10_554, 37777]
            let openPorts = ports.filter { LocalPortProbe.canConnect(to: host, port: $0, timeout: timeout) }

            if openPorts.isEmpty {
                return [Self.fallbackCamera(host: host)]
            }

            return openPorts.map { Self.discoveredCamera(host: host, port: $0) }
        }.value
    }

    private static func normalizedHost(_ rawHost: String) -> String {
        rawHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "rtsp://", with: "")
            .split(separator: "/")
            .first
            .map(String.init) ?? ""
    }

    private static func fallbackCamera(host: String) -> DiscoveredCamera {
        let url = URL(string: "http://\(host)")!
        return DiscoveredCamera(
            id: "known-ip://\(host)",
            name: "Camera \(host)",
            host: host,
            serviceURL: url,
            suggestedURL: url,
            discoveryMethod: "Known IP",
            scopes: ["No common camera ports answered from this Mac."]
        )
    }

    private static func discoveredCamera(host: String, port: Int) -> DiscoveredCamera {
        if port == 37777 {
            let serviceURL = URL(string: "tcp://\(host):37777")!
            let suggestedURL = URL(string: "rtsp://\(host):554/cam/realmonitor?channel=1&subtype=0")!
            return DiscoveredCamera(
                id: "known-ip://\(host):\(port)",
                name: "Camera \(host)",
                host: host,
                serviceURL: serviceURL,
                suggestedURL: suggestedURL,
                discoveryMethod: "Known IP Probe",
                scopes: ["port:\(port)", "Dahua-style TCP service detected; suggested stream uses RTSP channel 1 main stream."]
            )
        }

        let scheme = port == 443 ? "https" : (port == 554 || port == 8554 || port == 10_554 ? "rtsp" : "http")
        let portSuffix = (scheme == "http" && port == 80) || (scheme == "https" && port == 443) ? "" : ":\(port)"
        let url = URL(string: "\(scheme)://\(host)\(portSuffix)")!

        return DiscoveredCamera(
            id: "known-ip://\(host):\(port)",
            name: "Camera \(host)",
            host: host,
            serviceURL: url,
            suggestedURL: url,
            discoveryMethod: "Known IP Probe",
            scopes: ["port:\(port)"]
        )
    }
}
