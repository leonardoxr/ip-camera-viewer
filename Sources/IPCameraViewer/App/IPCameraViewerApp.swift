import AppKit
import OSLog
import SwiftUI

@main
struct IPCameraViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var cameraStore = CameraStore()
    @State private var discoveryStore = DiscoveryStore()

    var body: some Scene {
        WindowGroup("IP Camera Viewer", id: "main") {
            ContentView()
                .environment(cameraStore)
                .environment(discoveryStore)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Camera") {
                    postCommand(.showAddCameraSheet, label: "Add Camera")
                }
                .keyboardShortcut("n")

                Button("Discover Cameras") {
                    postCommand(.showDiscoverySheet, label: "Discover Cameras")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandMenu("Camera") {
                Button("Scan Again") {
                    postCommand(.scanCameras, label: "Scan Again")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Reload Selected Stream") {
                    postCommand(.reloadSelectedCamera, label: "Reload Selected Stream")
                }
                .keyboardShortcut("r")

                Divider()

                Button("Clear Camera Search") {
                    postCommand(.clearCameraSearch, label: "Clear Camera Search")
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Toggle Location Groups") {
                    postCommand(.toggleCameraGrouping, label: "Toggle Location Groups")
                }
                .keyboardShortcut("g", modifiers: [.command, .control])
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func postCommand(_ name: Notification.Name, label: String) {
        AppLoggers.commands.info("Command invoked: \(label, privacy: .public)")
        NotificationCenter.default.post(name: name, object: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        BridgeProcessCleanup.cleanUpLeftoverProcesses()
        AppLoggers.lifecycle.info("Application launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        BridgeProcessCleanup.cleanUpLeftoverProcesses()
        AppLoggers.lifecycle.info("Application bridge processes cleaned up")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLoggers.lifecycle.info("Terminating after last window closed")
        return true
    }
}
