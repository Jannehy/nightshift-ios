import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var session: Session
    @ObservedObject var monitor: JobMonitor
    @StateObject private var model = DownloadsModel()
    @FocusState private var urlFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    if monitor.state != .idle || !monitor.lines.isEmpty {
                        statusCard
                    }
                    if let error = monitor.errorMessage {
                        ErrorBanner(message: error) { monitor.errorMessage = nil }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    QueueIndicator(queue: monitor.queue)
                }
            }
            .refreshable {
                await monitor.restore()
            }
            .task {
                await model.load(session: session)
            }
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste a Spotify, SoundCloud or YouTube link.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("https://…", text: $model.urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($urlFocused)
                    .submitLabel(.go)
                    .onSubmit(start)
                    .padding(10)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    if let text = UIPasteboard.general.string { model.urlText = text }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
            }

            if !model.urlText.isEmpty, let hint = model.sourceHint {
                Label(hint, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !model.urlText.isEmpty {
                Label("Not a supported link", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if session.syncEnabled {
                Toggle(isOn: $model.keepInSync) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep in sync")
                        Text("The nightly job keeps this playlist up to date.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if session.navidromeEnabled && !model.navidromeUsers.isEmpty {
                Picker("Playlist owner", selection: $model.ownerID) {
                    Text("Public").tag(String?.none)
                    ForEach(model.navidromeUsers) { user in
                        Text(user.name.isEmpty ? user.userName : user.name)
                            .tag(String?.some(user.id))
                    }
                }
            }

            Button(action: start) {
                HStack {
                    Spacer()
                    Label("Start download", systemImage: "arrow.down.circle.fill")
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStart || monitor.state.isBusy)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            JobStatusView(monitor: monitor)
            LogView(lines: monitor.lines)
            if !monitor.state.isBusy && !monitor.lines.isEmpty {
                Button("Clear log", role: .destructive) { monitor.clear() }
                    .font(.footnote)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func start() {
        urlFocused = false
        let url = model.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = model.ownerID
        let sync = model.keepInSync && session.syncEnabled
        guard let client = session.client, model.canStart else { return }
        Task { @MainActor in
            await monitor.start {
                try await client.startDownload(url: url, ownerID: owner, sync: sync)
            }
            model.urlText = ""
        }
    }
}

/// Compact queue readout for the navigation bar.
struct QueueIndicator: View {
    let queue: QueueStatus?

    var body: some View {
        if let queue, !queue.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet")
                Text("\(queue.count)")
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

@MainActor
final class DownloadsModel: ObservableObject {
    @Published var urlText = ""
    @Published var keepInSync = false
    @Published var ownerID: String?
    @Published var navidromeUsers: [NavidromeUser] = []

    private static let supportedDomains = ["spotify.com", "soundcloud.com",
                                           "youtube.com", "youtu.be"]

    var sourceHint: String? {
        let text = urlText.lowercased()
        if text.contains("spotify.com") { return NSLocalizedString("Spotify link", comment: "") }
        if text.contains("soundcloud.com") { return NSLocalizedString("SoundCloud link", comment: "") }
        if text.contains("youtube.com") || text.contains("youtu.be") {
            return NSLocalizedString("YouTube link", comment: "")
        }
        return nil
    }

    var canStart: Bool {
        let text = urlText.lowercased()
        return Self.supportedDomains.contains { text.contains($0) }
    }

    func load(session: Session) async {
        guard session.navidromeEnabled, let client = session.client,
              navidromeUsers.isEmpty else { return }
        if let response = try? await client.navidromeUsers(), response.enabled {
            navidromeUsers = response.users
        }
    }
}
