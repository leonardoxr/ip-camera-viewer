import Foundation
import OSLog

enum AppLoggers {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.local.IPCameraViewer"

    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
    static let commands = Logger(subsystem: subsystem, category: "Commands")
    static let sidebar = Logger(subsystem: subsystem, category: "Sidebar")
    static let cameras = Logger(subsystem: subsystem, category: "Cameras")
    static let discovery = Logger(subsystem: subsystem, category: "Discovery")
    static let streams = Logger(subsystem: subsystem, category: "Streams")
}
