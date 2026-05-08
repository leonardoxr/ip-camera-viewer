import Foundation

enum CameraSortOrder: String, CaseIterable, Identifiable {
    case name
    case location
    case newest
    case stream

    var id: String { rawValue }

    var label: String {
        switch self {
        case .name:
            "Name"
        case .location:
            "Location"
        case .newest:
            "Newest"
        case .stream:
            "Stream Type"
        }
    }

    func sort(_ cameras: [Camera]) -> [Camera] {
        cameras.sorted {
            if $0.isFavorite != $1.isFavorite {
                return $0.isFavorite && !$1.isFavorite
            }

            switch self {
            case .name:
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            case .location:
                if $0.locationLabel != $1.locationLabel {
                    return $0.locationLabel.localizedCaseInsensitiveCompare($1.locationLabel) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            case .newest:
                return $0.createdAt > $1.createdAt
            case .stream:
                if $0.streamKind.label != $1.streamKind.label {
                    return $0.streamKind.label.localizedCaseInsensitiveCompare($1.streamKind.label) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }
}
