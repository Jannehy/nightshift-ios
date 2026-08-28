import SwiftUI

/// How a log line reads at a glance.
///
/// A track the catalogue does not have is an outcome, not a failure; counting
/// it as an error made a finished run look broken. The three cases here match
/// what the web interface shows, so the same run does not describe itself
/// differently depending on where it is watched.
enum LogKind {
    case ok, warning, error, plain

    static func of(_ line: String) -> LogKind {
        let lower = line.lowercased()
        if line.hasPrefix("=== DONE") || line.hasPrefix("✓") { return .ok }
        if lower.contains("no results found") || lower.contains("lookuperror")
            || lower.contains("could not be downloaded") { return .warning }
        if line.hasPrefix("=== FAILED") || line.contains("✗") || line.contains("⚠")
            || lower.contains("error") || lower.contains("failed") { return .error }
        if lower.contains("downloaded") { return .ok }
        return .plain
    }

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .error: return .red
        case .plain: return .primary.opacity(0.85)
        }
    }
}

/// The log, folded away.
///
/// While something runs, two questions matter: is it still going, and did
/// anything go wrong. The header answers both. The lines themselves are for
/// whoever wants them, and start hidden - on a phone they otherwise fill the
/// screen and push everything else out of reach.
struct ConsoleView: View {
    let lines: [String]
    let isRunning: Bool
    var height: CGFloat = 280

    @State private var isOpen = false

    private var errorCount: Int {
        lines.filter { LogKind.of($0) == .error }.count
    }
    private var missingCount: Int {
        lines.filter { LogKind.of($0) == .warning }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Console")
                        .font(.subheadline.weight(.medium))
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(summaryColor)
                    Spacer()
                    Text("\(lines.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                LogView(lines: lines, height: height)
            }
        }
    }

    private var summary: String {
        var parts = [isRunning
            ? NSLocalizedString("running", comment: "console state")
            : NSLocalizedString("done", comment: "console state")]
        if errorCount > 0 {
            parts.append(String(format: NSLocalizedString("%d error(s)", comment: ""),
                                errorCount))
        }
        if missingCount > 0 {
            parts.append(String(format: NSLocalizedString("%d not found", comment: ""),
                                missingCount))
        }
        return parts.joined(separator: " · ")
    }

    private var summaryColor: Color {
        if errorCount > 0 { return .red }
        if missingCount > 0 { return .orange }
        return .secondary
    }
}
