import SwiftUI

struct CameraFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let camera: Camera?
    private let isNewCamera: Bool
    private let onSave: (Camera) -> Void

    @State private var name: String
    @State private var urlString: String
    @State private var location: String
    @State private var notes: String
    @State private var isFavorite: Bool
    @State private var username: String
    @State private var password: String
    @State private var isPTZEnabled: Bool
    @State private var ptzPort: Int
    @State private var ptzChannel: Int
    @State private var ptzSpeed: Int
    @State private var qualityPreset: StreamQualityPreset
    @State private var encodingMode: StreamEncodingMode

    init(camera: Camera?, isNewCamera: Bool? = nil, onSave: @escaping (Camera) -> Void) {
        self.camera = camera
        self.isNewCamera = isNewCamera ?? (camera == nil)
        self.onSave = onSave
        _name = State(initialValue: camera?.name ?? "")
        _urlString = State(initialValue: camera?.urlString ?? "")
        _location = State(initialValue: camera?.location ?? "")
        _notes = State(initialValue: camera?.notes ?? "")
        _isFavorite = State(initialValue: camera?.isFavorite ?? false)
        _username = State(initialValue: camera?.username ?? "")
        _password = State(initialValue: camera?.resolvedPassword ?? "")
        _isPTZEnabled = State(initialValue: camera?.isPTZEnabled ?? true)
        _ptzPort = State(initialValue: camera?.ptzPort ?? 80)
        _ptzChannel = State(initialValue: camera?.ptzChannel ?? 1)
        _ptzSpeed = State(initialValue: camera?.ptzSpeed ?? 4)
        _qualityPreset = State(initialValue: camera?.qualityPreset ?? .balanced)
        _encodingMode = State(initialValue: camera?.encodingMode ?? .lowCPU)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNewCamera ? "Add Camera" : "Edit Camera")
                .font(.title2.weight(.semibold))
                .padding([.horizontal, .top], 22)
                .padding(.bottom, 14)

            Form {
                TextField("Name", text: $name)

                TextField("Stream URL", text: $urlString, prompt: Text("http://192.168.1.20/video.mjpg"))
                    .textContentType(.URL)

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                TextField("Location", text: $location, prompt: Text("Front Door, Garage, Office"))

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...5)

                Toggle("Favorite", isOn: $isFavorite)

                Section("Quality") {
                    Picker("Playback", selection: $qualityPreset) {
                        ForEach(StreamQualityPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Encoder", selection: $encodingMode) {
                        ForEach(StreamEncodingMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("PTZ") {
                    Toggle("Show PTZ controls", isOn: $isPTZEnabled)

                    Stepper("HTTP port: \(ptzPort)", value: $ptzPort, in: 1...65_535)
                        .disabled(!isPTZEnabled)

                    Stepper("Channel: \(ptzChannel)", value: $ptzChannel, in: 1...64)
                        .disabled(!isPTZEnabled)

                    Stepper("Speed: \(ptzSpeed)", value: $ptzSpeed, in: 1...8)
                        .disabled(!isPTZEnabled)
                }

                if !urlString.isEmpty, parsedURL == nil {
                    Label("Enter a complete URL with http://, https://, or rtsp://.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 12)

            Divider()

            HStack {
                Text(streamKind.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isNewCamera ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedURL: URL? {
        URL(string: trimmedURLString)
    }

    private var streamKind: StreamKind {
        Camera(name: trimmedName.isEmpty ? "Camera" : trimmedName, urlString: trimmedURLString).streamKind
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && parsedURL != nil
    }

    private func save() {
        guard canSave else { return }

        let savedCamera = Camera(
            id: camera?.id ?? UUID(),
            name: trimmedName,
            urlString: trimmedURLString,
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isFavorite: isFavorite,
            createdAt: camera?.createdAt ?? Date(),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            isPTZEnabled: isPTZEnabled,
            ptzPort: ptzPort,
            ptzChannel: ptzChannel,
            ptzSpeed: ptzSpeed,
            qualityPreset: qualityPreset,
            encodingMode: encodingMode
        )

        onSave(savedCamera)
        dismiss()
    }
}
