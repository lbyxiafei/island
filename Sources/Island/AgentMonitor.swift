import Foundation
import IslandCore

/// Polls the on-disk agent session stores and keeps the inbox current.
///
/// Polling rather than FSEvents is deliberate for the MVP: the sources are small
/// hand-rolled parsers, and a couple of seconds of latency is invisible next to
/// an agent turn.
@MainActor
final class AgentMonitor {
    /// Returns the ids of the given tasks the user is looking at right now.
    typealias InViewCheck = @MainActor ([AgentTask]) async -> Set<String>

    private let scanner: AgentActivityScanner
    private let inbox: AgentInbox
    private let interval: TimeInterval
    private let startedAt: Date
    /// Which scenarios to watch; Settings → Agents changes it live.
    var scenarios: AgentScenarioSettings
    private let inView: InViewCheck
    private let processes: any ProcessInspecting
    private let onChange: (_ alerted: Bool) -> Void
    private var timer: Timer?
    /// One visibility check at a time, so a slow one cannot ingest a run twice.
    private var isChecking = false

    /// `onChange(alerted)`: the inbox changed; `alerted` is true when a run
    /// arrived that the user was not already watching, i.e. worth a pop-up.
    init(
        scanner: AgentActivityScanner,
        inbox: AgentInbox,
        interval: TimeInterval = 3,
        startedAt: Date = Date(),
        scenarios: AgentScenarioSettings,
        inView: @escaping InViewCheck,
        processes: any ProcessInspecting = ProcessInspector(),
        onChange: @escaping (_ alerted: Bool) -> Void
    ) {
        self.scanner = scanner
        self.inbox = inbox
        self.interval = interval
        self.startedAt = startedAt
        self.scenarios = scenarios
        self.inView = inView
        self.processes = processes
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

    /// Also run when the user switches apps, so walking back to a finished
    /// task clears its dot without waiting for the next tick.
    func poll() {
        pruneClosed()
        guard !isChecking else { return }
        // PLAN: historical runs do not matter, only what finished after island
        // came up.
        let fresh = inbox.pending(
            scanner.completedTasks(settings: scenarios).filter { $0.completedAt >= startedAt })
        let unread = inbox.unreadEntries.map(\.task)
        guard !fresh.isEmpty || !unread.isEmpty else { return }
        isChecking = true
        Task {
            let seen = await inView(fresh + unread)
            isChecking = false
            apply(fresh: fresh, seen: seen)
        }
    }

    /// Drops rows whose session is gone: its terminal was closed or its
    /// conversation deleted (issue remove-closed-agent-title). Only agents
    /// with rows are asked, so an empty list costs nothing.
    func pruneClosed() {
        let agents = Set(inbox.allEntries.map(\.task.agent))
        guard !agents.isEmpty else { return }
        let presence = scanner.presence(of: agents, processes: processes)
        let gone = inbox.allEntries.filter { presence.isGone($0.task) }
        guard !gone.isEmpty else { return }
        for entry in gone {
            FileHandle.standardError.write(
                Data("[island] session closed, removed \"\(entry.task.title)\"\n".utf8))
        }
        inbox.removeAll(where: presence.isGone)
        onChange(false)
    }

    private func apply(fresh: [AgentTask], seen: Set<String>) {
        let change = inbox.update(fresh: fresh, seen: seen)
        if change.changed { onChange(change.alerted) }
    }
}
