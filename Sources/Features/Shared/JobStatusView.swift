import SwiftUI

/// Progress bar, status line and queue position for a running job.
struct JobStatusView: View {
    @ObservedObject var monitor: JobMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                icon
                Text(headline)
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let counter = monitor.trackCounter {
                    Text(counter)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if monitor.state.isBusy {
                if let progress = monitor.progress {
                    ProgressView(value: progress)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }

            if let message = monitor.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let queue = monitor.queue, !queue.pending.isEmpty {
                Text(String(format: NSLocalizedString("%d job(s) waiting", comment: ""),
                            queue.pending.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var icon: some View {
        switch monitor.state {
        case .idle:
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        case .queued:
            Image(systemName: "clock").foregroundStyle(.orange)
        case .running:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
        case .finished:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var headline: String {
        switch monitor.state {
        case .idle: return NSLocalizedString("Idle", comment: "")
        case .queued(let position):
            return position > 0
                ? String(format: NSLocalizedString("Queued – %d job(s) ahead", comment: ""), position)
                : NSLocalizedString("Starting …", comment: "")
        case .running: return NSLocalizedString("Running", comment: "")
        case .finished(let message): return message
        case .failed(let message): return message
        }
    }
}
