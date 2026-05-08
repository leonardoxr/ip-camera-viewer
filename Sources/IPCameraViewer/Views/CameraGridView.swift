import SwiftUI

@MainActor
struct CameraGridView: View {
    let cameras: [Camera]
    @Binding var searchText: String
    @Binding var isGroupedByLocation: Bool
    let onSelect: (Camera) -> Void

    @AppStorage(AppPreferenceKey.cameraSortOrder) private var sortOrderRawValue = CameraSortOrder.name.rawValue

    private let columns = [
        GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 16)
    ]

    var body: some View {
        Group {
            if cameras.isEmpty {
                EmptyCameraState(onSelect: onSelect)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        libraryHeader

                        if filteredCameras.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(minHeight: 280)
                        } else if isGroupedByLocation {
                            ForEach(groupedCameras, id: \.location) { group in
                                CameraGroupSection(
                                    title: group.location,
                                    cameras: group.cameras,
                                    columns: columns,
                                    onSelect: onSelect
                                )
                            }
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredCameras) { camera in
                                    CameraPreviewTile(camera: camera) {
                                        onSelect(camera)
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("All Cameras")
    }

    private var libraryHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(cameras.count) saved")
                        .font(.title2.weight(.semibold))

                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("Sort", selection: sortOrder) {
                    ForEach(CameraSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Toggle(isOn: $isGroupedByLocation) {
                    Label("Group", systemImage: "folder")
                }
                .toggleStyle(.button)
                .help("Group by Location")
            }
        }
    }

    private var summaryText: String {
        let favoritesCount = cameras.filter(\.isFavorite).count
        let locationsCount = Set(cameras.map(\.locationLabel)).count
        return "\(favoritesCount) favorite\(favoritesCount == 1 ? "" : "s") across \(locationsCount) location\(locationsCount == 1 ? "" : "s")"
    }

    private var filteredCameras: [Camera] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchingCameras = cameras.filter { camera in
            guard !trimmedSearch.isEmpty else { return true }
            return [
                camera.name,
                camera.locationLabel,
                camera.hostLabel,
                camera.urlString,
                camera.notes,
                camera.streamKind.label
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(trimmedSearch)
        }

        return currentSortOrder.sort(matchingCameras)
    }

    private var groupedCameras: [CameraGroup] {
        Dictionary(grouping: filteredCameras, by: \.locationLabel)
            .map { CameraGroup(location: $0.key, cameras: $0.value) }
            .sorted { $0.location.localizedCaseInsensitiveCompare($1.location) == .orderedAscending }
    }

    private var currentSortOrder: CameraSortOrder {
        CameraSortOrder(rawValue: sortOrderRawValue) ?? .name
    }

    private var sortOrder: Binding<CameraSortOrder> {
        Binding {
            currentSortOrder
        } set: { newValue in
            sortOrderRawValue = newValue.rawValue
            AppLoggers.commands.info("Camera sort order changed to \(newValue.rawValue, privacy: .public)")
        }
    }
}

@MainActor
private struct CameraPreviewTile: View {
    let camera: Camera
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                CameraStreamView(camera: camera, mode: .preview)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(camera.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(camera.streamKind.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if camera.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)

                HStack(spacing: 6) {
                    Label(camera.locationLabel, systemImage: "folder")
                    Text(camera.hostLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct CameraGroupSection: View {
    let title: String
    let cameras: [Camera]
    let columns: [GridItem]
    let onSelect: (Camera) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: "folder")
                    .font(.headline)

                Text("\(cameras.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(cameras) { camera in
                    CameraPreviewTile(camera: camera) {
                        onSelect(camera)
                    }
                }
            }
        }
    }
}

private struct CameraGroup {
    let location: String
    let cameras: [Camera]
}

@MainActor
private struct EmptyCameraState: View {
    @Environment(CameraStore.self) private var store
    @Environment(DiscoveryStore.self) private var discoveryStore
    let onSelect: (Camera) -> Void

    var body: some View {
        if !availableDiscoveries.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Discovered Cameras")
                            .font(.title2.weight(.semibold))

                        Text("Devices found by ONVIF, Bonjour, UPnP, or local port scan.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(availableDiscoveries) { camera in
                        HStack(spacing: 12) {
                            Image(systemName: "video.badge.checkmark")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(camera.name)
                                    .font(.headline)

                                Text(camera.serviceURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }

                            Spacer()

                            Button("Add") {
                                let savedCamera = store.add(camera)
                                onSelect(savedCamera)
                            }
                        }
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(24)
            }
        } else if discoveryStore.isScanning {
            ContentUnavailableView {
                Label("Scanning for Cameras", systemImage: "network")
            } description: {
                Text("Looking for IP cameras using ONVIF, Bonjour, UPnP, and common HTTP/RTSP ports.")
            }
        } else {
            ContentUnavailableView {
                Label("No Cameras", systemImage: "video.slash")
            } description: {
                Text("Add an HTTP, MJPEG, or HLS camera stream to start viewing.")
            } actions: {
                Button("Discover") {
                    discoveryStore.scan()
                }

                Button("Add Camera") {
                    NotificationCenter.default.post(name: .showAddCameraSheet, object: nil)
                }
            }
        }
    }

    private var availableDiscoveries: [DiscoveredCamera] {
        discoveryStore.discoveredCameras.filter { !store.contains($0) }
    }
}
