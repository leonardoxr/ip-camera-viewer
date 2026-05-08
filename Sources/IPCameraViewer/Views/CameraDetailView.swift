import SwiftUI

@MainActor
struct CameraDetailView: View {
    let camera: Camera
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var reloadID = UUID()
    @State private var ptzModel = PTZControlModel()

    var body: some View {
        VStack(spacing: 0) {
            CameraStreamView(camera: camera, mode: .full)
                .id(reloadID)

            Divider()

            if shouldShowPTZControls, let status = ptzModel.status {
                PTZStatusView(status: status)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(camera.name)
                        .font(.headline)

                    Text(camera.urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }

                Spacer()

                if shouldShowPTZControls {
                    PTZControlPanel(camera: camera, model: ptzModel)
                }

                Button {
                    reloadStream()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload Stream")

                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Edit Camera")

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete Camera")
            }
            .padding()
        }
        .navigationTitle(camera.name)
        .onReceive(NotificationCenter.default.publisher(for: .reloadSelectedCamera)) { _ in
            reloadStream()
        }
    }

    private func reloadStream() {
        reloadID = UUID()
        AppLoggers.streams.info("Reloaded stream for camera \(camera.id.uuidString, privacy: .public)")
    }

    private var shouldShowPTZControls: Bool {
        camera.isPTZEnabled && !camera.requiresUnavailablePassword && camera.streamKind != .unknown
    }
}

@MainActor
private struct PTZControlPanel: View {
    let camera: Camera
    let model: PTZControlModel

    var body: some View {
        HStack(spacing: 6) {
            PTZHoldButton(systemImage: "arrow.up.left", command: .leftUp, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.up", command: .up, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.up.right", command: .rightUp, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.left", command: .left, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.right", command: .right, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.down.left", command: .leftDown, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.down", command: .down, camera: camera, model: model)
            PTZHoldButton(systemImage: "arrow.down.right", command: .rightDown, camera: camera, model: model)

            Divider()
                .frame(height: 22)

            PTZHoldButton(systemImage: "minus.magnifyingglass", command: .zoomOut, camera: camera, model: model)
            PTZHoldButton(systemImage: "plus.magnifyingglass", command: .zoomIn, camera: camera, model: model)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

@MainActor
private struct PTZStatusView: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial)
    }
}

@MainActor
private struct PTZHoldButton: View {
    let systemImage: String
    let command: PTZCommand
    let camera: Camera
    let model: PTZControlModel

    @State private var isPressing = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 28, height: 26)
            .background(.primary.opacity(isPressing ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressing else { return }
                        isPressing = true
                        model.start(command, camera: camera)
                    }
                    .onEnded { _ in
                        isPressing = false
                        model.stop(command, camera: camera)
                    }
            )
            .help(command.rawValue)
    }
}
