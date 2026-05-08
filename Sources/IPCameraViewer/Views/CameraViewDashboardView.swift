import SwiftUI

struct CameraViewDashboardView: View {
    let cameraView: CameraViewLayout
    let cameras: [Camera]
    let onSelectCamera: (Camera) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isCastingView = false

    var body: some View {
        Group {
            if cameras.isEmpty {
                ContentUnavailableView {
                    Label("Empty View", systemImage: "rectangle.grid.2x2")
                } description: {
                    Text("Edit this view and choose cameras to show here.")
                } actions: {
                    Button("Edit View", action: onEdit)
                }
            } else if isCastingView {
                CompositeViewCastView(cameraView: cameraView, cameras: cameras) {
                    isCastingView = false
                }
            } else {
                GeometryReader { proxy in
                    ScrollView(cameraView.fitsAvailableWidth ? [.vertical] : [.vertical, .horizontal]) {
                        VStack(alignment: .leading, spacing: 16) {
                            header(width: layoutMetrics(for: proxy.size.width).gridWidth)

                            LazyVGrid(columns: columns(width: layoutMetrics(for: proxy.size.width).tileWidth), spacing: gridSpacing) {
                                ForEach(cameras) { camera in
                                    CameraViewStreamTile(camera: camera) {
                                        onSelectCamera(camera)
                                    }
                                    .frame(width: layoutMetrics(for: proxy.size.width).tileWidth)
                                }
                            }
                            .frame(width: layoutMetrics(for: proxy.size.width).gridWidth, alignment: .leading)
                        }
                        .padding(20)
                    }
                    .background {
                        if !cameraView.fitsAvailableWidth {
                            WindowMinimumSizeReader(
                                minSize: CGSize(width: minimumWindowWidth, height: 620),
                                fallbackMinSize: CGSize(width: 980, height: 620)
                            )
                        }
                    }
                    .onDisappear {
                        WindowMinimumSizeCoordinator.applyFallbackMinSize()
                    }
                }
            }
        }
        .navigationTitle(cameraView.name)
    }

    private func header(width: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(cameraView.name)
                    .font(.title2.weight(.semibold))

                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isCastingView = true
            } label: {
                Label("Cast View", systemImage: "airplayvideo")
            }
            .help("Create one AirPlay-capable stream for this view")

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func columns(width: CGFloat) -> [GridItem] {
        Array(
            repeating: GridItem(.fixed(width), spacing: gridSpacing),
            count: min(max(cameraView.columnCount, 1), 6)
        )
    }

    private var summaryText: String {
        let playbackSummary = "\(cameraView.qualityPreset.label) · \(cameraView.encodingMode.label)"
        if cameraView.fitsAvailableWidth {
            return "\(cameras.count) camera\(cameras.count == 1 ? "" : "s") · \(cameraView.columnCount) per row · fit width · \(playbackSummary)"
        }

        return "\(cameras.count) camera\(cameras.count == 1 ? "" : "s") · \(cameraView.columnCount) per row · \(cameraView.tileWidth) px minimum · \(playbackSummary)"
    }

    private var gridSpacing: CGFloat {
        14
    }

    private func layoutMetrics(for availableWidth: CGFloat) -> (tileWidth: CGFloat, gridWidth: CGFloat) {
        let columns = CGFloat(min(max(cameraView.columnCount, 1), 6))
        let spacingWidth = max(columns - 1, 0) * gridSpacing

        if cameraView.fitsAvailableWidth {
            let usableWidth = max(availableWidth - 40, 1)
            let tileWidth = max((usableWidth - spacingWidth) / columns, 160)
            return (tileWidth, columns * tileWidth + spacingWidth)
        }

        return (CGFloat(cameraView.tileWidth), minimumGridWidth)
    }

    private var minimumGridWidth: CGFloat {
        let columns = CGFloat(min(max(cameraView.columnCount, 1), 6))
        let tileWidth = CGFloat(cameraView.tileWidth)
        return columns * tileWidth + max(columns - 1, 0) * gridSpacing
    }

    private var minimumWindowWidth: CGFloat {
        let sidebarWidth: CGFloat = 288
        let splitterWidth: CGFloat = 1
        let contentPadding: CGFloat = 40
        let scrollAndChromeAllowance: CGFloat = 64
        return sidebarWidth + splitterWidth + minimumGridWidth + contentPadding + scrollAndChromeAllowance
    }
}

