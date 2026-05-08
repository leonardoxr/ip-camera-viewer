import Foundation

struct ImageAnalysisResult: Equatable {
    var summary: String
    var detectedObjects: [DetectedImageObject]
    var detectedRegions: [DetectedImageRegion]
    var capturedAt: Date

    var hasObjects: Bool {
        !detectedObjects.isEmpty
    }

    var hasRegions: Bool {
        !detectedRegions.isEmpty
    }
}

struct DetectedImageObject: Identifiable, Equatable {
    var id: String { "\(label)-\(Int(confidence * 1000))" }
    var label: String
    var confidence: Double

    var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

struct DetectedImageRegion: Identifiable, Equatable {
    var id = UUID()
    var label: String
    var confidence: Double
    var boundingBox: CGRect

    var confidenceLabel: String {
        "\(Int((confidence * 100).rounded()))%"
    }
}
