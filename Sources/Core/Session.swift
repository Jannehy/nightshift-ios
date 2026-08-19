import Foundation
import SwiftUI

/// App-wide auth and connection state: which server, who is signed in, and
/// which optional server features (sync, Navidrome) the UI may show.
@MainActor
final class Session: ObservableObject {

    enum Phase: Equatable {
        case launching
        case needsServer
        case needsSetup        // server has no users yet – wizard runs in the browser
        case needsLogin
        case ready
    }

    /// One instance for the whole app: views get it from the environment, and
    /// objects created inside a `View.init` (the job monitors) reach it here.
    static let shared = Session()

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var me: MeInfo?
    @Published private(set) var serverVersion: VersionInfo?
    @Published var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Self.addressKey) }
    }
    @Published var loginError: String?
    @Published var isWorking = false

    private static let addressKey = "nightshift.serverAddress"
    private static let usernameKey = "nightshift.username"

    private(set) var client: APIClient?

    var user: NightshiftUser? { me?.user }
    var isAdmin: Bool { me?.isAdmin ?? false }
    var syncEnabled: Bool { me?.syncEnabled ?? false }
    var navidromeEnabled: Bool { me?.navidromeEnabled ?? false }

    private init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.addressKey) ?? ""
    }

    /// Turns whatever the user typed into a usable base URL.
    ///
    /// A bare host gets `http://` and Nightshift's default port, matching how
    /// the server is normally reached over a tunnel. Anything more explicit is
    /// taken at face value: `host:9000` keeps its port, and a full URL keeps
    /// both its scheme and its port — so `http://music.example.com` behind a
    /// reverse proxy stays on port 80 instead of being pushed to 8765. A path
    /// prefix survives too, for servers published under a subpath.
    static func normalize(address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let hadScheme = text.contains("://")
        if !hadScheme { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard var comps = URLComponents(string: text), let host = comps.host, !host.isEmpty
        else { return nil }
        if comps.port == nil && !hadScheme { comps.port = 8765 }
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard let url = Self.normalize(address: serverAddress) else {
            phase = .needsServer
            return
        }
        client = APIClient(baseURL: url)
        await refreshPhase()
    }

    /// Called from the server screen after the address changed.
    func connect(to address: String) async -> Bool {
        guard let url = Self.normalize(address: address) else {
            loginError = NSLocalizedString("The server address is not a valid URL.", comment: "")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let candidate = APIClient(baseURL: url)
        do {
            let health = try await candidate.health()
            serverAddress = address
            client = candidate
            loginError = nil
            phase = health.configured ? .needsLogin : .needsSetup
            await refreshPhase()
            return true
        } catch {
            loginError = error.localizedDescription
            return false
        }
    }

    /// Reads the server's version. Nil means "older than 1.3" – those servers
    /// have no version endpoint at all.
    private func refreshVersion() async {
        guard let client else { return }
        serverVersion = (try? await client.version()) ?? nil
    }

    private func refreshPhase() async {
        guard let client else { phase = .needsServer; return }
        await refreshVersion()
        do {
            me = try await client.me()
            phase = .ready
        } catch APIError.unauthorized {
            // Cookie gone – try the stored credentials once before asking.
            if await attemptStoredLogin() { return }
            await determineSetupOrLogin(client)
        } catch {
            await determineSetupOrLogin(client)
        }
    }

    private func determineSetupOrLogin(_ client: APIClient) async {
        if let health = try? await client.health() {
            phase = health.configured ? .needsLogin : .needsSetup
        } else {
            phase = .needsServer
            loginError = NSLocalizedString("Server unreachable.", comment: "")
        }
    }

    private func attemptStoredLogin() async -> Bool {
        guard let client,
              let username = UserDefaults.standard.string(forKey: Self.usernameKey),
              let password = Keychain.password(account: username)
        else { return false }
        do {
            _ = try await client.login(username: username, password: password)
            me = try await client.me()
            phase = .ready
            return true
        } catch {
            return false
        }
    }

    func login(username: String, password: String) async {
        guard let client else { return }
        isWorking = true
        loginError = nil
        defer { isWorking = false }
        do {
            _ = try await client.login(username: username, password: password)
            me = try await client.me()
            UserDefaults.standard.set(username, forKey: Self.usernameKey)
            Keychain.save(password: password, account: username)
            phase = .ready
        } catch {
            loginError = error.localizedDescription
        }
    }

    func logout(forgetServer: Bool = false) async {
        if let client { try? await client.logout() }
        if let username = UserDefaults.standard.string(forKey: Self.usernameKey) {
            Keychain.delete(account: username)
        }
        UserDefaults.standard.removeObject(forKey: Self.usernameKey)
        clearCookies()
        me = nil
        if forgetServer {
            serverAddress = ""
            client = nil
            phase = .needsServer
        } else {
            phase = .needsLogin
        }
    }

    /// Re-read `/api/me` – picks up role or feature-flag changes made elsewhere.
    func refreshMe() async {
        guard let client else { return }
        if let info = try? await client.me() { me = info }
    }

    /// Any view that gets a 401 routes through here so the whole app agrees
    /// on the auth state instead of each screen showing its own error.
    func handleUnauthorized() async {
        if await attemptStoredLogin() { return }
        me = nil
        phase = .needsLogin
    }

    private func clearCookies() {
        guard let host = client?.server.host else { return }
        let storage = HTTPCookieStorage.shared
        storage.cookies?.filter { $0.domain.contains(host) }.forEach(storage.deleteCookie)
    }
}