private struct CompositeViewCastView: View {
    let cameraView: CameraViewLayout
    let cameras: [Camera]
    let onStop: () -> Void

    @State private var bridge = CompositeViewBridgeSession()

    var body: some View {
        VStack(spacing: 0) {
            castHeader

            Divider()

            Group {
                switch bridge.state {
                case .idle, .starting:
                    StreamMessageView(
                        title: "Starting Cast View",
                        message: "Compositing this view into one AirPlay-capable HLS stream.",
                        systemImage: "airplayvideo",
                        showsProgress: true
                    )
                case .streaming(let playlistURL):
                    HLSCameraView(url: playlistURL)
                case .missingFFmpeg:
                    StreamMessageView(
                        title: "Install ffmpeg",
                        message: "Casting a view needs ffmpeg installed at /opt/homebrew/bin/ffmpeg or another standard PATH location.",
                        systemImage: "terminal"
                    )
                case .failed(let message):
                    StreamMessageView(
                        title: "Cast View Failed",
                        message: message,
                        systemImage: "exclamationmark.triangle"
                    )
                }
            }
            .background(Color.black)
        }
        .task(id: cameraView) {
            bridge.start(cameraView: cameraView, cameras: cameras)
        }
        .onDisappear {
            bridge.stop()
        }
    }

    private var castHeader: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(cameraView.name) Cast")
                    .font(.title2.weight(.semibold))

                Text(castSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onStop) {
                Label("Back to Grid", systemImage: "rectangle.grid.2x2")
            }
        }
        .padding(20)
    }

    private var castSubtitle: String {
        guard !bridge.skippedCameraNames.isEmpty else {
            return "One combined stream for AirPlay · \(cameraView.qualityPreset.label) · \(cameraView.encodingMode.label)"
        }

        return "One combined stream for AirPlay · \(cameraView.qualityPreset.label) · \(cameraView.encodingMode.label) · skipped \(bridge.skippedCameraNames.count) unavailable camera\(bridge.skippedCameraNames.count == 1 ? "" : "s")"
    }
}

private struct WindowMinimumSizeReader: NSViewRepresentable {
    let minSize: CGSize
    let fallbackMinSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            WindowMinimumSizeCoordinator.apply(minSize: minSize, fallbackMinSize: fallbackMinSize, from: view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            WindowMinimumSizeCoordinator.apply(minSize: minSize, fallbackMinSize: fallbackMinSize, from: view)
        }
    }
}

enum WindowMinimumSizeCoordinator {
    private static weak var currentWindow: NSWindow?
    private static var fallbackMinSize = CGSize(width: 980, height: 620)

    static func apply(minSize: CGSize, fallbackMinSize: CGSize, from view: NSView) {
        guard let window = view.window else { return }
        currentWindow = window
        self.fallbackMinSize = fallbackMinSize

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        let cappedWidth = visibleFrame.map { min(minSize.width, $0.width) } ?? minSize.width
        let cappedHeight = visibleFrame.map { min(minSize.height, $0.height) } ?? minSize.height
        let cappedMinSize = CGSize(width: cappedWidth, height: cappedHeight)

        if window.minSize != cappedMinSize {
            window.minSize = cappedMinSize
        }

        guard window.frame.width < cappedMinSize.width || window.frame.height < cappedMinSize.height else {
            return
        }

        var frame = window.frame
        frame.size.width = max(frame.width, cappedMinSize.width)
        frame.size.height = max(frame.height, cappedMinSize.height)

        if let visibleFrame {
            frame.size.width = min(frame.width, visibleFrame.width)
            frame.size.height = min(frame.height, visibleFrame.height)
            frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), visibleFrame.maxY - frame.height)
        }

        window.setFrame(frame, display: true, animate: true)
    }

    static func applyFallbackMinSize() {
        guard let window = currentWindow else { return }
        window.minSize = fallbackMinSize
    }
}

private struct CameraViewStreamTile: View {
    let camera: Camera
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CameraStreamView(camera: camera, mode: .full)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button(action: onSelect) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(camera.name)
                            .font(.headline)
                            .lineLimit(1)

                        Text(camera.hostLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
            }
            .buttonStyle(.plain)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .frame(maxWidth: .infinity)
    }
}
