import SwiftUI

struct SidebarView: View {
    @Environment(CameraStore.self) private var store
    @Binding var selection: SidebarSelection
    let onAddCamera: () -> Void
    let onDiscoverCameras: () -> Void
    let onEditCamera: (Camera) -> Void
    let onDeleteCamera: (Camera) -> Void
    let onAddCameraView: () -> Void
    let onEditCameraView: (CameraViewLayout) -> Void
    let onDeleteCameraView: (CameraViewLayout) -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Cameras", systemImage: "square.grid.2x2")
                    .tag(SidebarSelection.overview)

                Label("Views", systemImage: "rectangle.grid.2x2")
                    .tag(SidebarSelection.views)
                    .contextMenu {
                        Button("New View") {
                            onAddCameraView()
                        }
                    }
            }

            if !store.cameraViews.isEmpty {
                Section("Saved Views") {
                    ForEach(store.cameraViews) { cameraView in
                        CameraViewSidebarRow(cameraView: cameraView, camerasCount: store.cameras(in: cameraView).count)
                            .tag(SidebarSelection.cameraView(cameraView.id))
                            .contextMenu {
                                Button("Edit") {
                                    onEditCameraView(cameraView)
                                }

                                Button("Delete", role: .destructive) {
                                    onDeleteCameraView(cameraView)
                                }
                            }
                    }
                }
            }

            ForEach(store.locations, id: \.self) { location in
                Section(location) {
                    ForEach(store.cameras.filter { $0.locationLabel == location }) { camera in
                        CameraSidebarRow(camera: camera)
                            .tag(SidebarSelection.camera(camera.id))
                            .contextMenu {
                                Button("Edit") {
                                    onEditCamera(camera)
                                }

                                Button("Delete", role: .destructive) {
                                    onDeleteCamera(camera)
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                Button {
                    onDiscoverCameras()
                } label: {
                    Label("Discover", systemImage: "network")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)

                Button {
                    onAddCamera()
                } label: {
                    Label("Add Camera", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 340)
    }
}

private struct CameraSidebarRow: View {
    let camera: Camera

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: camera.isFavorite ? "star.fill" : "video")
                .foregroundStyle(camera.isFavorite ? .yellow : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(camera.name)
                    .lineLimit(1)

                Text(camera.hostLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct CameraViewSidebarRow: View {
    let cameraView: CameraViewLayout
    let camerasCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.grid.2x2")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(cameraView.name)
                    .lineLimit(1)

                Text("\(camerasCount) camera\(camerasCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
