import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: Session
    @State private var username = ""
    @State private var password = ""
    @FocusState private var field: Field?

    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($field, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { field = .password }

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                } header: {
                    Text("Sign in")
                } footer: {
                    Text(session.serverAddress)
                        .font(.caption)
                }

                Section {
                    Button {
                        signIn()
                    } label: {
                        HStack {
                            Text("Sign in")
                            Spacer()
                            if session.isWorking { ProgressView() }
                        }
                    }
                    .disabled(!canSubmit)
                }

                if let error = session.loginError {
                    Section { ErrorBanner(message: error) }
                }

                Section {
                    Button("Use a different server", role: .destructive) {
                        Task { @MainActor in await session.logout(forgetServer: true) }
                    }
                }
            }
            .navigationTitle("Nightshift")
            .onAppear {
                if username.isEmpty {
                    username = UserDefaults.standard.string(forKey: "nightshift.username") ?? ""
                }
                field = username.isEmpty ? .username : .password
            }
        }
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty && !session.isWorking
    }

    private func signIn() {
        guard canSubmit else { return }
        Task { @MainActor in await session.login(username: username, password: password) }
    }
}
