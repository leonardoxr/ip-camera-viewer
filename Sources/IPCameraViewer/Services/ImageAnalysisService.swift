import AppKit
import AVFoundation
import Foundation
import Vision

enum ImageAnalysisError: LocalizedError {
    case unsupportedStream
    case noImageData
    case noClassifications
    case missingFFmpeg
    case frameExtractionFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unsupportedStream:
            "This stream did not provide a still image that Vision can inspect."
        case .noImageData:
            "No readable image frame was found."
        case .noClassifications:
            "Vision did not find recognizable objects in this frame."
        case .missingFFmpeg:
            "Install ffmpeg to analyze RTSP/HLS camera frames."
        case .frameExtractionFailed(let message):
            "Could not extract a frame from the stream. \(message)"
        case .timedOut:
            "Frame analysis timed out. Try again after the stream has been playing for a few seconds."
        }
    }
}

struct ImageAnalysisService {
    static func isAvailable(for streamKind: StreamKind) -> Bool {
        switch streamKind {
        case .web:
            true
        case .hls:
            RTSPBridgeSession.ffmpegExecutableURL() != nil
        case .rtsp, .unknown:
            false
        }
    }

    static func availabilityMessage(for streamKind: StreamKind) -> String {
        switch streamKind {
        case .web:
            "Analyze a still frame locally with Apple Vision."
        case .hls:
            if RTSPBridgeSession.ffmpegExecutableURL() == nil {
                "Install ffmpeg to analyze HLS/RTSP camera frames."
            } else {
                "Analyze a still frame locally with Apple Vision."
            }
        case .rtsp:
            "Waiting for the RTSP bridge to produce an analyzable HLS frame."
        case .unknown:
            "Vision analysis supports HTTP image snapshots and HLS streams."
        }
    }

    func analyze(camera: Camera) async throws -> ImageAnalysisResult {
        guard let url = camera.playbackURL else {
            throw ImageAnalysisError.unsupportedStream
        }

        let image = try await snapshotImage(from: url, streamKind: camera.streamKind)
        return try await analyze(image: image)
    }

    func analyze(url: URL, streamKind: StreamKind) async throws -> ImageAnalysisResult {
        try await withTimeout(seconds: 8) {
            let image = try await snapshotImage(from: url, streamKind: streamKind)
            return try await analyze(image: image)
        }
    }

    private func analyze(image: CGImage) async throws -> ImageAnalysisResult {
        let classifications = try await classify(image: image)
        let regions = try await detectRegions(image: image)
        let objects = Self.mergedObjects(
            classifiedObjects: Self.homeCameraObjects(from: classifications),
            regions: regions
        )

        guard !objects.isEmpty else {
            throw ImageAnalysisError.noClassifications
        }

        return ImageAnalysisResult(
            summary: Self.summary(for: objects),
            detectedObjects: Array(objects),
            detectedRegions: regions,
            capturedAt: Date()
        )
    }

    private func snapshotImage(from url: URL, streamKind: StreamKind) async throws -> CGImage {
        switch streamKind {
        case .web:
            return try await stillImageData(from: url)
        case .hls:
            return try await hlsFrame(from: url)
        case .rtsp:
            throw ImageAnalysisError.unsupportedStream
        case .unknown:
            throw ImageAnalysisError.unsupportedStream
        }
    }

    private func hlsFrame(from url: URL) async throws -> CGImage {
        if let segmentURL = try await latestSegmentURL(from: url) {
            return try await ffmpegFrame(from: segmentURL)
        }

        return try await ffmpegFrame(from: url)
    }

    private func latestSegmentURL(from playlistURL: URL) async throws -> URL? {
        let (data, _) = try await URLSession.shared.data(from: playlistURL)
        guard let playlist = String(data: data, encoding: .utf8) else {
            return nil
        }

        let segmentPath = playlist
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last { !$0.isEmpty && !$0.hasPrefix("#") }

        guard let segmentPath else {
            return nil
        }

        return URL(string: segmentPath, relativeTo: playlistURL)?.absoluteURL
    }

    private func stillImageData(from url: URL) async throws -> CGImage {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageAnalysisError.noImageData
        }

