import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class DiscoveryStore {
    var discoveredCameras: [DiscoveredCamera] = []
    var isScanning = false
    private(set) var hasScanned = false

    private let discoveryService = CameraDiscoveryService()

    func scanIfNeeded() {
        guard !hasScanned else { return }
        scan()
    }

    func scan() {
        guard !isScanning else { return }

        isScanning = true
        hasScanned = true
        AppLoggers.discovery.info("Started camera discovery scan")

        Task {
            let discovered = await discoveryService.discover()
            discoveredCameras = discovered
            isScanning = false
            AppLoggers.discovery.info("Completed camera discovery scan with \(discovered.count, privacy: .public) result(s)")
        }
    }
}
