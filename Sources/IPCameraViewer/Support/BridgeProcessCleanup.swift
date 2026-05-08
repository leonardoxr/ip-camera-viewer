import Foundation

enum BridgeProcessCleanup {
    static func cleanUpLeftoverProcesses() {
        let patterns = [
            "/IPCameraViewer/RTSPBridge-",
            "http.server .*IPCameraViewer/RTSPBridge-",
            "/IPCameraViewer/CompositeBridge-",
            "http.server .*IPCameraViewer/CompositeBridge-"
        ]

        for pattern in patterns {
            terminateProcesses(matching: pattern)
        }

        removeTemporaryDirectories(prefix: "RTSPBridge-")
        removeTemporaryDirectories(prefix: "CompositeBridge-")
    }

    private static func terminateProcesses(matching pattern: String) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pkill")
        process.arguments = ["-f", pattern]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            AppLoggers.streams.debug("Bridge process cleanup skipped pattern \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func removeTemporaryDirectories(prefix: String) {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for child in children where child.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: child)
        }
    }
}
