import Foundation

struct CameraDiscoveryService {
    func discover(timeout: TimeInterval = 12) async -> [DiscoveredCamera] {
        async let onvif = ONVIFDiscoveryService().discover(timeout: timeout)
        async let ssdp = SSDPDiscoveryService().discover(timeout: timeout)
        async let bonjour = BonjourDiscoveryService().discover(timeout: timeout)
        async let portScan = LocalPortScanDiscoveryService().discover(timeout: timeout)

        return await merge(onvif + ssdp + bonjour + portScan)
    }

    private func merge(_ cameras: [DiscoveredCamera]) -> [DiscoveredCamera] {
        var merged: [String: DiscoveredCamera] = [:]

        for camera in cameras {
            let hostKey = camera.host.lowercased()
            let urlKey = camera.suggestedURL.absoluteString.lowercased()
            let key = hostKey.isEmpty ? urlKey : hostKey

            if let existing = merged[key] {
                merged[key] = preferred(existing, camera)
            } else {
                merged[key] = camera
            }
        }

        return merged.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func preferred(_ first: DiscoveredCamera, _ second: DiscoveredCamera) -> DiscoveredCamera {
        let rank = ["ONVIF WS-Discovery": 0, "Bonjour": 1, "SSDP/UPnP": 2, "Port Scan": 3]
        return (rank[second.discoveryMethod] ?? 99) < (rank[first.discoveryMethod] ?? 99) ? second : first
    }
}
