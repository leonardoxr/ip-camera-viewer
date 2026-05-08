import SwiftUI

struct CameraViewsManagerView: View {
    let cameraViews: [CameraViewLayout]
    let cameras: [Camera]
    let onCreate: () -> Void
    let onOpen: (CameraViewLayout) -> Void
    let onEdit: (CameraViewLayout) -> Void
    let onDelete: (CameraViewLayout) -> Void

    var body: some View {
        Group {
            if cameraViews.isEmpty {
                ContentUnavailableView {
                    Label("No Views", systemImage: "rectangle.grid.2x2")
                } description: {
                    Text("Create a grid view to watch multiple cameras at once.")
                } actions: {
                    Button("New View", action: onCreate)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(cameraViews) { cameraView in
                                CameraViewSummaryTile(
                                    cameraView: cameraView,
                                    cameras: cameras(for: cameraView),
                                    onOpen: { onOpen(cameraView) },
                                    onEdit: { onEdit(cameraView) },
                                    onDelete: { onDelete(cameraView) }
                                )
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("Views")
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(cameraViews.count) view\(cameraViews.count == 1 ? "" : "s")")
                    .font(.title2.weight(.semibold))

                Text("Reusable multi-camera grids for live monitoring.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onCreate) {
                Label("New View", systemImage: "plus")
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 300, maximum: 440), spacing: 14)]
    }

    private func cameras(for cameraView: CameraViewLayout) -> [Camera] {
        cameraView.cameraIDs.compactMap { cameraID in
            cameras.first { $0.id == cameraID }
        }
    }
}

private struct CameraViewSummaryTile: View {
    let cameraView: CameraViewLayout
    let cameras: [Camera]
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(cameraView.name, systemImage: "rectangle.grid.2x2")
                            .font(.headline)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if cameras.isEmpty {
                Text("No cameras selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(cameras.prefix(4)) { camera in
                        Label(camera.name, systemImage: "video")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if cameras.count > 4 {
                        Text("+ \(cameras.count - 4) more")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            HStack {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
            .labelStyle(.iconOnly)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var summaryText: String {
        if cameraView.fitsAvailableWidth {
            return "\(cameras.count) camera\(cameras.count == 1 ? "" : "s") · \(cameraView.columnCount) per row · fit width"
        }

        return "\(cameras.count) camera\(cameras.count == 1 ? "" : "s") · \(cameraView.columnCount) per row · \(cameraView.tileWidth) px min"
    }
}
