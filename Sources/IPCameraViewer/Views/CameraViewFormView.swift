import SwiftUI

@MainActor
struct CameraViewFormView: View {
    @Environment(\.dismiss) private var dismiss

    let cameraView: CameraViewLayout?
    let cameras: [Camera]
    let onSave: (CameraViewLayout) -> Void

    @State private var name: String
    @State private var columnCount: Int
    @State private var tileWidth: Int
    @State private var fitsAvailableWidth: Bool
    @State private var qualityPreset: StreamQualityPreset
    @State private var encodingMode: StreamEncodingMode
    @State private var selectedCameraIDs: [Camera.ID]

    init(cameraView: CameraViewLayout?, cameras: [Camera], onSave: @escaping (CameraViewLayout) -> Void) {
        self.cameraView = cameraView
        self.cameras = cameras
        self.onSave = onSave

        _name = State(initialValue: cameraView?.name ?? "New View")
        _columnCount = State(initialValue: cameraView?.columnCount ?? 2)
        _tileWidth = State(initialValue: cameraView?.tileWidth ?? 320)
        _fitsAvailableWidth = State(initialValue: cameraView?.fitsAvailableWidth ?? false)
        _qualityPreset = State(initialValue: cameraView?.qualityPreset ?? .balanced)
        _encodingMode = State(initialValue: cameraView?.encodingMode ?? .lowCPU)
        _selectedCameraIDs = State(initialValue: cameraView?.cameraIDs ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("View") {
                    TextField("Name", text: $name)

                    Stepper("Cameras per row: \(columnCount)", value: $columnCount, in: 1...6)

                    Toggle("Fit available width", isOn: $fitsAvailableWidth)

                    Stepper("Minimum tile width: \(tileWidth) px", value: $tileWidth, in: 180...520, step: 20)
                        .disabled(fitsAvailableWidth)

                    Picker("Cast quality", selection: $qualityPreset) {
                        ForEach(StreamQualityPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Cast encoder", selection: $encodingMode) {
                        ForEach(StreamEncodingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Included Cameras") {
                    if selectedCameras.isEmpty {
                        Text("No cameras selected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(selectedCameras) { camera in
                            SelectedCameraRow(
                                camera: camera,
                                canMoveUp: canMove(camera.id, offset: -1),
                                canMoveDown: canMove(camera.id, offset: 1),
                                onMoveUp: { move(camera.id, offset: -1) },
                                onMoveDown: { move(camera.id, offset: 1) },
                                onRemove: { remove(camera.id) }
                            )
                        }
                    }
                }

                Section("Available Cameras") {
                    if availableCameras.isEmpty {
                        Text(cameras.isEmpty ? "Add cameras before creating a view." : "All cameras are already included.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableCameras) { camera in
                            Button {
                                selectedCameraIDs.append(camera.id)
                            } label: {
                                Label(camera.name, systemImage: "plus.circle")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(cameraView == nil ? "New View" : "Edit View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCameras: [Camera] {
        selectedCameraIDs.compactMap { cameraID in
            cameras.first { $0.id == cameraID }
        }
    }

    private var availableCameras: [Camera] {
        let selectedIDs = Set(selectedCameraIDs)
        return cameras.filter { !selectedIDs.contains($0.id) }
    }

    private func canMove(_ cameraID: Camera.ID, offset: Int) -> Bool {
        guard let index = selectedCameraIDs.firstIndex(of: cameraID) else { return false }
        return selectedCameraIDs.indices.contains(index + offset)
    }

    private func move(_ cameraID: Camera.ID, offset: Int) {
        guard let index = selectedCameraIDs.firstIndex(of: cameraID) else { return }
        let newIndex = index + offset
        guard selectedCameraIDs.indices.contains(newIndex) else { return }
        selectedCameraIDs.swapAt(index, newIndex)
    }

    private func remove(_ cameraID: Camera.ID) {
        selectedCameraIDs.removeAll { $0 == cameraID }
    }

    private func save() {
        let cameraView = CameraViewLayout(
            id: cameraView?.id ?? UUID(),
            name: trimmedName,
            cameraIDs: selectedCameraIDs,
            columnCount: columnCount,
            tileWidth: tileWidth,
            fitsAvailableWidth: fitsAvailableWidth,
            qualityPreset: qualityPreset,
            encodingMode: encodingMode,
            createdAt: cameraView?.createdAt ?? Date()
        )
        onSave(cameraView)
        dismiss()
    }
}

@MainActor
private struct SelectedCameraRow: View {
    let camera: Camera
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(camera.name, systemImage: "video")
                .lineLimit(1)

            Spacer()

            Button(action: onMoveUp) {
                Image(systemName: "arrow.up")
            }
            .disabled(!canMoveUp)
            .help("Move Up")

            Button(action: onMoveDown) {
                Image(systemName: "arrow.down")
            }
            .disabled(!canMoveDown)
            .help("Move Down")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle")
            }
            .help("Remove")
        }
        .buttonStyle(.borderless)
    }
}
