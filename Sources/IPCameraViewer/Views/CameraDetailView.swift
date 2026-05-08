import SwiftUI

@MainActor
struct CameraDetailView: View {
    let camera: Camera
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var reloadID = UUID()
    @State private var ptzModel = PTZControlModel()
    @State private var imageAnalysis: ImageAnalysisResult?
    @State private var imageAnalysisError: String?
    @State private var isAnalyzingSingleFrame = false
    @State private var isLiveAnalyzing = false
    @State private var analysisURL: URL?
    @State private var analysisStreamKind: StreamKind?
    @State private var liveAnalysisTask: Task<Void, Never>?
    @State private var singleAnalysisTask: Task<Void, Never>?
    @State private var clearSingleAnalysisTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraStreamView(camera: camera, mode: .full) { url in
                    analysisURL = url
                    analysisStreamKind = resolvedAnalysisStreamKind(for: url)
                }
                .id(reloadID)

                if let imageAnalysis, imageAnalysis.hasRegions {
                    VisionRegionOverlay(regions: imageAnalysis.detectedRegions)
                        .allowsHitTesting(false)
                }
            }

            Divider()

            if shouldShowPTZControls, let status = ptzModel.status {
                PTZStatusView(status: status)
            }

            ImageAnalysisPanel(
                result: imageAnalysis,
                errorMessage: imageAnalysisError,
                isAnalyzing: isAnalyzingSingleFrame,
                isLiveAnalyzing: isLiveAnalyzing,
                isSupported: supportsImageAnalysis,
                supportMessage: imageAnalysisSupportMessage,
                onAnalyze: analyzeCurrentFrame,
                onToggleLive: toggleLiveAnalysis
            )

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
        .onChange(of: camera.id) {
            stopAnalysis()
        }
        .onDisappear {
            stopAnalysis()
        }
    }

    private func reloadStream() {
        stopAnalysis()
        reloadID = UUID()
        imageAnalysis = nil
        imageAnalysisError = nil
        analysisURL = nil
        analysisStreamKind = nil
        AppLoggers.streams.info("Reloaded stream for camera \(camera.id.uuidString, privacy: .public)")
    }

    private func analyzeCurrentFrame() {
        guard !isAnalyzingSingleFrame else { return }
        isAnalyzingSingleFrame = true
        imageAnalysisError = nil
        clearSingleAnalysisTask?.cancel()

        singleAnalysisTask?.cancel()
        singleAnalysisTask = Task {
            if let result = await runImageAnalysis() {
                imageAnalysis = result
                scheduleSingleAnalysisClear()
            }
            isAnalyzingSingleFrame = false
            singleAnalysisTask = nil
        }
    }

    private func toggleLiveAnalysis() {
        if isLiveAnalyzing {
            stopLiveAnalysis()
            return
        }

        isLiveAnalyzing = true
        clearSingleAnalysisTask?.cancel()
        liveAnalysisTask?.cancel()
        liveAnalysisTask = Task {
            while !Task.isCancelled {
                if let result = await runImageAnalysis() {
                    imageAnalysis = result
                }

                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func stopAnalysis() {
        stopLiveAnalysis()
        singleAnalysisTask?.cancel()
        singleAnalysisTask = nil
        clearSingleAnalysisTask?.cancel()
        clearSingleAnalysisTask = nil
        isAnalyzingSingleFrame = false
    }

    private func stopLiveAnalysis() {
        isLiveAnalyzing = false
        liveAnalysisTask?.cancel()
        liveAnalysisTask = nil
        imageAnalysis = nil
        imageAnalysisError = nil
    }

    private func scheduleSingleAnalysisClear() {
        guard !isLiveAnalyzing else { return }
        clearSingleAnalysisTask?.cancel()
        clearSingleAnalysisTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, !isLiveAnalyzing else { return }
            imageAnalysis = nil
            clearSingleAnalysisTask = nil
        }
    }

    private func runImageAnalysis() async -> ImageAnalysisResult? {
        do {
            if let analysisURL, let analysisStreamKind {
                return try await ImageAnalysisService().analyze(url: analysisURL, streamKind: analysisStreamKind)
            }

            return try await ImageAnalysisService().analyze(camera: camera)
        } catch {
            imageAnalysisError = error.localizedDescription
            if !isLiveAnalyzing {
                imageAnalysis = nil
            }
            return nil
        }
    }

    private var shouldShowPTZControls: Bool {
        camera.isPTZEnabled && !camera.requiresUnavailablePassword && camera.streamKind != .unknown
    }

    private var supportsImageAnalysis: Bool {
        if let analysisStreamKind {
            return ImageAnalysisService.isAvailable(for: analysisStreamKind)
        }

        return ImageAnalysisService.isAvailable(for: camera.streamKind)
    }

    private var imageAnalysisSupportMessage: String {
        if camera.streamKind == .rtsp && analysisURL == nil {
            return ImageAnalysisService.availabilityMessage(for: .rtsp)
        }

        return ImageAnalysisService.availabilityMessage(for: analysisStreamKind ?? camera.streamKind)
    }

    private func resolvedAnalysisStreamKind(for url: URL?) -> StreamKind? {
        guard let url else { return nil }
        if url.path(percentEncoded: false).lowercased().hasSuffix(".m3u8") {
            return .hls
        }

        return camera.streamKind == .rtsp ? .hls : camera.streamKind
    }
}

private struct VisionRegionOverlay: View {
    let regions: [DetectedImageRegion]

    var body: some View {
        GeometryReader { proxy in
            ForEach(regions) { region in
                let rect = overlayRect(for: region.boundingBox, in: proxy.size)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(.yellow, lineWidth: 2)
                        .background(.yellow.opacity(0.08))

                    Text("\(region.label) \(region.confidenceLabel)")
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .offset(x: 3, y: 3)
                }
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            }
        }
    }

    private func overlayRect(for normalizedRect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalizedRect.minX * size.width,
            y: (1 - normalizedRect.maxY) * size.height,
            width: normalizedRect.width * size.width,
            height: normalizedRect.height * size.height
        )
    }
}

