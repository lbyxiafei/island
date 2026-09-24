import Foundation
import IslandCore

/// Polls the on-disk agent session stores and keeps the inbox current.
///
/// Polling rather than FSEvents is deliberate for the MVP: the sources are small
/// hand-rolled parsers, and a couple of seconds of latency is invisible next to
/// an agent turn.
@MainActor
final class AgentMonitor {
    private let scanner: AgentActivityScanner
    private let inbox: AgentInbox
    private let interval: TimeInterval
    private let startedAt: Date
    private let onChange: () -> Void
    private var timer: Timer?

    init(
        scanner: AgentActivityScanner,
        inbox: AgentInbox,
        interval: TimeInterval = 3,
        startedAt: Date = Date(),
        onChange: @escaping () -> Void
    ) {
        self.scanner = scanner
        self.inbox = inbox
        self.interval = interval
        self.startedAt = startedAt
        self.onChange = onChange
    }

    func start() {
        poll()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        // PLAN: historical runs do not matter, only what finished after island
        // came up.
        let fresh = scanner.completedTasks().filter { $0.completedAt >= startedAt }
        if inbox.ingest(fresh) {
            onChange()
        }
    }
}
