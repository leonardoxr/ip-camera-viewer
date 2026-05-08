// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "IPCameraViewer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "IPCameraViewer", targets: ["IPCameraViewer"])
    ],
    targets: [
        .executableTarget(
            name: "IPCameraViewer",
            path: "Sources/IPCameraViewer"
        )
    ]
)
