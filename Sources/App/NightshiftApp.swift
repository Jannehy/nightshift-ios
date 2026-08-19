import SwiftUI

@main
struct NightshiftApp: App {
    @StateObject private var session = Session.shared
    @StateObject private var appearance = Appearance.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(appearance)
                .tint(appearance.accent)
        }
    }
}
