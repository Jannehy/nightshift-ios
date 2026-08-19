import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var appearance: Appearance
    @State private var showPasswordSheet = false
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    LabeledContent("User", value: session.user?.username ?? "–")
                    LabeledContent("Role",
                                   value: session.isAdmin
                                       ? NSLocalizedString("Administrator", comment: "")
                                       : NSLocalizedString("User", comment: ""))
                    Button("Change password") { showPasswordSheet = true }
                }

                Section("Appearance") {
                    AccentPicker()
                }

                Section {
                    AppIconPicker()
                } header: {
                    Text("App icon")
                } footer: {
                    Text("iOS shows a confirmation every time the icon changes – that is why this is separate from the accent colour.")
                }

                Section {
                    LabeledContent("Address", value: session.serverAddress)
                    LabeledContent("Version",
                                   value: session.serverVersion?.version
                                       ?? NSLocalizedString("older than 1.3", comment: ""))
                    LabeledContent("Sync",
                                   value: session.syncEnabled
                                       ? NSLocalizedString("On", comment: "")
                                       : NSLocalizedString("Off", comment: ""))
                    LabeledContent("Navidrome",
                                   value: session.navidromeEnabled
                                       ? NSLocalizedString("Connected", comment: "")
                                       : NSLocalizedString("Off", comment: ""))
                } header: {
                    Text("Server")
                } footer: {
                    if session.serverVersion?.isSupported != true {
                        Text("This server is older than Nightshift 1.3. Everything works, but the download log is shared between all users – you may see someone else's run.")
                    }
                }

                if session.isAdmin {
                    Section("Administration") {
                        NavigationLink {
                            UsersView()
                        } label: {
                            Label("Users", systemImage: "person.2")
                        }
                        NavigationLink {
                            ServerConfigView()
                        } label: {
                            Label("Server settings", systemImage: "gearshape.2")
                        }
                    }
                }

                Section {
                    Button("Sign out", role: .destructive) { showLogoutConfirm = true }
                    Button("Sign out and forget server", role: .destructive) {
                        Task { @MainActor in await session.logout(forgetServer: true) }
                    }
                }
            }
            .navigationTitle("Settings")
            .refreshable { await session.refreshMe() }
            .sheet(isPresented: $showPasswordSheet) {
                PasswordSheet(username: nil)
                    .environmentObject(session)
            }
            .confirmationDialog("Sign out?", isPresented: $showLogoutConfirm) {
                Button("Sign out", role: .destructive) {
                    Task { @MainActor in await session.logout() }
                }
            }
        }
    }
}

/// Icon variants, shown as the artwork itself rather than a plain swatch.
struct AppIconPicker: View {
    @StateObject private var manager = AppIconManager.shared

    private let columns = [GridItem(.adaptive(minimum: 56), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AppIconManager.options) { option in
                    Button {
                        manager.select(option)
                    } label: {
                        NightshiftMark()
                            .foregroundStyle(option.color)
                            .padding(6)
                            .frame(width: 52, height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(manager.current.id == option.id
                                                  ? Color.accentColor : Color.primary.opacity(0.15),
                                                  lineWidth: manager.current.id == option.id ? 2.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString(option.label, comment: "app icon"))
                }
            }

            if let error = manager.errorMessage {
                ErrorBanner(message: error) { manager.errorMessage = nil }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Swatch row plus the system colour picker for anything not in the row.
struct AccentPicker: View {
    @EnvironmentObject private var appearance: Appearance

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Appearance.swatches) { swatch in
                    Button {
                        appearance.accentHex = swatch.hex
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if appearance.isSelected(swatch) {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString(swatch.name, comment: "accent colour"))
                }
            }

            ColorPicker("Custom colour", selection: appearance.customColor, supportsOpacity: false)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Users

struct UsersView: View {
    @EnvironmentObject private var session: Session
    @State private var users: [NightshiftUser] = []
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var passwordTarget: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) { self.errorMessage = nil } }
            }
            ForEach(users) { user in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.username)
                        Text(user.isAdmin
                             ? NSLocalizedString("Administrator", comment: "")
                             : NSLocalizedString("User", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        passwordTarget = user.username
                    } label: {
                        Image(systemName: "key")
                    }
                    .buttonStyle(.borderless)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { @MainActor in await delete(user) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Users")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate) {
            CreateUserSheet { username, password, role in
                await create(username: username, password: password, role: role)
            }
        }
        .sheet(item: Binding(get: { passwordTarget.map(IdentifiableString.init) },
                             set: { passwordTarget = $0?.value })) { target in
            PasswordSheet(username: target.value)
                .environmentObject(session)
        }
    }

    private func load() async {
        guard let client = session.client else { return }
        do { users = try await client.users() }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ user: NightshiftUser) async {
        guard let client = session.client else { return }
        do {
            try await client.deleteUser(username: user.username)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create(username: String, password: String, role: String) async {
        guard let client = session.client else { return }
        do {
            try await client.createUser(username: username, password: password, role: role)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct IdentifiableString: Identifiable {
    let value: String
    var id: String { value }

    init(_ value: String) { self.value = value }
}

struct CreateUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String, String) async -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isAdmin = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Toggle("Administrator", isOn: $isAdmin)
            }
            .navigationTitle("New user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { @MainActor in
                            await onCreate(username, password, isAdmin ? "admin" : "user")
                            dismiss()
                        }
                    }
                    .disabled(username.isEmpty || password.count < 4)
                }
            }
        }
    }
}

struct PasswordSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    /// nil = the signed-in user's own password.
    let username: String?

    @State private var password = ""
    @State private var confirmation = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New password", text: $password)
                    SecureField("Repeat password", text: $confirmation)
                } footer: {
                    Text(username.map { String(format: NSLocalizedString("Changing the password for %@.", comment: ""), $0) }
                         ?? NSLocalizedString("At least 4 characters.", comment: ""))
                }
                if let errorMessage {
                    Section { ErrorBanner(message: errorMessage) }
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(password.count < 4 || password != confirmation)
                }
            }
        }
    }

    private func save() {
        guard let client = session.client else { return }
        Task { @MainActor in
            do {
                try await client.changePassword(username: username, newPassword: password)
                // Keep the Keychain in step so silent re-login still works.
                if username == nil || username == session.user?.username,
                   let account = session.user?.username {
                    Keychain.save(password: password, account: account)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
