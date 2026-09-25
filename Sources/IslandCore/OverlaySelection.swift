import Foundation

/// Alfred-style filtering for the overlay's query field.
public enum TaskFilter {
    /// True when every whitespace-separated word of `query` appears, ignoring
    /// case, in the task's title, directory name, or agent name.
    public static func matches(_ task: AgentTask, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        var fields = [task.title, task.agent.displayName]
        if let cwd = task.cwd { fields.append((cwd as NSString).lastPathComponent) }
        let haystack = fields.joined(separator: "\n").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// The keyboard state of the overlay list: what the query filters down to and
/// which row is highlighted. AppKit only forwards keys here and renders `rows`.
public struct OverlaySelection: Equatable, Sendable {
    public private(set) var query = ""
    public private(set) var rows: [AgentInbox.Entry] = []
    public private(set) var selectedIndex: Int?

    private var entries: [AgentInbox.Entry]

    public init(entries: [AgentInbox.Entry]) {
        self.entries = entries
        refilter(keeping: nil)
    }

    public var selected: AgentInbox.Entry? {
        selectedIndex.map { rows[$0] }
    }

    /// New inbox contents; keeps the query and, when still listed, the
    /// highlighted task.
    public mutating func setEntries(_ entries: [AgentInbox.Entry]) {
        self.entries = entries
        refilter(keeping: selected?.id)
    }

    public mutating func setQuery(_ query: String) {
        self.query = query
        refilter(keeping: nil)
    }

    /// Up/down arrows; stops at both ends like Alfred.
    public mutating func move(by delta: Int) {
        guard let selectedIndex else { return }
        self.selectedIndex = min(max(selectedIndex + delta, 0), rows.count - 1)
    }

    /// Hovering or clicking a row.
    public mutating func select(index: Int) {
        guard rows.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// ⌘1…⌘9: the N-th visible row (1-based).
    public func entry(forShortcut number: Int) -> AgentInbox.Entry? {
        rows.indices.contains(number - 1) ? rows[number - 1] : nil
    }

    /// `↩` on the highlighted row, `⌘N` on the first nine others.
    public static func shortcutLabel(row: Int, selectedRow: Int?) -> String? {
        if row == selectedRow { return "↩" }
        return row < 9 ? "⌘\(row + 1)" : nil
    }

    private mutating func refilter(keeping id: String?) {
        rows = entries.filter { TaskFilter.matches($0.task, query: query) }
        if let id, let index = rows.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else {
            selectedIndex = rows.isEmpty ? nil : 0
        }
    }
}
