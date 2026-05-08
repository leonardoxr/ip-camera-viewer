import Foundation

enum StreamEncodingMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case lowCPU
    case compatibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lowCPU:
            "Low CPU"
        case .compatibility:
            "Compatibility"
        }
    }

    var ffmpegCodec: String {
        switch self {
        case .lowCPU:
            "h264_videotoolbox"
        case .compatibility:
            "libx264"
        }
    }
}
