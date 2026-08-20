import Foundation

// MARK: - Identity

struct NightshiftUser: Codable, Hashable, Identifiable {
    let username: String
    let role: String

    var id: String { username }
    var isAdmin: Bool { role == "admin" }
}

/// `/api/me` – everything the UI needs to decide what to show.
struct MeInfo: Codable {
    let user: NightshiftUser
    let isAdmin: Bool
    let syncEnabled: Bool
    let navidromeEnabled: Bool
    let nightlySchedule: String?
    let language: String?
    let theme: String?

    enum CodingKeys: String, CodingKey {
        case user
        case isAdmin = "is_admin"
        case syncEnabled = "sync_enabled"
        case navidromeEnabled = "navidrome_enabled"
        case nightlySchedule = "nightly_schedule"
        case language, theme
    }
}

struct HealthInfo: Codable {
    let status: String
    let configured: Bool
    let version: String?
}

/// `/api/version` – open, so the app can identify a server before signing in.
struct VersionInfo: Codable {
    let name: String?
    let version: String

    /// The oldest server this build understands. Older ones still work, but
    /// share one download log between all users (fixed server-side in 1.3).
    static let minimumSupported = "1.3"

    var isSupported: Bool { Self.compare(version, Self.minimumSupported) >= 0 }

    /// Numeric compare of dot-separated versions: -1, 0 or 1.
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(l.count, r.count) {
            let a = i < l.count ? l[i] : 0
            let b = i < r.count ? r[i] : 0
            if a != b { return a < b ? -1 : 1 }
        }
        return 0
    }
}

struct LoginResponse: Codable {
    let ok: Bool
    let user: NightshiftUser
}

// MARK: - Jobs

/// Every download endpoint answers with a job id and its queue position.
struct JobRef: Codable {
    let jobID: String
    let position: Int
    let trackCount: Int?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case position
        case trackCount = "track_count"
    }
}

/// One server-sent event from `/stream/<job_id>`.
struct JobEvent: Codable {
    let type: String          // status | log | progress | done | error
    let message: String?
    let line: String?
    let progress: Int?
    let current: Int?
    let total: Int?
    let track: String?
    let totalTracks: Int?

    enum CodingKeys: String, CodingKey {
        case type, message, line, progress, current, total, track
        case totalTracks = "total_tracks"
    }

    var isTerminal: Bool { type == "done" || type == "error" }

    /// The text this event contributes to the visible log, if any.
    var logLine: String? {
        if let line, !line.isEmpty { return line }
        if type == "progress", let track, !track.isEmpty { return "♪ \(track)" }
        if let message, !message.isEmpty { return message }
        return nil
    }
}

/// `/download-log` and `/nightly-log` – lets the UI restore after a cold start.
struct LogState: Codable {
    let log: String
    let mtime: Double
    let finished: Bool
    let failed: Bool
    let running: Bool?

    var isRunning: Bool { running ?? false }
    var lines: [String] {
        log.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }
}

extension LogState {
    /// Track counts read out of the log text.
    ///
    /// While the app polls the log – after a cold start, or when a job was
    /// begun elsewhere – no progress events arrive, so the percentage is
    /// derived the same way the web UI derives it.
    struct Counts {
        let done: Int
        let total: Int

        /// The same 5 … 95 % window the web UI uses, so both agree.
        var fraction: Double { min(0.95, 0.05 + Double(done) / Double(total) * 0.90) }
    }

