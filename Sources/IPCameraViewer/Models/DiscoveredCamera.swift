import Foundation

struct DiscoveredCamera: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let serviceURL: URL
    let suggestedURL: URL
    let discoveryMethod: String
    let scopes: [String]

    var notes: String {
        """
        Discovered with \(discoveryMethod).
        Service: \(serviceURL.absoluteString)
        """
    }
}
