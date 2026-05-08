import Foundation

struct Camera: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var urlString: String
    var location: String
    var notes: String
    var isFavorite: Bool
    var createdAt: Date
    var username: String
    var password: String
    var isPTZEnabled: Bool
    var ptzPort: Int
    var ptzChannel: Int
    var ptzSpeed: Int
    var qualityPreset: StreamQualityPreset
    var encodingMode: StreamEncodingMode

    init(
        id: UUID = UUID(),
        name: String,
        urlString: String,
        location: String = "",
        notes: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        username: String = "",
        password: String = "",
        isPTZEnabled: Bool = true,
        ptzPort: Int = 80,
        ptzChannel: Int = 1,
        ptzSpeed: Int = 4,
        qualityPreset: StreamQualityPreset = .balanced,
        encodingMode: StreamEncodingMode = .lowCPU
    ) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.location = location
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.username = username
        self.password = password
        self.isPTZEnabled = isPTZEnabled
        self.ptzPort = ptzPort
        self.ptzChannel = ptzChannel
        self.ptzSpeed = ptzSpeed
        self.qualityPreset = qualityPreset
        self.encodingMode = encodingMode
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case urlString
        case location
        case notes
        case isFavorite
        case createdAt
        case username
        case password
        case isPTZEnabled
        case ptzPort
        case ptzChannel
        case ptzSpeed
        case qualityPreset
        case encodingMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        urlString = try container.decode(String.self, forKey: .urlString)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        isPTZEnabled = try container.decodeIfPresent(Bool.self, forKey: .isPTZEnabled) ?? true
        ptzPort = try container.decodeIfPresent(Int.self, forKey: .ptzPort) ?? 80
        ptzChannel = try container.decodeIfPresent(Int.self, forKey: .ptzChannel) ?? Self.channel(from: urlString)
        ptzSpeed = try container.decodeIfPresent(Int.self, forKey: .ptzSpeed) ?? 4
        qualityPreset = try container.decodeIfPresent(StreamQualityPreset.self, forKey: .qualityPreset) ?? .balanced
        encodingMode = try container.decodeIfPresent(StreamEncodingMode.self, forKey: .encodingMode) ?? .lowCPU
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(urlString, forKey: .urlString)
        try container.encode(location, forKey: .location)
        try container.encode(notes, forKey: .notes)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(username, forKey: .username)
        if !password.isEmpty {
            try container.encode(password, forKey: .password)
        }
        try container.encode(isPTZEnabled, forKey: .isPTZEnabled)
        try container.encode(ptzPort, forKey: .ptzPort)
        try container.encode(ptzChannel, forKey: .ptzChannel)
        try container.encode(ptzSpeed, forKey: .ptzSpeed)
        try container.encode(qualityPreset, forKey: .qualityPreset)
        try container.encode(encodingMode, forKey: .encodingMode)
    }

    var url: URL? {
        URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var playbackURL: URL? {
        guard let url = normalizedStreamURL else { return nil }
        guard !trimmedUsername.isEmpty else { return url }

        let resolvedPassword = resolvedPassword
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.user = trimmedUsername
        components?.password = resolvedPassword.isEmpty ? nil : resolvedPassword
        return components?.url ?? url
    }

    var requiresUnavailablePassword: Bool {
        !trimmedUsername.isEmpty && resolvedPassword.isEmpty
    }

    var resolvedPassword: String {
        if !password.isEmpty {
            return password
        }

        return CameraCredentialStore.password(for: id)
    }

    var hostLabel: String {
        guard let url else { return "Invalid URL" }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    var locationLabel: String {
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedLocation.isEmpty ? "Unassigned" : trimmedLocation
    }

    var streamKind: StreamKind {
        guard let scheme = url?.scheme?.lowercased() else { return .unknown }

        if scheme == "rtsp" || scheme == "rtsps" {
            return .rtsp
        }

        if scheme == "http" || scheme == "https" {
            let lowercasedPath = url?.path(percentEncoded: false).lowercased() ?? ""
            if lowercasedPath.hasSuffix(".m3u8") {
                return .hls
            }

            return .web
        }

        return .unknown
    }

    var normalizedStreamURL: URL? {
        guard let url else { return nil }
        guard streamKind == .rtsp else { return url }

        let path = url.path(percentEncoded: false)
        guard path.isEmpty || path == "/" else { return url }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/cam/realmonitor"
        components?.queryItems = [
            URLQueryItem(name: "channel", value: "1"),
            URLQueryItem(name: "subtype", value: qualityPreset.dahuaSubtype)
        ]
        return components?.url ?? url
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func channel(from urlString: String) -> Int {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let channel = components.queryItems?.first(where: { $0.name == "channel" })?.value,
              let channelNumber = Int(channel) else {
            return 1
        }

        return channelNumber
    }
}

enum StreamKind: String, Codable {
    case web
    case hls
    case rtsp
    case unknown

    var label: String {
        switch self {
        case .web:
            "HTTP/MJPEG"
        case .hls:
            "HLS"
        case .rtsp:
            "RTSP"
        case .unknown:
            "Unknown"
        }
    }
}
