import Foundation

/// How many tasks the overlay lists (PLAN § Design: N, configurable, default 10).
public enum TaskLimit {
    public static let fallback = 10

    public static func resolve(_ text: String?) -> Int {
        guard let text, let value = Int(text.trimmingCharacters(in: .whitespaces)), value > 0 else {
            return fallback
        }
        return value
    }
}

/// The in-memory list island builds from scanner output. It owns the rules
/// PLAN § Design asks for: keep only runs seen live, one row per session (its
/// latest run), order unread first then by completion time, and remember which
/// ones the user already opened.
public final class AgentInbox {
    public struct Entry: Equatable, Sendable {
        public let task: AgentTask
        public fileprivate(set) var isRead: Bool

        public var id: String { task.id }
    }

    /// How many entries the overlay shows (PLAN: N, default 10).
    public let limit: Int

    private let capacity: Int
    private var entries: [Entry] = []
    /// Latest completion seen per session, so a dropped or already-shown run is
    /// never re-added, while a newer run of the same session is.
    private var known: [String: Date] = [:]

    public init(limit: Int = 10, capacity: Int = 200) {
        self.limit = max(1, limit)
        self.capacity = max(self.limit, capacity)
    }

    /// The runs `ingest` would add: newer than anything seen for their session.
    public func pending(_ tasks: [AgentTask]) -> [AgentTask] {
        var latest = known
        return tasks.filter { task in
            if let seen = latest[task.sessionKey], seen >= task.completedAt { return false }
            latest[task.sessionKey] = task.completedAt
            return true
        }
    }

    /// Adds newly finished runs; a newer run of a listed session replaces its row
    /// and makes it unread again — unless its id is in `read`, a run the user
    /// was already looking at when it finished. Returns true when something
    /// changed, so the caller can refresh the UI only when it matters.
    @discardableResult
    public func ingest(_ tasks: [AgentTask], read: Set<String> = []) -> Bool {
        var added = false
        for task in tasks {
            let key = task.sessionKey
            if let seen = known[key], seen >= task.completedAt { continue }
            known[key] = task.completedAt
            entries.removeAll { $0.task.sessionKey == key }
            entries.append(Entry(task: task, isRead: read.contains(task.id)))
            added = true
        }
        if added {
            sort()
            trim()
        }
        return added
    }

    /// What one monitor tick did to the inbox.
    public struct Change: Equatable, Sendable {
        /// Something to redraw: a row arrived or a dot cleared.
        public let changed: Bool
        /// A run arrived that the user was not watching: worth a pop-up.
        public let alerted: Bool
    }

    /// One monitor tick: `fresh` runs arrive (read when the user watched them
    /// finish), and unread rows whose id is in `seen` — the user went back to
    /// them without going through island — lose their dot.
    public func update(fresh: [AgentTask], seen: Set<String>) -> Change {
        let visited = unreadEntries.filter { seen.contains($0.id) }
        for entry in visited { markRead(id: entry.id) }
        let pending = pending(fresh)
        let added = ingest(pending, read: seen)
        return Change(
            changed: added || !visited.isEmpty,
            alerted: pending.contains { !seen.contains($0.id) })
    }

    public var unreadCount: Int {
        entries.lazy.filter { !$0.isRead }.count
    }

    public var allEntries: [Entry] { entries }

    public var unreadEntries: [Entry] { entries.filter { !$0.isRead } }

    /// What the overlay renders: the newest `limit` entries, unread on top.
    public var visibleEntries: [Entry] { Array(entries.prefix(limit)) }

    public func markRead(id: String) {
        guard let index = entries.firstIndex(where: { $0.id == id }), !entries[index].isRead else {
            return
        }
        entries[index].isRead = true
        sort()
    }

    /// Drops the rows matching `shouldRemove` (a scenario was switched off).
    /// Their runs stay known, so switching back on does not resurrect them.
    @discardableResult
    public func removeAll(where shouldRemove: (AgentTask) -> Bool) -> Bool {
        let before = entries.count
        entries.removeAll { shouldRemove($0.task) }
        return entries.count != before
    }

    private func sort() {
        entries.sort { lhs, rhs in
            if lhs.isRead != rhs.isRead { return !lhs.isRead }
            return lhs.task.completedAt > rhs.task.completedAt
        }
    }

    /// Keeps memory bounded by dropping the oldest read entries; unread ones are
    /// never dropped, and `known` keeps them from being re-added.
    private func trim() {
        var excess = entries.count - capacity
        guard excess > 0 else { return }
        var index = entries.count - 1
        while excess > 0 && index >= 0 {
            if entries[index].isRead {
                entries.remove(at: index)
                excess -= 1
            }
            index -= 1
        }
    }
}
