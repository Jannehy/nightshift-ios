import SwiftUI

/// Mirrors the server's access gate: no server → setup → login → app.
struct RootView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            switch session.phase {
            case .launching:
                LaunchView()
            case .needsServer:
                ServerSetupView()
            case .needsSetup:
                SetupRequiredView()
            case .needsLogin:
                LoginView()
            case .ready:
                MainTabView()
            }
        }
        .animation(.default, value: session.phase)
        .task { await session.bootstrap() }
    }
}

private struct LaunchView: View {
    var body: some View {
        VStack(spacing: 24) {
            NightshiftMark()
                .foregroundStyle(.tint)
                .frame(width: 104, height: 104)
            ProgressView()
        }
    }
}
