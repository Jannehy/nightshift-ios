import SwiftUI

/// Playlists the nightly job keeps up to date – the app's view of the sync
/// registry plus spotDL's own sync files.
struct SyncView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var model = SyncModel()
    @State private var editing: SyncItem?

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.items.isEmpty {
                    ProgressView()
                } else if model.items.isEmpty {
                    ContentUnavailableCompat(
                        title: "Nothing in sync",
                        message: "Enable Keep in sync while downloading a playlist and it will show up here.",
                        systemImage: "arrow.triangle.2.circlepath")
                } else {
                    list
                }
            }
            .navigationTitle("Sync")
            // No reload button: pull-to-refresh covers it, and a button up there
            // reads like it would trigger a sync, which is the Nightly tab's job.
            .refreshable { await model.load(session: session) }
            .task { await model.load(session: session) }
            .sheet(item: $editing) { item in
                SyncItemEditor(item: item) { owner, isPublic in
                    await model.updateMeta(item: item, owner: owner,
                                           isPublic: isPublic, session: session)
                }
                .environmentObject(session)
            }
        }
    }

    private var list: some View {
        List {
            if let error = model.errorMessage {
                Section { ErrorBanner(message: error) { model.errorMessage = nil } }
            }
            ForEach(model.grouped, id: \.source) { group in
                Section(group.label) {
                    ForEach(group.items) { item in
                        row(item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: SyncItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.sourceSymbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let owner = item.owner, !owner.isEmpty {
                        Label(owner, systemImage: "person")
                    } else if item.isPublic {
                        Label("Public", systemImage: "globe")
                    }
                    if !item.isPublic && (item.owner ?? "").isEmpty {
                        Label("Private", systemImage: "lock")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if session.isAdmin {
                Button {
                    editing = item
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions(edge: .trailing) {
            if item.canRemove {
                Button(role: .destructive) {
                    Task { @MainActor in await model.remove(item: item, session: session) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

/// Admin sheet: playlist visibility and owner. Visibility is mirrored to
/// Navidrome by the server; the owner stays local.
struct SyncItemEditor: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    let item: SyncItem
    let onSave: (String?, Bool) async -> Void

    @State private var isPublic: Bool
    @State private var owner: String
    @State private var users: [NightshiftUser] = []
    @State private var isSaving = false

    init(item: SyncItem, onSave: @escaping (String?, Bool) async -> Void) {
        self.item = item
        self.onSave = onSave
        _isPublic = State(initialValue: item.isPublic)
        _owner = State(initialValue: item.owner ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name).font(.headline)
                    LabeledContent("Source", value: item.sourceLabel)
                }

                Section {
                    Toggle("Public", isOn: $isPublic)
                } footer: {
                    Text("Public playlists are visible to every Nightshift user; the setting is mirrored to Navidrome.")
                }

                Section("Owner") {
                    Picker("Owner", selection: $owner) {
                        Text("None").tag("")
                        ForEach(users) { user in
                            Text(user.username).tag(user.username)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            }
            .navigationTitle("Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task { @MainActor in
                            await onSave(owner.isEmpty ? nil : owner, isPublic)
                            dismiss()
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .task {
                guard let client = session.client else { return }
                users = (try? await client.users()) ?? []
            }
        }
    }
}

@MainActor
final class SyncModel: ObservableObject {
    struct Group {
        let source: String
        let label: String
        let items: [SyncItem]
    }

    @Published private(set) var items: [SyncItem] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private static let order = ["spotify", "soundcloud", "youtube"]

    var grouped: [Group] {
        let buckets = Dictionary(grouping: items, by: { $0.source })
        let keys = buckets.keys.sorted {
            (Self.order.firstIndex(of: $0) ?? 99) < (Self.order.firstIndex(of: $1) ?? 99)
        }
        return keys.map { key in
            let entries = (buckets[key] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return Group(source: key, label: entries.first?.sourceLabel ?? key, items: entries)
        }
    }

    func load(session: Session) async {
        guard let client = session.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await client.syncPlaylists().entries
        } catch APIError.unauthorized {
            await session.handleUnauthorized()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func remove(item: SyncItem, session: Session) async {
        guard let client = session.client else { return }
        do {
            try await client.removeSyncItem(url: item.url, file: item.file)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateMeta(item: SyncItem, owner: String?, isPublic: Bool, session: Session) async {
        guard let client = session.client else { return }
        do {
            try await client.updateSyncMeta(url: item.url, file: item.file,
                                            owner: owner, isPublic: isPublic)
            await load(session: session)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// `ContentUnavailableView` is iOS 17 only – this app still targets iOS 16.
struct ContentUnavailableCompat: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
