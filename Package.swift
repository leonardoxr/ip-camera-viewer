// swift-tools-version: 6.2

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
            path: "Sources/IPCameraViewer",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