        return cgImage
    }

    private func videoFrame(from url: URL) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 600))]) { _, image, _, result, error in
                if let image, result == .succeeded {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ImageAnalysisError.noImageData)
                }
            }
        }
    }

    private func ffmpegFrame(from url: URL) async throws -> CGImage {
        guard let ffmpegURL = RTSPBridgeSession.ffmpegExecutableURL() else {
            throw ImageAnalysisError.missingFFmpeg
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "IPCameraViewer", directoryHint: .isDirectory)
            .appending(path: "VisionFrame-\(UUID().uuidString).jpg")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        let processBox = ProcessBox(process)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let errorPipe = Pipe()
                process.executableURL = ffmpegURL
                process.arguments = [
                    "-hide_banner",
                    "-loglevel", "error",
                    "-y",
                    "-i", url.absoluteString,
                    "-frames:v", "1",
                    "-q:v", "2",
                    outputURL.path
                ]
                process.standardError = errorPipe
                process.terminationHandler = { process in
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMessage = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ImageAnalysisError.frameExtractionFailed(errorMessage))
                    }
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            processBox.terminate()
        }

        guard let image = NSImage(contentsOf: outputURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImageAnalysisError.noImageData
        }

        return cgImage
    }

    private func withTimeout<T: Sendable>(seconds: UInt64, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw ImageAnalysisError.timedOut
            }

            guard let result = try await group.next() else {
                throw ImageAnalysisError.timedOut
            }

            group.cancelAll()
            return result
        }
    }

    private func classify(image: CGImage) async throws -> [ImageClassification] {
        try await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            guard let observations = request.results, !observations.isEmpty else {
                throw ImageAnalysisError.noClassifications
            }

            return observations.map {
                ImageClassification(label: $0.identifier, confidence: $0.confidence)
            }
        }.value
    }

    private func detectRegions(image: CGImage) async throws -> [DetectedImageRegion] {
        try await Task.detached(priority: .userInitiated) {
            let personRequest = VNDetectHumanRectanglesRequest()
            personRequest.upperBodyOnly = false
            let animalRequest = VNRecognizeAnimalsRequest()
            let faceRequest = VNDetectFaceRectanglesRequest()

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([
                personRequest,
                animalRequest,
                faceRequest
            ])

            var regions: [DetectedImageRegion] = []

            regions.append(contentsOf: (personRequest.results ?? []).map {
                DetectedImageRegion(label: "Person", confidence: Double($0.confidence), boundingBox: $0.boundingBox)
            })

            regions.append(contentsOf: (animalRequest.results ?? []).compactMap { observation in
                guard let label = observation.labels.first else { return nil }
                return DetectedImageRegion(
                    label: Self.displayLabel(from: label.identifier),
                    confidence: Double(label.confidence),
                    boundingBox: observation.boundingBox
                )
            })

            regions.append(contentsOf: (faceRequest.results ?? []).map {
                DetectedImageRegion(label: "Face", confidence: Double($0.confidence), boundingBox: $0.boundingBox)
            })

            return regions
                .filter { $0.confidence >= 0.45 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(8)
                .map { $0 }
        }.value
    }

    private static func homeCameraObjects(from classifications: [ImageClassification]) -> [DetectedImageObject] {
        let candidates = classifications
            .flatMap { classification in
                labels(from: classification.label).map { label in
                    HomeCameraCandidate(
                        rawLabel: label,
                        displayLabel: displayLabel(from: label),
                        confidence: Double(classification.confidence),
                        priority: homeCameraPriority(for: label)
                    )
                }
            }
            .filter { candidate in
                if candidate.priority > 0 {
                    candidate.confidence >= 0.22
                } else {
                    candidate.confidence >= 0.32 && !ignoredClassificationLabels.contains(candidate.rawLabel)
                }
            }
            .sorted {
                let leftScore = $0.confidence + Double($0.priority) * 0.05
                let rightScore = $1.confidence + Double($1.priority) * 0.05
                return leftScore == rightScore ? $0.confidence > $1.confidence : leftScore > rightScore
            }

        var seenLabels = Set<String>()
        return candidates.compactMap { candidate in
            let normalizedLabel = normalized(candidate.displayLabel)
            guard !seenLabels.contains(normalizedLabel) else { return nil }
            seenLabels.insert(normalizedLabel)
            return DetectedImageObject(label: candidate.displayLabel, confidence: candidate.confidence)
        }
        .prefix(6)
        .map { $0 }
    }

    private static func mergedObjects(classifiedObjects: [DetectedImageObject], regions: [DetectedImageRegion]) -> [DetectedImageObject] {
        let regionObjects = regions.compactMap { region -> DetectedImageObject? in
            let normalizedLabel = normalized(region.label)
            guard normalizedLabel == "person" || animalLabels.contains(normalizedLabel) else {
                return nil
            }

            return DetectedImageObject(label: region.label, confidence: region.confidence)
        }

        let allObjects = regionObjects + classifiedObjects
        var bestByLabel: [String: DetectedImageObject] = [:]
        for object in allObjects {
            let key = normalized(object.label)
            if let existing = bestByLabel[key], existing.confidence >= object.confidence {
                continue
            }
            bestByLabel[key] = object
        }

        return bestByLabel.values
            .sorted { $0.confidence > $1.confidence }
            .prefix(6)
            .map { $0 }
    }

    private static func labels(from identifier: String) -> [String] {
        identifier
            .split(separator: ",")
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    private static func homeCameraPriority(for label: String) -> Int {
        let normalizedLabel = normalized(label)

        if peopleLabels.contains(normalizedLabel) {
            return 5
        }

        if animalLabels.contains(normalizedLabel) {
            return 5
        }

        if vehicleLabels.contains(normalizedLabel) {
            return 4
        }

        if deliveryLabels.contains(normalizedLabel) {
            return 4
        }

        if homeObjectLabels.contains(normalizedLabel) {
            return 3
        }

        if outdoorLabels.contains(normalizedLabel) {
            return 2
        }

        return 0
    }

    private static func displayLabel(from identifier: String) -> String {
        normalized(identifier)
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private static func summary(for objects: [DetectedImageObject]) -> String {
        let detected = objects.prefix(3).map(\.label).joined(separator: ", ")

        if containsStrong(objects, matching: peopleLabels) {
            return "Person likely visible near the camera. Other context: \(detected)."
        }

        if containsStrong(objects, matching: ["dog"]) {
            return "Dog likely visible. Barking cannot be confirmed from a still image without audio."
        }

        if containsStrong(objects, matching: animalLabels) {
            return "Animal likely visible near the house. Context: \(detected)."
        }

        if containsStrong(objects, matching: deliveryLabels) {
            return "Possible package or delivery-related object. Context: \(detected)."
        }

        if containsStrong(objects, matching: vehicleLabels) {
            return "Vehicle likely visible near the house. Context: \(detected)."
        }

        return "Possible scene context: \(detected)."
    }

    private static func containsStrong(_ objects: [DetectedImageObject], matching labels: Set<String>) -> Bool {
        objects.contains { object in
            labels.contains(normalized(object.label)) && object.confidence >= 0.30
        }
    }

    private static let peopleLabels: Set<String> = [
        "person", "people", "human", "man", "woman", "boy", "girl", "child", "pedestrian"
    ]

    private static let animalLabels: Set<String> = [
        "dog", "cat", "puppy", "kitten", "pet", "bird", "horse", "squirrel", "rabbit", "animal",
        "golden retriever", "labrador retriever", "retriever", "poodle", "terrier", "beagle", "bulldog",
        "chihuahua", "german shepherd", "rottweiler", "husky", "spaniel", "dachshund", "maltese",
        "persian cat", "siamese cat", "tabby cat"
    ]

    private static let vehicleLabels: Set<String> = [
        "car", "truck", "vehicle", "van", "pickup", "suv", "bus", "motorcycle", "bicycle", "bike"
    ]

    private static let deliveryLabels: Set<String> = [
        "package", "box", "carton", "mailbox", "envelope", "parcel", "backpack", "bag", "handbag", "suitcase"
    ]

    private static let homeObjectLabels: Set<String> = [
        "door", "window", "porch", "fence", "gate", "garage", "driveway", "stairs", "chair", "bench", "table",
        "trash can", "plant", "potted plant", "flowerpot", "lamp", "light", "security camera"
    ]

    private static let outdoorLabels: Set<String> = [
        "yard", "garden", "tree", "grass", "road", "street", "sidewalk", "path", "patio", "deck", "roof", "house", "building"
    ]

    private static let ignoredClassificationLabels: Set<String> = [
        "structure", "art", "illustration", "adult", "wood processed", "font", "screenshot", "graphics",
        "pattern", "design", "texture", "indoor", "outdoor", "room", "image", "photograph"
    ]

    private struct HomeCameraCandidate {
        var rawLabel: String
        var displayLabel: String
        var confidence: Double
        var priority: Int
    }

    private struct ImageClassification: Sendable {
        var label: String
        var confidence: Float
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private let process: Process

        init(_ process: Process) {
            self.process = process
        }

        func terminate() {
            lock.lock()
            defer {
                lock.unlock()
            }

            if process.isRunning {
                process.terminate()
            }
        }
    }
}
