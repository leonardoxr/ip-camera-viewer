import Foundation

struct CameraViewLayout: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var cameraIDs: [Camera.ID]
    var columnCount: Int
    var tileWidth: Int
    var fitsAvailableWidth: Bool
    var qualityPreset: StreamQualityPreset
    var encodingMode: StreamEncodingMode
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        cameraIDs: [Camera.ID] = [],
        columnCount: Int = 2,
        tileWidth: Int = 320,
        fitsAvailableWidth: Bool = false,
        qualityPreset: StreamQualityPreset = .balanced,
        encodingMode: StreamEncodingMode = .lowCPU,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.cameraIDs = cameraIDs
        self.columnCount = Self.clampedColumnCount(columnCount)
        self.tileWidth = Self.clampedTileWidth(tileWidth)
        self.fitsAvailableWidth = fitsAvailableWidth
        self.qualityPreset = qualityPreset
        self.encodingMode = encodingMode
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case cameraIDs
        case columnCount
        case tileWidth
        case fitsAvailableWidth
        case qualityPreset
        case encodingMode
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cameraIDs = try container.decodeIfPresent([Camera.ID].self, forKey: .cameraIDs) ?? []
        columnCount = Self.clampedColumnCount(try container.decodeIfPresent(Int.self, forKey: .columnCount) ?? 2)
        tileWidth = Self.clampedTileWidth(try container.decodeIfPresent(Int.self, forKey: .tileWidth) ?? 320)
        fitsAvailableWidth = try container.decodeIfPresent(Bool.self, forKey: .fitsAvailableWidth) ?? false
        qualityPreset = try container.decodeIfPresent(StreamQualityPreset.self, forKey: .qualityPreset) ?? .balanced
        encodingMode = try container.decodeIfPresent(StreamEncodingMode.self, forKey: .encodingMode) ?? .lowCPU
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    private static func clampedColumnCount(_ value: Int) -> Int {
        min(max(value, 1), 6)
    }

    private static func clampedTileWidth(_ value: Int) -> Int {
        min(max(value, 180), 520)
    }
}
