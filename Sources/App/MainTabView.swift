import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var downloads: JobMonitor
    @StateObject private var nightly: JobMonitor
    @State private var selection = Tab.downloads

    enum Tab: Hashable {
        case downloads, search, sync, nightly, settings
    }

    @MainActor init() {
        // The monitors need the session; RootView only builds this view once the
        // session is ready, so reaching for the shared instance here is safe.
        let session = Session.shared
        _downloads = StateObject(wrappedValue: JobMonitor(source: .download, session: session))
        _nightly = StateObject(wrappedValue: JobMonitor(source: .nightly, session: session))
    }

    var body: some View {
        TabView(selection: $selection) {
            DownloadsView(monitor: downloads)
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
                .tag(Tab.downloads)

            SearchView(monitor: downloads, onQueued: { selection = .downloads })
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            if session.syncEnabled {
                SyncView()
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(Tab.sync)
            }

            NightlyView(monitor: nightly)
                .tabItem { Label("Nightly", systemImage: "moon.stars") }
                .tag(Tab.nightly)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .task {
            await downloads.restore()
            await nightly.restore()
        }
    }
}
