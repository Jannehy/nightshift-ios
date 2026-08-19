import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var session: Session
    @ObservedObject var monitor: JobMonitor
    let onQueued: () -> Void

    @StateObject private var model = SearchModel()
    @StateObject private var player = PreviewPlayer()
    @State private var toast: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            content
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Search")
                .searchable(text: $model.term, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: Text("Artist, track or album"))
                .onSubmit(of: .search) { runSearch() }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        QueueIndicator(queue: monitor.queue)
                    }
                }
                .onDisappear { player.stop() }
        }
        .toast($toast)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            Picker("Kind", selection: $model.entity) {
                ForEach(SearchEntity.allCases) { entity in
                    Text(entity.label).tag(entity)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onChange(of: model.entity) { _ in
                if !model.term.isEmpty { runSearch() }
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error) { model.errorMessage = nil }
                    .padding(.horizontal, 16)
            }

            if model.isSearching {
                Spacer()
                ProgressView()
                Spacer()
            } else if model.results.isEmpty {
                emptyState
            } else {
                results
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(model.hasSearched ? "No results" : "Search the iTunes catalog and download straight into your library.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    private var results: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(model.results) { result in
                    SearchResultCard(
                        result: result,
                        isPlaying: player.isPlaying(result.previewURL),
                        onPreview: { player.toggle(result.previewURL) },
                        onDownload: { download(result) })
                }
            }
            .padding(16)
        }
    }

    private func runSearch() {
        guard let client = session.client else { return }
        Task { @MainActor in await model.search(using: client, session: session) }
    }

    private func download(_ result: SearchResult) {
        guard let client = session.client else { return }
        player.stop()
        Task { @MainActor in
            if result.kind == "album", let albumID = result.itunesID {
                await monitor.start { try await client.downloadAlbum(itunesAlbumID: albumID) }
            } else {
                await monitor.start { try await client.downloadFromQuery(result.query) }
            }
            toast = String(format: NSLocalizedString("Queued: %@", comment: ""), result.title)
            onQueued()
        }
    }
}

struct SearchResultCard: View {
    let result: SearchResult
    let isPlaying: Bool
    let onPreview: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(url: result.artworkURL, size: 150, corner: 12)
                    .frame(maxWidth: .infinity)
                if result.previewURL != nil {
                    Button(action: onPreview) {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.55))
                    }
                    .padding(6)
                }
            }

            Text(result.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(action: onDownload) {
                Label(result.kind == "album" ? "Album" : "Download",
                      systemImage: "arrow.down.circle")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subtitle: String {
        var parts: [String] = []
        if result.kind != "artist" { parts.append(result.artist) }
        if let duration = result.durationText { parts.append(duration) }
        if let count = result.trackCount {
            parts.append(String(format: NSLocalizedString("%d tracks", comment: ""), count))
        }
        if let genre = result.genre { parts.append(genre) }
        if let year = result.releaseYear, result.kind == "album" { parts.append(year) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var term = ""
    @Published var entity: SearchEntity = .song
    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published var errorMessage: String?

    func search(using client: APIClient, session: Session) async {
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { results = []; return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false; hasSearched = true }
        do {
            results = try await client.search(query, entity: entity)
        } catch APIError.unauthorized {
            await session.handleUnauthorized()
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
