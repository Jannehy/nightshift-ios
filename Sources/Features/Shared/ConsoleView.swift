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
        if isCount(line) { return .plain }
        // Plain "error" also hides inside words that mean nothing here:
        // a track by "Absolute Terror" turned a clean run red, and the
        // server then repeated the invented entry in its closing summary,
        // so one line was counted three times. The word boundary rules
        // those out; the second test puts back the compound exception
        // names it would otherwise lose (HTTPError, ConnectionError).
        if line.hasPrefix("=== FAILED") || line.contains("✗") || line.contains("⚠")
            || line.range(of: #"\b(?:error|failed)"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
            || line.range(of: #"[A-Za-z]Error\b"#,
                          options: .regularExpression) != nil { return .error }
        if lower.contains("downloaded") { return .ok }
        return .plain
    }

    /// `[2026-08-29 03:11:28]   Playlists failed:     0` — a closing statistic.
    ///
    /// The word "failed" makes such a line look like a failure while it is
    /// only a count, so it is recognised by its shape instead: a short label,
    /// a colon, a number, nothing else. The timestamp the server writes in
    /// front carries colons of its own and has to go first, or the shape never
    /// matches.
    private static func isCount(_ line: String) -> Bool {
        var body = Substring(line).drop { $0 == " " || $0 == "\t" || $0 == "•" || $0 == "-" }
        if body.first == "[", let close = body.firstIndex(of: "]") {
            body = body[body.index(after: close)...].drop { $0 == " " }
        }
        guard let colon = body.firstIndex(of: ":") else { return false }
        let label = body[..<colon]
        guard !label.isEmpty, label.count <= 40 else { return false }
        let value = body[body.index(after: colon)...]
            .trimmingCharacters(in: .whitespaces)
        return !value.isEmpty && value.allSatisfy(\.isNumber)
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

    /// A run closes with "Errors in this run (N):" and repeats every entry as
    /// a bullet underneath. Counting coloured lines therefore counts one
    /// failure three times - where it happened, in the heading, in the bullet.
    /// Where the server states a number, that number wins; the tally is only
    /// a fallback for a run still in progress.
    private func statedTotal(after marker: String) -> Int? {
        for line in lines.reversed() {
            guard let found = line.range(of: marker) else { continue }
            let rest = line[found.upperBound...]
            guard let open = rest.firstIndex(of: "("),
                  let close = rest.firstIndex(of: ")"), open < close
            else { continue }
            return Int(rest[rest.index(after: open)..<close])
        }
        return nil
    }

    private func isSummary(_ line: String) -> Bool {
        var body = Substring(line).drop { $0 == " " || $0 == "\t" }
        if body.first == "[", let close = body.firstIndex(of: "]") {
            body = body[body.index(after: close)...].drop { $0 == " " }
        }
        return body.first == "\u{2022}"
            || line.contains("Errors in this run")
            || line.contains("Not found (")
    }

    private var errorCount: Int {
        statedTotal(after: "Errors in this run")
            ?? lines.filter { !isSummary($0) && LogKind.of($0) == .error }.count
    }
    private var missingCount: Int {
        statedTotal(after: "Not found")
            ?? lines.filter { !isSummary($0) && LogKind.of($0) == .warning }.count
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
            parts.append(errorCount == 1
                ? NSLocalizedString("1 error", comment: "console summary")
                : String(format: NSLocalizedString("%d errors", comment: "console summary"),
                         errorCount))
        }
        if missingCount > 0 {
            parts.append(missingCount == 1
                ? NSLocalizedString("1 not found", comment: "console summary")
                : String(format: NSLocalizedString("%d not found", comment: "console summary"),
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
