import Foundation

enum SidebarSelection: Hashable {
    case overview
    case views
    case cameraView(CameraViewLayout.ID)
    case camera(Camera.ID)

    init?(storageValue: String) {
        if storageValue == Self.overviewStorageValue {
            self = .overview
            return
        }

        if storageValue == Self.viewsStorageValue {
            self = .views
            return
        }

        if storageValue.hasPrefix(Self.cameraViewStoragePrefix) {
            let rawID = String(storageValue.dropFirst(Self.cameraViewStoragePrefix.count))
            guard let id = UUID(uuidString: rawID) else { return nil }
            self = .cameraView(id)
            return
        }

        if storageValue.hasPrefix(Self.cameraStoragePrefix) {
            let rawID = String(storageValue.dropFirst(Self.cameraStoragePrefix.count))
            guard let id = UUID(uuidString: rawID) else { return nil }
            self = .camera(id)
            return
        }

        return nil
    }

    var storageValue: String {
        switch self {
        case .overview:
            Self.overviewStorageValue
        case .views:
            Self.viewsStorageValue
        case .cameraView(let id):
            "\(Self.cameraViewStoragePrefix)\(id.uuidString)"
        case .camera(let id):
            "\(Self.cameraStoragePrefix)\(id.uuidString)"
        }
    }

    var logLabel: String {
        switch self {
        case .overview:
            "overview"
        case .views:
            "views"
        case .cameraView(let id):
            "view:\(id.uuidString)"
        case .camera(let id):
            "camera:\(id.uuidString)"
        }
    }

    private static let overviewStorageValue = "overview"
    private static let viewsStorageValue = "views"
    private static let cameraViewStoragePrefix = "view:"
    private static let cameraStoragePrefix = "camera:"
}
