import SwiftUI

/// Inline error strip – used where an alert would interrupt too much.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Short-lived confirmation, e.g. after queueing a download from search.
struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(radius: 8, y: 4)
    }
}

extension View {
    func toast(_ text: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let value = text.wrappedValue {
                ToastView(text: value)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation { text.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(response: 0.3), value: text.wrappedValue)
    }
}

/// Standing notice for cookie files that stopped working.
///
/// Expired cookies are the quietest failure Nightshift has: downloads that
/// need a signed-in session come back censored or not at all, and the run
/// still reports success. Saying it on the first screen is the whole point.
struct CookieBanner: View {
    let entries: [CookieStatus]

    private var urgent: Bool { entries.contains { $0.isUrgent } }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: urgent ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                .foregroundStyle(urgent ? .red : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.footnote.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background((urgent ? Color.red : Color.orange).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var title: String {
        if entries.contains(where: { $0.state == "signed_out" }) {
            return NSLocalizedString("Cookies no longer work", comment: "")
        }
        if entries.contains(where: { $0.state == "expired" }) {
            return NSLocalizedString("Cookies expired", comment: "")
        }
        if entries.contains(where: { $0.state == "missing" }) {
            return NSLocalizedString("Cookie file not found", comment: "")
        }
        return NSLocalizedString("Cookies expire soon", comment: "")
    }

    private var detail: String {
        let parts = entries.map { entry -> String in
            switch entry.state {
            case "signed_out":
                return String(format: NSLocalizedString("%@: no longer signed in", comment: ""), entry.kind)
            case "expired":
                return String(format: NSLocalizedString("%@: expired", comment: ""), entry.kind)
            case "missing":
                return String(format: NSLocalizedString("%@: file missing", comment: ""), entry.kind)
            default:
                return String(format: NSLocalizedString("%@: %d days left", comment: ""),
                              entry.kind, Int((entry.daysLeft ?? 0).rounded()))
            }
        }
        return parts.joined(separator: " · ")
            + " — " + NSLocalizedString("Upload a fresh file in the web settings.", comment: "")
    }
}
