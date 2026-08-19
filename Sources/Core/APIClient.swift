import Foundation

enum APIError: LocalizedError {
    case noServer
    case badURL
    case unauthorized
    case forbidden
    case conflict(String)
    case server(String)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .noServer: return NSLocalizedString("No server configured.", comment: "")
        case .badURL: return NSLocalizedString("The server address is not a valid URL.", comment: "")
        case .unauthorized: return NSLocalizedString("Not signed in.", comment: "")
        case .forbidden: return NSLocalizedString("Administrators only.", comment: "")
        case .conflict(let m): return m
        case .server(let m): return m
        case .transport(let e): return e.localizedDescription
        case .decoding: return NSLocalizedString("The server sent an unexpected response.", comment: "")
        }
    }
}

/// Error envelope Nightshift uses for every failing endpoint.
private struct ErrorEnvelope: Decodable { let error: String? }

/// Thin async wrapper over the Nightshift HTTP API.
///
/// Auth is the Flask session cookie: `/api/login` sets a permanent cookie which
/// `URLSession`'s shared cookie storage persists across launches, so a normal
/// start needs no round trip. `Session` re-logs in from the Keychain when the
/// cookie has expired server-side.
final class APIClient {
    private let baseURL: URL
    private let session: URLSession

    let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder = JSONEncoder()

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        // Live logs must not be served from a cache.
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    var server: URL { baseURL }

    // MARK: - Request plumbing

