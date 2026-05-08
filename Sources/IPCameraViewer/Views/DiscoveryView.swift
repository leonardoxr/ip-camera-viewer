import SwiftUI

@MainActor
struct DiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CameraStore.self) private var store
    @State private var viewModel = DiscoveryViewModel()
    @State private var knownHost = ""
    @State private var cameraDraft: Camera?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            knownHostProbe

            Divider()

            content
                .frame(minHeight: 360)

            Divider()

            footer
        }
        .frame(width: 720, height: 590)
        .task {
            if viewModel.discoveredCameras.isEmpty && !viewModel.isScanning {
                viewModel.scan()
            }
        }
        .sheet(item: $cameraDraft) { draft in
            CameraFormView(camera: draft, isNewCamera: true) { camera in
                store.add(camera)
                AppLoggers.discovery.info("Added discovered camera \(camera.id.uuidString, privacy: .public)")
            }
        }
    }

    private var knownHostProbe: some View {
        HStack(spacing: 10) {
            TextField("Camera IP address", text: $knownHost, prompt: Text("192.168.1.20"))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    probeKnownHost()
                }

            Button {
                probeKnownHost()
            } label: {
                Label("Probe IP", systemImage: "scope")
            }
            .disabled(viewModel.isScanning || knownHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Discover Cameras")
                    .font(.title2.weight(.semibold))

                Text("Searches with ONVIF, Bonjour, UPnP, and common IP camera ports.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isScanning && viewModel.discoveredCameras.isEmpty {
            ContentUnavailableView {
                Label("Scanning Local Network", systemImage: "network")
            } description: {
                Text("Checking camera discovery protocols and common HTTP/RTSP ports.")
            }
        } else if viewModel.discoveredCameras.isEmpty {
            ContentUnavailableView {
                Label("No Cameras Found", systemImage: "video.slash")
            } description: {
                Text("Make sure cameras are powered on and on the same network. Some cameras require discovery to be enabled in their admin settings.")
            }
        } else {
            List(viewModel.discoveredCameras) { camera in
                DiscoveredCameraRow(
                    camera: camera,
                    isAdded: store.contains(camera),
                    onAdd: { add(camera) }
                )
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.discoveredCameras.count) found")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Scan Again") {
                viewModel.scan()
            }
            .disabled(viewModel.isScanning)

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func add(_ discoveredCamera: DiscoveredCamera) {
        cameraDraft = Camera(
            name: discoveredCamera.name,
            urlString: discoveredCamera.suggestedURL.absoluteString,
            location: "Discovered",
            notes: discoveredCamera.notes
        )
    }

    private func probeKnownHost() {
        AppLoggers.discovery.info("Started known host probe")
        viewModel.probeKnownHost(knownHost)
    }
}

@Observable
@MainActor
final class DiscoveryViewModel {
    var discoveredCameras: [DiscoveredCamera] = []
    var isScanning = false

    private let discoveryService = CameraDiscoveryService()
    private let knownHostProbeService = KnownHostProbeService()

    func scan() {
        guard !isScanning else { return }

        isScanning = true
        AppLoggers.discovery.info("Started discovery view scan")
        Task {
            self.discoveredCameras = await discoveryService.discover()
            self.isScanning = false
            AppLoggers.discovery.info("Completed discovery view scan with \(self.discoveredCameras.count, privacy: .public) result(s)")
        }
    }

    func probeKnownHost(_ host: String) {
        guard !isScanning else { return }

        isScanning = true
        Task {
            let cameras = await knownHostProbeService.probe(host: host)
            self.merge(cameras)
            self.isScanning = false
            AppLoggers.discovery.info("Completed known host probe with \(cameras.count, privacy: .public) result(s)")
        }
    }

    private func merge(_ cameras: [DiscoveredCamera]) {
        var byID = Dictionary(uniqueKeysWithValues: discoveredCameras.map { ($0.id, $0) })
        for camera in cameras {
            byID[camera.id] = camera
        }
        discoveredCameras = byID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

@MainActor
private struct DiscoveredCameraRow: View {
    let camera: DiscoveredCamera
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "video.badge.checkmark")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(camera.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(camera.host)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(camera.discoveryMethod)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(camera.serviceURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer()

            Button(isAdded ? "Added" : "Add") {
                onAdd()
            }
            .disabled(isAdded)
        }
        .padding(.vertical, 6)
    }
}
