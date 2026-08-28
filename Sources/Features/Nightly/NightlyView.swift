import SwiftUI

/// The nightly sync: schedule, manual trigger and its own live log.
struct NightlyView: View {
    @EnvironmentObject private var session: Session
    @ObservedObject var monitor: JobMonitor

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    scheduleCard
                    if monitor.state != .idle || !monitor.lines.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            JobStatusView(monitor: monitor)
                            ConsoleView(lines: monitor.lines,
                                        isRunning: monitor.state.isBusy,
                                        height: 340)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    if let error = monitor.errorMessage {
                        ErrorBanner(message: error) { monitor.errorMessage = nil }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nightly")
            .refreshable { await monitor.restore() }
            .task { await monitor.restore() }
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scheduled")
                        .font(.subheadline.weight(.medium))
                    Text(scheduleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("Re-syncs every synced playlist, tags new files and rewrites the m3u8 playlists. Large playlists continue the next night when rate limits cut them short.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                guard let client = session.client else { return }
                Task { @MainActor in await monitor.start { try await client.startNightly() } }
            } label: {
                HStack {
                    Spacer()
                    Label("Run now", systemImage: "play.circle.fill")
                    Spacer()
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(monitor.state.isBusy)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var scheduleText: String {
        guard let cron = session.me?.nightlySchedule, !cron.isEmpty else {
            return NSLocalizedString("Unknown", comment: "")
        }
        return CronDescription.describe(cron)
    }
}

/// Turns the handful of cron shapes Nightshift actually uses into plain text;
/// anything else falls back to the raw expression.
enum CronDescription {
    static func describe(_ cron: String) -> String {
        let parts = cron.split(separator: " ").map(String.init)
        guard parts.count == 5 else { return cron }
        let (minute, hour, dayOfMonth, month, weekday) = (parts[0], parts[1], parts[2], parts[3], parts[4])
        guard let m = Int(minute), let h = Int(hour),
              dayOfMonth == "*", month == "*" else { return cron }
        let time = String(format: "%02d:%02d", h, m)
        if weekday == "*" {
            return String(format: NSLocalizedString("Daily at %@", comment: ""), time)
        }
        if let day = Int(weekday), (0...7).contains(day) {
            let names = Calendar.current.weekdaySymbols  // index 0 = Sunday
            let name = names[day % 7]
            return String(format: NSLocalizedString("%@ at %@", comment: ""), name, time)
        }
        return cron
    }
}
