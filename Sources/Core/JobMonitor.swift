import Foundation
import SwiftUI

/// Drives one of the server's two live logs.
///
/// While the app owns a job id it reads the SSE stream; after a cold start –
/// when a download begun on another device or before the app was killed is
/// still running – it falls back to polling the log endpoint, which is what
/// the web UI does to restore its view.
@MainActor
final class JobMonitor: ObservableObject {

    enum Source {
        case download
        case nightly
    }

    enum State: Equatable {
        case idle
        case queued(Int)
        case running
        case finished(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .queued, .running: return true
            case .idle, .finished, .failed: return false
            }
        }
    }

    @Published private(set) var lines: [String] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var statusMessage: String?
    @Published private(set) var progress: Double?
    @Published private(set) var trackCounter: String?
    @Published private(set) var queue: QueueStatus?
    @Published var errorMessage: String?

    let source: Source
    private unowned let session: Session
    private var streamTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var currentJobID: String?

    private static let maxLines = 2000

    init(source: Source, session: Session) {
        self.source = source
        self.session = session
    }

    private var client: APIClient? { session.client }

    // MARK: - Starting work

    /// Runs the given endpoint call and attaches to the job it returns.
    func start(_ makeJob: @escaping () async throws -> JobRef) async {
        guard !state.isBusy else { return }
        errorMessage = nil
        lines = []
        progress = nil
        trackCounter = nil
        statusMessage = nil
        state = .queued(0)
        do {
            let job = try await makeJob()
            attach(to: job)
        } catch APIError.unauthorized {
            state = .idle
            await session.handleUnauthorized()
        } catch {
            state = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
        await refreshQueue()
    }

    private func attach(to job: JobRef) {
        currentJobID = job.jobID
        state = job.position > 0 ? .queued(job.position) : .running
        if job.position > 0 {
            statusMessage = String(
                format: NSLocalizedString("Queued – %d job(s) ahead", comment: ""),
                job.position)
        }
        if let count = job.trackCount {
            trackCounter = String(
                format: NSLocalizedString("%d tracks", comment: ""), count)
        }
        listen(jobID: job.jobID)
    }

    private func listen(jobID: String) {
        streamTask?.cancel()
        pollTask?.cancel()
        guard let client else { return }
        streamTask = Task { [weak self] in
            do {
                for try await event in client.events(forJob: jobID) {
                    guard !Task.isCancelled else { return }
                    self?.apply(event)
                }
                self?.streamTask = nil
                // Stream ended without a terminal event (server restart, timeout):
                // fall back to the log file so the UI does not hang on "running".
                if let self, self.state.isBusy { await self.restore() }
            } catch APIError.unauthorized {
                self?.streamTask = nil
                await self?.session.handleUnauthorized()
            } catch {
                self?.streamTask = nil
                guard !Task.isCancelled else { return }
                await self?.restore()
            }
        }
    }

    private func apply(_ event: JobEvent) {
        if case .queued = state { state = .running }
        if let line = event.logLine { append(line) }

        switch event.type {
        case "status":
            statusMessage = event.message
            if let p = event.progress { progress = Double(p) / 100 }
        case "progress":
            if let p = event.progress { progress = Double(p) / 100 }
            if let current = event.current, let total = event.total, total > 0 {
                trackCounter = "\(current)/\(total)"
            }
        case "done":
            progress = 1
            statusMessage = event.message
            state = .finished(event.message ?? NSLocalizedString("Done", comment: ""))
        case "error":
            statusMessage = event.message
            state = .failed(event.message ?? NSLocalizedString("Failed", comment: ""))
        default:
            break
        }
    }

    private func append(_ line: String) {
        lines.append(line)
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines)
        }
    }

    // MARK: - Restoring after a cold start

    /// Reads the server-side log file and, if work is still in flight, keeps
    /// polling until it finishes.
    func restore() async {
        guard let client else { return }
        do {
            let log = try await fetchLog(client)
            applyLogState(log)
            if log.isRunning && streamTask == nil { startPolling() }
        } catch APIError.unauthorized {
            await session.handleUnauthorized()
        } catch {
            // A missing log is normal on a fresh server – stay quiet.
        }
        await refreshQueue()
    }

    private func fetchLog(_ client: APIClient) async throws -> LogState {
        switch source {
        case .download: return try await client.downloadLog()
        case .nightly: return try await client.nightlyLog()
        }
    }

    private func applyLogState(_ log: LogState) {
        let incoming = log.lines.filter { !$0.isEmpty }
        // Only adopt the file while no live stream is feeding the view.
        guard streamTask == nil || lines.isEmpty else { return }
        lines = Array(incoming.suffix(Self.maxLines))
        if log.failed {
            state = .failed(NSLocalizedString("Failed", comment: ""))
        } else if log.finished {
            state = .finished(NSLocalizedString("Done", comment: ""))
            progress = 1
        } else if log.isRunning {
            state = .running
        } else {
            state = .idle
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, let client = self.client else { return }
                guard let log = try? await self.fetchLog(client) else { continue }
                await MainActor.run { self.applyLogState(log) }
                if !log.isRunning { return }
            }
        }
    }

    func refreshQueue() async {
        guard let client else { return }
        queue = try? await client.queue()
    }

    /// Detach from the current job without cancelling server-side work – the
    /// server has no cancel endpoint, so this only clears the view.
    func clear() {
        streamTask?.cancel()
        pollTask?.cancel()
        streamTask = nil
        pollTask = nil
        currentJobID = nil
        lines = []
        state = .idle
        progress = nil
        statusMessage = nil
        trackCounter = nil
        errorMessage = nil
    }

    func stopStreaming() {
        streamTask?.cancel()
        pollTask?.cancel()
        streamTask = nil
        pollTask = nil
    }
}
