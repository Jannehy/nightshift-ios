import SwiftUI

/// Monospaced live log that sticks to the bottom while new lines arrive.
///
/// The height is fixed on purpose: the log sits inside a scrolling page, so
/// without a definite height it would simply grow and push everything else off
/// screen instead of scrolling within its own frame.
struct LogView: View {
    let lines: [String]
    var height: CGFloat = 280

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(for: line))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(10)
            }
            .frame(height: height)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            // A restored log – finished or still running – arrives complete, so
            // the interesting end would otherwise sit far below the fold.
            .onAppear { scrollToEnd(proxy, animated: false) }
            .onChange(of: lines.count) { _ in scrollToEnd(proxy, animated: true) }
        }
    }

    private static let bottomAnchor = "log-bottom"

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool) {
        guard !lines.isEmpty else { return }
        Task { @MainActor in
            // The lazy stack needs one turn of the run loop before the bottom
            // anchor exists to scroll to.
            try? await Task.sleep(nanoseconds: 50_000_000)
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private func color(for line: String) -> Color {
        let lower = line.lowercased()
        if line.hasPrefix("=== DONE") || line.hasPrefix("✓") || lower.contains("downloaded") {
            return .green
        }
        if line.hasPrefix("=== FAILED") || lower.contains("error") || lower.contains("failed") {
            return .red
        }
        if line.hasPrefix("===") || line.hasPrefix("━") { return .secondary }
        if line.hasPrefix("♪") { return .primary }
        return .primary.opacity(0.85)
    }
}