    private func makeRequest(_ path: String,
                             method: String = "GET",
                             query: [URLQueryItem] = [],
                             body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path),
                                        resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // The access gate answers HTML redirects for browser GETs but JSON 401s
        // for anything under /api/ – this header keeps proxies honest too.
        req.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("Invalid response")
        }
        // Non-/api/ GETs are answered with a redirect to the login page rather
        // than a 401, and URLSession follows it – so a 200 whose final URL is
        // the login screen means the session is gone, not that the call worked.
        if Self.isGatePage(http.url) { throw APIError.unauthorized }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 409:
            throw APIError.conflict(Self.message(from: data)
                                    ?? NSLocalizedString("Already running.", comment: ""))
        default:
            // A redirect that made it this far means the gate wants the login
            // page – treat it as "session gone" rather than a random failure.
            if http.statusCode == 302 { throw APIError.unauthorized }
            throw APIError.server(Self.message(from: data)
                                  ?? "HTTP \(http.statusCode)")
        }
    }

    /// True for the login and setup pages the access gate redirects to. Matched
    /// on the suffix so a server published under a path prefix is recognised
    /// too; `/api/login` is excluded, since that endpoint legitimately ends in
    /// "/login" and answers with JSON.
    private static func isGatePage(_ url: URL?) -> Bool {
        guard let path = url?.path, !path.contains("/api/") else { return false }
        return path.hasSuffix("/login") || path.hasSuffix("/setup")
    }

    private static func message(from data: Data) -> String? {
        guard let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
              let msg = env.error, !msg.isEmpty else { return nil }
        return msg
    }

    private func get<T: Decodable>(_ path: String,
                                   query: [URLQueryItem] = [],
                                   as type: T.Type = T.self) async throws -> T {
        let data = try await perform(try makeRequest(path, query: query))
        return try decode(data)
    }

    /// Bodies are plain dictionaries – Nightshift treats an empty string like a
    /// missing value everywhere it accepts one, so no key needs an explicit null.
    @discardableResult
    private func send<T: Decodable>(_ path: String,
                                    method: String,
                                    json: [String: Any] = [:],
                                    as type: T.Type = T.self) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: json)
        let data = try await perform(try makeRequest(path, method: method, body: body))
        return try decode(data)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    struct EmptyResponse: Decodable {}

    // MARK: - Auth

    func health() async throws -> HealthInfo {
        try await get("health")
    }

    /// Servers before 1.3 have no version endpoint – there a 404 is the answer,
    /// not a failure, so this reports nil instead of throwing.
    func version() async throws -> VersionInfo? {
        do {
            return try await get("api/version")
        } catch APIError.server, APIError.decoding {
            return nil
        }
    }

    func login(username: String, password: String) async throws -> NightshiftUser {
        let res: LoginResponse = try await send("api/login", method: "POST",
                                                json: ["username": username,
                                                       "password": password])
        return res.user
    }

    func logout() async throws {
        try await send("api/logout", method: "POST", as: EmptyResponse.self)
    }

    func me() async throws -> MeInfo {
        try await get("api/me")
    }

    // MARK: - Downloads

    func startDownload(url: String, ownerID: String?, sync: Bool) async throws -> JobRef {
        try await send("download", method: "POST",
                       json: ["url": url, "owner_id": ownerID ?? "", "sync": sync])
    }

    func downloadFromQuery(_ query: String) async throws -> JobRef {
        try await send("api/download-from-query", method: "POST",
                       json: ["query": query])
    }

    func downloadAlbum(itunesAlbumID: Int) async throws -> JobRef {
        try await send("api/download-album", method: "POST",
                       json: ["itunes_album_id": itunesAlbumID])
    }

    func downloadLog() async throws -> LogState {
        try await get("download-log")
    }

    func queue() async throws -> QueueStatus {
        try await get("api/queue")
    }

    // MARK: - Nightly

    func startNightly() async throws -> JobRef {
        try await send("nightly", method: "POST")
    }

    func nightlyStatus() async throws -> Bool {
        let status: NightlyStatus = try await get("nightly-status")
        return status.running
    }

    func nightlyLog() async throws -> LogState {
        try await get("nightly-log")
    }

    // MARK: - Search

    func search(_ term: String, entity: SearchEntity) async throws -> [SearchResult] {
        let res: SearchResponse = try await get(
            "api/search",
            query: [URLQueryItem(name: "q", value: term),
                    URLQueryItem(name: "entity", value: entity.rawValue)])
        if let error = res.error { throw APIError.server(error) }
        return res.results
    }

    // MARK: - Sync registry

    func syncPlaylists() async throws -> SyncListResponse {
        try await get("api/sync-playlists")
    }

    func updateSyncMeta(url: String?, file: String?,
                        owner: String?, isPublic: Bool) async throws {
        try await send("api/sync-playlists", method: "PATCH",
                       json: ["url": url ?? "", "file": file ?? "",
                              "owner": owner ?? "", "public": isPublic],
                       as: EmptyResponse.self)
    }

    func removeSyncItem(url: String?, file: String?) async throws {
        try await send("api/sync-playlists", method: "DELETE",
                       json: ["url": url ?? "", "file": file ?? ""],
                       as: EmptyResponse.self)
    }

    func navidromeUsers() async throws -> NavidromeUsersResponse {
        try await get("nd-users")
    }

    // MARK: - User management

    func users() async throws -> [NightshiftUser] {
        let res: UsersResponse = try await get("api/users")
        return res.users
    }

    func createUser(username: String, password: String, role: String) async throws {
        try await send("api/users", method: "POST",
                       json: ["username": username, "password": password, "role": role],
                       as: EmptyResponse.self)
    }

    func deleteUser(username: String) async throws {
        try await send("api/users", method: "DELETE",
                       json: ["username": username], as: EmptyResponse.self)
    }

    func changePassword(username: String?, newPassword: String) async throws {
        try await send("api/users/password", method: "POST",
                       json: ["username": username ?? "", "password": newPassword],
                       as: EmptyResponse.self)
    }

    // MARK: - Config

    func config() async throws -> [String: [String: JSONValue]] {
        let data = try await perform(try makeRequest("api/config"))
        let raw = try decoder.decode([String: JSONValue].self, from: data)
        var out: [String: [String: JSONValue]] = [:]
        for (section, value) in raw {
            if case .object(let fields) = value { out[section] = fields }
        }
        return out
    }

    func saveConfig(_ updates: [String: [String: JSONValue]]) async throws {
        let payload = updates.mapValues { JSONValue.object($0) }
        let body = try encoder.encode(payload)
        _ = try await perform(try makeRequest("api/config", method: "POST", body: body))
    }

    func resetConfig() async throws {
        try await send("api/config/reset", method: "POST", as: EmptyResponse.self)
    }

    // MARK: - Live job stream

    /// Server-sent events for one job. The stream ends after `done`/`error`;
    /// the server's `: ping` comments keep it alive and are skipped.
    func events(forJob jobID: String) -> AsyncThrowingStream<JobEvent, Error> {
        AsyncThrowingStream<JobEvent, Error> { continuation in
            let task = Task {
                do {
                    var request = try makeRequest("stream/\(jobID)")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 3600

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.server("Invalid response")
                    }
                    if Self.isGatePage(http.url) { throw APIError.unauthorized }
                    guard http.statusCode == 200 else {
                        throw http.statusCode == 401 ? APIError.unauthorized
                                                     : APIError.server("HTTP \(http.statusCode)")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? decoder.decode(JobEvent.self, from: data)
                        else { continue }
                        continuation.yield(event)
                        if event.isTerminal { break }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
