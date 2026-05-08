import Foundation

enum StreamQualityPreset: String, Codable, CaseIterable, Identifiable, Hashable {
    case high
    case balanced
    case fast
    case stable

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high:
            "High"
        case .balanced:
            "Balanced"
        case .fast:
            "Fast"
        case .stable:
            "Stable"
        }
    }

    var dahuaSubtype: String {
        switch self {
        case .high, .balanced:
            "0"
        case .fast, .stable:
            "1"
        }
    }

    var bridgeHeight: Int {
        switch self {
        case .high:
            1080
        case .balanced:
            720
        case .fast:
            540
        case .stable:
            360
        }
    }

    var bridgeFPS: Int {
        switch self {
        case .high:
            20
        case .balanced:
            15
        case .fast:
            12
        case .stable:
            8
        }
    }

    var videoBitrate: String {
        switch self {
        case .high:
            "3500k"
        case .balanced:
            "1800k"
        case .fast:
            "1000k"
        case .stable:
            "600k"
        }
    }

    var encoderPreset: String {
        switch self {
        case .high:
            "veryfast"
        case .balanced, .fast, .stable:
            "ultrafast"
        }
    }

    var compositeTileSize: String {
        let dimensions = compositeTileDimensions
        return "\(dimensions.width)x\(dimensions.height)"
    }

    var compositeTileDimensions: (width: Int, height: Int) {
        switch self {
        case .high:
            (960, 540)
        case .balanced:
            (640, 360)
        case .fast:
            (480, 270)
        case .stable:
            (426, 240)
        }
    }
}
