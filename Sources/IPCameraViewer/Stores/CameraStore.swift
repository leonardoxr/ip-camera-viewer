import Foundation
import Observation
import OSLog

@Observable
final class CameraStore {
    var cameras: [Camera] = [] {
        didSet {
            guard !isLoading else { return }
            save()
        }
    }

    var cameraViews: [CameraViewLayout] = [] {
        didSet {
            guard !isLoading else { return }
            saveCameraViews()
        }
    }

    private let fileURL: URL
    private let viewsFileURL: URL
    private var isLoading = false

    init(fileURL: URL? = nil, viewsFileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultStoreURL()
        self.viewsFileURL = viewsFileURL ?? Self.defaultViewsStoreURL()
        load()
        loadCameraViews()
    }

    var favorites: [Camera] {
        cameras.filter(\.isFavorite)
    }

    var locations: [String] {
        Array(Set(cameras.map(\.locationLabel))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func add(_ camera: Camera) {
        cameras.append(persistCredentialAndRedact(camera))
        sortCameras()
        AppLoggers.cameras.info("Added camera \(camera.id.uuidString, privacy: .public)")
    }

    @discardableResult
    func add(_ discoveredCamera: DiscoveredCamera) -> Camera {
        let camera = Camera(
            name: discoveredCamera.name,
            urlString: discoveredCamera.suggestedURL.absoluteString,
            location: "Discovered",
            notes: discoveredCamera.notes
        )
        add(camera)
        return camera
    }

    func update(_ camera: Camera) {
        guard let index = cameras.firstIndex(where: { $0.id == camera.id }) else { return }
        cameras[index] = persistCredentialAndRedact(camera)
        sortCameras()
        AppLoggers.cameras.info("Updated camera \(camera.id.uuidString, privacy: .public)")
    }

    func delete(_ camera: Camera) {
        cameras.removeAll { $0.id == camera.id }
        CameraCredentialStore.deletePassword(for: camera.id)
        removeCameraFromViews(camera.id)
        AppLoggers.cameras.info("Deleted camera \(camera.id.uuidString, privacy: .public)")
    }

    func camera(id: Camera.ID?) -> Camera? {
        guard let id else { return nil }
        return cameras.first { $0.id == id }
    }

    func add(_ cameraView: CameraViewLayout) {
        cameraViews.append(cameraView)
        sortCameraViews()
        AppLoggers.cameras.info("Added camera view \(cameraView.id.uuidString, privacy: .public)")
    }

    func update(_ cameraView: CameraViewLayout) {
        guard let index = cameraViews.firstIndex(where: { $0.id == cameraView.id }) else { return }
        cameraViews[index] = cameraView
        sortCameraViews()
        AppLoggers.cameras.info("Updated camera view \(cameraView.id.uuidString, privacy: .public)")
    }

    func delete(_ cameraView: CameraViewLayout) {
        cameraViews.removeAll { $0.id == cameraView.id }
        AppLoggers.cameras.info("Deleted camera view \(cameraView.id.uuidString, privacy: .public)")
    }

    func cameraView(id: CameraViewLayout.ID?) -> CameraViewLayout? {
        guard let id else { return nil }
        return cameraViews.first { $0.id == id }
    }

    func cameras(in cameraView: CameraViewLayout) -> [Camera] {
        cameraView.cameraIDs.compactMap { camera(id: $0) }
    }

    func contains(_ discoveredCamera: DiscoveredCamera) -> Bool {
        cameras.contains { camera in
            camera.urlString == discoveredCamera.suggestedURL.absoluteString ||
                camera.notes.contains(discoveredCamera.serviceURL.absoluteString)
        }
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: fileURL)
            cameras = migrateLegacyPasswords(try JSONDecoder.cameraStore.decode([Camera].self, from: data))
            sortCameras()
            save()
            AppLoggers.cameras.info("Loaded \(self.cameras.count, privacy: .public) saved camera(s)")
        } catch CocoaError.fileReadNoSuchFile {
            cameras = []
            save()
        } catch {
            cameras = []
            AppLoggers.cameras.error("Unable to load cameras: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func loadCameraViews() {
        isLoading = true
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: viewsFileURL)
            cameraViews = try JSONDecoder.cameraStore.decode([CameraViewLayout].self, from: data)
            normalizeCameraViews()
            sortCameraViews()
            saveCameraViews()
            AppLoggers.cameras.info("Loaded \(self.cameraViews.count, privacy: .public) saved camera view(s)")
        } catch CocoaError.fileReadNoSuchFile {
            cameraViews = []
            saveCameraViews()
        } catch {
            cameraViews = []
            AppLoggers.cameras.error("Unable to load camera views: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.cameraStore.encode(cameras)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            AppLoggers.cameras.error("Unable to save cameras: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveCameraViews() {
        do {
            try FileManager.default.createDirectory(
                at: viewsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.cameraStore.encode(cameraViews)
            try data.write(to: viewsFileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: viewsFileURL.path
            )
        } catch {
            AppLoggers.cameras.error("Unable to save camera views: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistCredentialAndRedact(_ camera: Camera) -> Camera {
        var redactedCamera = camera
        if camera.password.isEmpty {
            CameraCredentialStore.deletePassword(for: camera.id)
        } else {
            guard CameraCredentialStore.save(password: camera.password, for: camera.id) else {
                return camera
            }
            redactedCamera.password = ""
        }

        return redactedCamera
    }

    private func migrateLegacyPasswords(_ loadedCameras: [Camera]) -> [Camera] {
        loadedCameras.map { camera in
            guard !camera.password.isEmpty else { return camera }
            guard CameraCredentialStore.save(password: camera.password, for: camera.id) else { return camera }

            var migratedCamera = camera
            migratedCamera.password = ""
            return migratedCamera
        }
    }

    private func sortCameras() {
        cameras.sort {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }

            if $0.locationLabel != $1.locationLabel {
                return $0.locationLabel.localizedCaseInsensitiveCompare($1.locationLabel) == .orderedAscending
            }

            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func sortCameraViews() {
        cameraViews.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func normalizeCameraViews() {
        let validCameraIDs = Set(cameras.map(\.id))
        cameraViews = cameraViews.map { cameraView in
            var normalizedView = cameraView
            normalizedView.cameraIDs = cameraView.cameraIDs.filter { validCameraIDs.contains($0) }
            normalizedView.columnCount = min(max(cameraView.columnCount, 1), 6)
            normalizedView.tileWidth = min(max(cameraView.tileWidth, 180), 520)
            return normalizedView
        }
    }

    private func removeCameraFromViews(_ cameraID: Camera.ID) {
        cameraViews = cameraViews.map { cameraView in
            var updatedView = cameraView
            updatedView.cameraIDs.removeAll { $0 == cameraID }
            return updatedView
        }
        sortCameraViews()
    }

    private static func defaultStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)
            .appending(path: "cameras.json")
    }

    private static func defaultViewsStoreURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return baseURL
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)
            .appending(path: "camera-views.json")
    }
}

private extension JSONEncoder {
    static var cameraStore: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var cameraStore: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
