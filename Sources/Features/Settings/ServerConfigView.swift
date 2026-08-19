import SwiftUI

/// Admin editor for `config.yaml`.
///
/// The server hands out whatever is in the file, so the screen renders a
/// control per value kind instead of hard-coding a form. Only changed keys are
/// sent back – the server deep-merges them.
struct ServerConfigView: View {
    @EnvironmentObject private var session: Session
    @StateObject private var model = ConfigModel()
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            if let error = model.errorMessage {
                Section { ErrorBanner(message: error) { model.errorMessage = nil } }
            }

            ForEach($model.sections) { $section in
                Section(section.title) {
                    ForEach($section.fields) { $field in
                        ConfigFieldRow(field: $field)
                    }
                }
            }

            Section {
                Button("Reset to defaults", role: .destructive) { showResetConfirm = true }
            } footer: {
                Text("Changing the schedule reschedules the nightly job immediately. The music library path refers to the server's own filesystem – in Docker that is always /music.")
            }
        }
        .navigationTitle("Server settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { @MainActor in await model.save(session: session) }
                }
                .disabled(!model.hasChanges || model.isSaving)
            }
        }
        .overlay {
            if model.isLoading { ProgressView() }
        }
        .task { await model.load(session: session) }
        .confirmationDialog("Reset all settings?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                Task { @MainActor in await model.reset(session: session) }
            }
        }
    }
}

private struct ConfigFieldRow: View {
    @Binding var field: ConfigField

    var body: some View {
        if field.isBool {
            Toggle(field.label, isOn: $field.flag)
        } else if field.isSecret {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).font(.caption).foregroundStyle(.secondary)
                SecureField(field.secretPlaceholder, text: $field.text)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(field.label).font(.caption).foregroundStyle(.secondary)
                TextField(field.key, text: $field.text)
                    .keyboardType(field.isNumeric ? .numbersAndPunctuation : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }
}

struct ConfigField: Identifiable {
    let section: String
    let key: String
    let original: JSONValue
    var text: String
    var flag: Bool

    var id: String { "\(section).\(key)" }

    var isBool: Bool { original.boolValue != nil }

    /// The server replaces stored secrets with a sentinel instead of shipping
    /// them to the client.
    var isSecret: Bool {
        if case .string(let value) = original { return value == "__SET__" }
        return false
    }

    var isNumeric: Bool {
        switch original {
        case .int, .double: return true
        default: return false
        }
    }

    var secretPlaceholder: String {
        NSLocalizedString("unchanged", comment: "placeholder for a stored secret")
    }

    var label: String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var isChanged: Bool {
        if isBool { return flag != (original.boolValue ?? false) }
        if isSecret { return !text.isEmpty }
        return text != original.editableText
    }

    var newValue: JSONValue {
        if isBool { return .bool(flag) }
        return original.withText(text)
    }
}

struct ConfigSection: Identifiable {
    let name: String
    var fields: [ConfigField]

    var id: String { name }
    var title: String { name.replacingOccurrences(of: "_", with: " ").capitalized }
}

@MainActor
final class ConfigModel: ObservableObject {
    @Published var sections: [ConfigSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    /// Order the web settings page uses; unknown sections follow alphabetically.
    private static let sectionOrder = ["server", "library", "downloads", "nightly",
                                       "sync", "navidrome", "beets", "logging"]

    var hasChanges: Bool {
        sections.contains { $0.fields.contains(where: \.isChanged) }
    }

    func load(session: Session) async {
        guard let client = session.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let config = try await client.config()
            sections = Self.build(from: config)
        } catch APIError.unauthorized {
            await session.handleUnauthorized()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func build(from config: [String: [String: JSONValue]]) -> [ConfigSection] {
        config.keys
            .filter { !$0.hasPrefix("_") }
            .sorted { lhs, rhs in
                let l = sectionOrder.firstIndex(of: lhs) ?? Int.max
                let r = sectionOrder.firstIndex(of: rhs) ?? Int.max
                return l == r ? lhs < rhs : l < r
            }
            .compactMap { name -> ConfigSection? in
                guard let values = config[name] else { return nil }
                let fields = values.keys.sorted().compactMap { key -> ConfigField? in
                    guard let value = values[key], value.isEditableScalar else { return nil }
                    return ConfigField(section: name, key: key, original: value,
                                       text: value.boolValue == nil ? value.editableText : "",
                                       flag: value.boolValue ?? false)
                }
                return fields.isEmpty ? nil : ConfigSection(name: name, fields: fields)
            }
    }

    func save(session: Session) async {
        guard let client = session.client else { return }
        var updates: [String: [String: JSONValue]] = [:]
        for section in sections {
            for field in section.fields where field.isChanged {
                updates[section.name, default: [:]][field.key] = field.newValue
            }
        }
        guard !updates.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await client.saveConfig(updates)
            await load(session: session)
            await session.refreshMe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset(session: Session) async {
        guard let client = session.client else { return }
        do {
            try await client.resetConfig()
            await load(session: session)
            await session.refreshMe()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
