import Foundation

struct BonjourDiscoveryService {
    func discover(timeout: TimeInterval = 4) async -> [DiscoveredCamera] {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let session = BonjourDiscoverySession(timeout: timeout) { session, cameras in
                    BonjourDiscoveryRetainer.remove(session)
                    continuation.resume(returning: cameras)
                }
                BonjourDiscoveryRetainer.add(session)
                session.start()
            }
        }
    }
}

private final class BonjourDiscoverySession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let timeout: TimeInterval
    private let completion: (BonjourDiscoverySession, [DiscoveredCamera]) -> Void
    private var browsers: [NetServiceBrowser] = []
    private var services: [NetService] = []
    private var discoveredByID: [String: DiscoveredCamera] = [:]
    private var didFinish = false

    init(timeout: TimeInterval, completion: @escaping (BonjourDiscoverySession, [DiscoveredCamera]) -> Void) {
        self.timeout = timeout
        self.completion = completion
    }

    func start() {
        let serviceTypes = [
            "_http._tcp.",
            "_https._tcp.",
            "_rtsp._tcp.",
            "_axis-video._tcp."
        ]

        browsers = serviceTypes.map { serviceType in
            let browser = NetServiceBrowser()
            browser.delegate = self
            browser.searchForServices(ofType: serviceType, inDomain: "local.")
            return browser
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        services.append(service)
        service.resolve(withTimeout: 1.5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              let scheme = scheme(for: sender.type),
              let serviceURL = URL(string: "\(scheme)://\(host):\(sender.port)") else {
            return
        }

        let camera = DiscoveredCamera(
            id: serviceURL.absoluteString,
            name: sender.name.isEmpty ? "Bonjour Camera \(host)" : sender.name,
            host: host,
            serviceURL: serviceURL,
            suggestedURL: serviceURL,
            discoveryMethod: "Bonjour",
            scopes: [sender.type]
        )
        discoveredByID[camera.id] = camera
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        browsers.forEach { $0.stop() }
        services.forEach { $0.stop() }
        completion(self, Array(discoveredByID.values))
    }

    private func scheme(for serviceType: String) -> String? {
        if serviceType.contains("_rtsp") {
            return "rtsp"
        }

        if serviceType.contains("_https") {
            return "https"
        }

        return "http"
    }
}

@MainActor
private enum BonjourDiscoveryRetainer {
    private static var sessions: [BonjourDiscoverySession] = []

    static func add(_ session: BonjourDiscoverySession) {
        sessions.append(session)
    }

    static func remove(_ session: BonjourDiscoverySession) {
        sessions.removeAll { $0 === session }
    }
}