    var counts: Counts? {
        var total = LogState.number(in: log, pattern: #"\((\d+) tracks\)"#) ?? 0
        if let found = LogState.number(in: log, pattern: #"(\d+) tracks found"#) {
            total = max(total, found)
        }
        guard total > 0 else { return nil }
        let done = LogState.matchCount(in: log, pattern: #"^(✓ |Downloaded |Skipping )"#)
        return Counts(done: min(done, total), total: total)
    }

    private static func number(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let group = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[group])
    }

    private static func matchCount(in text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(
            pattern: pattern, options: [.anchorsMatchLines]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}

struct QueueEntry: Codable, Hashable, Identifiable {
    let jobID: String?
    let label: String

    var id: String { jobID ?? label }

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case label
    }
}

struct QueueStatus: Codable {
    let running: QueueEntry?
    let pending: [QueueEntry]

    var isEmpty: Bool { running == nil && pending.isEmpty }
    var count: Int { (running == nil ? 0 : 1) + pending.count }
}

struct NightlyStatus: Codable {
    let running: Bool
}

// MARK: - Search

enum SearchEntity: String, CaseIterable, Identifiable {
    case song, album, musicArtist

    var id: String { rawValue }

    var label: String {
        switch self {
        case .song: return NSLocalizedString("Tracks", comment: "")
        case .album: return NSLocalizedString("Albums", comment: "")
        case .musicArtist: return NSLocalizedString("Artists", comment: "")
        }
    }
}

struct SearchResult: Codable, Identifiable, Hashable {
    let kind: String              // track | album | artist
    let itunesID: Int?
    let title: String
    let artist: String
    let album: String?
    let artwork: String?
    let preview: String?
    let durationMS: Int?
    let releaseDate: String?
    let trackCount: Int?
    let genre: String?
    let query: String

    enum CodingKeys: String, CodingKey {
        case kind, title, artist, album, artwork, preview, genre, query
        case itunesID = "id"
        case durationMS = "duration_ms"
        case releaseDate = "release_date"
        case trackCount = "track_count"
    }

    var artworkURL: URL? {
        guard let artwork, !artwork.isEmpty else { return nil }
        return URL(string: artwork)
    }

    var previewURL: URL? {
        guard let preview, !preview.isEmpty else { return nil }
        return URL(string: preview)
    }

    var durationText: String? {
        guard let ms = durationMS, ms > 0 else { return nil }
        let seconds = ms / 1000
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var releaseYear: String? {
        guard let releaseDate, releaseDate.count >= 4 else { return nil }
        return String(releaseDate.prefix(4))
    }

    /// iTunes occasionally omits the id – fall back to the query so SwiftUI
    /// still gets a stable identity.
    var id: String { itunesID.map(String.init) ?? "\(kind):\(query)" }
}

struct SearchResponse: Codable {
    let results: [SearchResult]
    let error: String?
}

// MARK: - Sync registry

struct SyncItem: Codable, Identifiable, Hashable {
    let url: String?
    let source: String            // spotify | soundcloud | youtube
    let name: String
    let file: String?
    let owner: String?
    let isPublic: Bool
    let canRemove: Bool

    enum CodingKeys: String, CodingKey {
        case url, source, name, file, owner
        case isPublic = "public"
        case canRemove = "can_remove"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "spotify"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "?"
        file = try c.decodeIfPresent(String.self, forKey: .file)
        owner = try c.decodeIfPresent(String.self, forKey: .owner)
        isPublic = try c.decodeIfPresent(Bool.self, forKey: .isPublic) ?? true
        canRemove = try c.decodeIfPresent(Bool.self, forKey: .canRemove) ?? false
    }

    var id: String { (url?.isEmpty == false ? url! : nil) ?? file ?? name }

    var sourceLabel: String {
        switch source {
        case "spotify": return "Spotify"
        case "soundcloud": return "SoundCloud"
        case "youtube": return "YouTube"
        default: return source.capitalized
        }
    }

    var sourceSymbol: String {
        switch source {
        case "spotify": return "music.note.list"
        case "soundcloud": return "cloud"
        case "youtube": return "play.rectangle"
        default: return "music.note"
        }
    }
}

struct SyncListResponse: Codable {
    let entries: [SyncItem]
    let enabled: Bool
}

// MARK: - Navidrome

struct NavidromeUser: Codable, Identifiable, Hashable {
    let id: String
    let userName: String
    let name: String
}

struct NavidromeUsersResponse: Codable {
    let users: [NavidromeUser]
    let enabled: Bool
    let error: String?
}

// MARK: - Config

struct UsersResponse: Codable {
    let users: [NightshiftUser]
}

/// The config API hands out whatever is in `config.yaml`, so the client keeps
/// it as loosely typed JSON and renders a control per value kind.
enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let v = try? c.decode(Bool.self) {
            self = .bool(v)
        } else if let v = try? c.decode(Int.self) {
            self = .int(v)
        } else if let v = try? c.decode(Double.self) {
            self = .double(v)
        } else if let v = try? c.decode(String.self) {
            self = .string(v)
        } else if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
        } else if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
        } else {
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }

    /// Text for a free-form field – numbers included, so one editor covers
    /// strings, ints and doubles.
    var editableText: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return ""
        case .array, .object: return ""
        }
    }

    var isEditableScalar: Bool {
        switch self {
        case .string, .int, .double, .bool, .null: return true
        case .array, .object: return false
        }
    }

    /// Re-encode edited text in the kind the server originally sent, so an
    /// int stays an int in `config.yaml`.
    func withText(_ text: String) -> JSONValue {
        switch self {
        case .int: return Int(text).map(JSONValue.int) ?? .string(text)
        case .double: return Double(text).map(JSONValue.double) ?? .string(text)
        default: return .string(text)
        }
    }
}