@MainActor
private struct ImageAnalysisPanel: View {
    let result: ImageAnalysisResult?
    let errorMessage: String?
    let isAnalyzing: Bool
    let isLiveAnalyzing: Bool
    let isSupported: Bool
    let supportMessage: String
    let onAnalyze: () -> Void
    let onToggleLive: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Vision Analysis")
                        .font(.headline)

                    Spacer()

                    if let result {
                        Text(result.capturedAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let result {
                    Text(result.summary)
                        .font(.subheadline)

                    if result.hasObjects {
                        FlowLayout(spacing: 6) {
                            ForEach(result.detectedObjects) { object in
                                Text("\(object.label) \(object.confidenceLabel)")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.primary.opacity(0.08), in: Capsule())
                            }
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(supportMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                onAnalyze()
            } label: {
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Label("Analyze", systemImage: "eye")
                }
            }
            .disabled(isAnalyzing || !isSupported)
            .help("Analyze Current Frame")

            Toggle(isOn: Binding(get: { isLiveAnalyzing }, set: { _ in onToggleLive() })) {
                Label("Live", systemImage: isLiveAnalyzing ? "dot.radiowaves.left.and.right" : "play.circle")
            }
            .toggleStyle(.button)
            .disabled(!isSupported)
            .help("Analyze Every Second")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(proposal: proposal, subviews: subviews)
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in rows(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(proposal: ProposedViewSize, subviews: Subviews) -> [FlowRow] {
        let maxWidth = proposal.width ?? 0
        var rows: [FlowRow] = []
        var currentRow = FlowRow()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = currentRow.items.isEmpty ? 0 : currentRow.width + spacing

            if nextX + size.width > maxWidth, !currentRow.items.isEmpty {
                rows.append(currentRow)
                currentRow = FlowRow(y: (rows.last?.y ?? 0) + (rows.last?.height ?? 0) + spacing)
            }

            let itemX = currentRow.items.isEmpty ? 0 : currentRow.width + spacing
            currentRow.items.append(FlowItem(index: index, x: itemX, size: size))
            currentRow.width = itemX + size.width
            currentRow.height = max(currentRow.height, size.height)
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct FlowRow {
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        var items: [FlowItem] = []
    }

    private struct FlowItem {
        var index: Int
        var x: CGFloat
        var size: CGSize
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
