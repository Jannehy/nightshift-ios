import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject private var session: Session
    @State private var address: String = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("192.168.1.20:8765", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($addressFocused)
                        .submitLabel(.go)
                        .onSubmit { connect() }
                } header: {
                    Text("Server address")
                } footer: {
                    Text("Host name or IP, with a port if Nightshift does not run on 8765 (host:9000). A full URL is taken as typed, https included. Over Tailscale or a VPN the tunnel has to be up before connecting.")
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Text("Connect")
                            Spacer()
                            if session.isWorking { ProgressView() }
                        }
                    }
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || session.isWorking)
                }

                if let error = session.loginError {
                    Section { ErrorBanner(message: error) }
                }
            }
            .navigationTitle("Nightshift")
            .onAppear {
                if address.isEmpty { address = session.serverAddress }
                addressFocused = address.isEmpty
            }
        }
    }

    private func connect() {
        Task { @MainActor in _ = await session.connect(to: address) }
    }
}

/// The server has no users yet – the wizard is web-only, so send them there.
struct SetupRequiredView: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Setup not finished")
                .font(.title2.weight(.semibold))
            Text("This server has no admin account yet. Run the setup wizard in a browser once, then come back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = setupURL {
                Link(destination: url) {
                    Label("Open setup in Safari", systemImage: "safari")
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Change server") {
                Task { @MainActor in await session.logout(forgetServer: true) }
            }
            .buttonStyle(.bordered)

            Button("Check again") {
                Task { @MainActor in await session.bootstrap() }
            }
            .font(.footnote)
        }
        .padding(32)
    }

    private var setupURL: URL? {
        guard let base = Session.normalize(address: session.serverAddress) else { return nil }
        return base.appendingPathComponent("setup")
    }
}
