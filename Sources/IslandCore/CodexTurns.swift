import Foundation

/// Runs a SQLite query and returns the rows as JSON (what `sqlite3 -json`
/// prints). Injected so the parsing below stays testable; the real
/// implementation lives in the executable target next to the other process
/// plumbing.
public protocol SQLiteQuerying: Sendable {
    func query(database: URL, sql: String) -> String?
}

/// Used when the app supplies no runner: Codex then falls back to the lighter
/// `session_index.jsonl` source instead of the turn history.
public struct NoSQLiteQuerying: SQLiteQuerying {
    public init() {}
    public func query(database: URL, sql: String) -> String? { nil }
}

/// Codex's authoritative history: `thread_turns` records every turn with a
/// `status` and a `completed_at`, which covers the desktop app and the CLI
/// alike (the lighter `session_index.jsonl` does not always see desktop runs).
public struct CodexTurnActivitySource: AgentActivitySource {
    public let agent = AgentKind.codex

    private let threadsDatabase: URL
    private let historyDatabase: URL
    private let runner: any SQLiteQuerying

    public init(threadsDatabase: URL, historyDatabase: URL, runner: any SQLiteQuerying) {
        self.threadsDatabase = threadsDatabase
        self.historyDatabase = historyDatabase
        self.runner = runner
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runner: any SQLiteQuerying
    ) -> CodexTurnActivitySource {
        CodexTurnActivitySource(
            threadsDatabase: home.appendingPathComponent(".codex/state_5.sqlite"),
            historyDatabase: home.appendingPathComponent(".codex/thread_history_1.sqlite"),
            runner: runner
        )
    }

    public func completedTasks() -> [AgentTask] {
        guard
            let output = runner.query(
                database: threadsDatabase, sql: Self.sql(history: historyDatabase))
        else { return [] }
        return Self.parse(output)
    }

    /// Deleting a thread in Codex archives it, so the open threads are the
    /// unarchived ones.
    public func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? {
        guard
            let output = runner.query(
                database: threadsDatabase, sql: "select id from threads where archived = 0;"),
            let rows = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [Any]
        else { return nil }
        return Set(rows.compactMap { ($0 as? [String: Any])?["id"] as? String })
    }

    /// The thread metadata (title, cwd) and the turn history live in two files,
    /// so the query attaches one to the other. `name` is the short title Codex
    /// shows; `title` is the raw first user message; `last_prompt` is the last
    /// thing the user typed (slash-command wrappers start with `<`).
    static func sql(history: URL) -> String {
        """
        attach database '\(history.path)' as history;
        select threads.id as id,
               threads.name as name,
               threads.title as title,
               threads.cwd as cwd,
               threads.source as source,
               max(history.thread_turns.completed_at) as completed_at,
               (select json_extract(items.item_json, '$.content[0].text')
                from history.thread_items as items
                where items.thread_id = threads.id
                  and items.item_type = 'userMessage'
                  and json_extract(items.item_json, '$.content[0].text') not like '<%'
                order by items.rollout_ordinal desc
                limit 1) as last_prompt
        from history.thread_turns
        join threads on threads.id = history.thread_turns.thread_id
        where history.thread_turns.status = 'completed'
        group by threads.id
        order by completed_at desc
        limit 100;
        """
    }

    static func parse(_ output: String) -> [AgentTask] {
        // `as? [[String: Any]]` fails for a whole array as soon as one element is
        // not an object, so go through `[Any]` and skip the stragglers.
        guard let data = output.data(using: .utf8),
            let rows = (try? JSONSerialization.jsonObject(with: data)) as? [Any]
        else { return [] }
        return rows.compactMap { $0 as? [String: Any] }.compactMap { row in
            guard let id = row["id"] as? String,
                let seconds = (row["completed_at"] as? NSNumber)?.doubleValue
            else { return nil }
            let cwd = row["cwd"] as? String
            let prompt = [row["last_prompt"], row["title"]]
                .compactMap { $0 as? String }
                .first { !$0.isEmpty }
            return AgentTask(
                agent: .codex,
                sessionID: id,
                title: TaskTitle.resolve(
                    title: row["name"] as? String, lastMessage: prompt, cwd: cwd),
                cwd: cwd,
                completedAt: Date(timeIntervalSince1970: seconds),
                host: .desktop(bundleID: "com.openai.codex"),
                resumeCommand: "codex resume \(id)",
                deepLink: "codex://threads/\(id)",
                scenario: scenario(source: row["source"] as? String).id
            )
        }
    }

    /// `threads.source`: `cli` for the TUI, `exec` for headless runs, `vscode`
    /// for both the desktop app and the IDE extension (they share it).
    static func scenario(source: String?) -> AgentScenario {
        switch source {
        case "cli": return .codexCLI
        case "exec": return .codexExec
        default: return .codexApp
        }
    }
}

/// The lighter `~/.codex/session_index.jsonl`, kept as a fallback for installs
/// whose SQLite files are missing or unreadable.
public struct CodexIndexActivitySource: AgentActivitySource {
    public let agent = AgentKind.codex

    private let sessionIndex: URL

    public init(sessionIndex: URL) {
        self.sessionIndex = sessionIndex
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CodexIndexActivitySource {
        CodexIndexActivitySource(
            sessionIndex: home.appendingPathComponent(".codex/session_index.jsonl"))
    }

    public func completedTasks() -> [AgentTask] {
        guard let contents = try? String(contentsOf: sessionIndex, encoding: .utf8) else {
            return []
        }
        return Self.parseIndex(contents)
    }

    static func parseIndex(_ contents: String) -> [AgentTask] {
        contents.split(separator: "\n").compactMap { line in
            guard let object = JSON.object(fromLine: String(line)),
                let id = object["id"] as? String,
                let updatedText = object["updated_at"] as? String,
                let updatedAt = AgentTimestamp.date(from: updatedText)
            else { return nil }
            let title = (object["thread_name"] as? String) ?? ""
            return AgentTask(
                agent: .codex,
                sessionID: id,
                title: TaskTitle.resolve(title: title, lastMessage: nil, cwd: nil),
                cwd: nil,
                completedAt: updatedAt,
                host: .desktop(bundleID: "com.openai.codex"),
                resumeCommand: "codex resume \(id)",
                deepLink: "codex://threads/\(id)",
                // The index does not say where a thread ran.
                scenario: AgentScenario.codexApp.id
            )
        }
    }
}

/// Prefers the turn history and degrades to the index.
public struct CodexActivitySource: AgentActivitySource {
    public let agent = AgentKind.codex

    private let turns: CodexTurnActivitySource
    private let index: CodexIndexActivitySource

    public init(turns: CodexTurnActivitySource, index: CodexIndexActivitySource) {
        self.turns = turns
        self.index = index
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sqlite: any SQLiteQuerying
    ) -> CodexActivitySource {
        CodexActivitySource(
            turns: CodexTurnActivitySource.standard(home: home, runner: sqlite),
            index: CodexIndexActivitySource.standard(home: home)
        )
    }

    public func completedTasks() -> [AgentTask] {
        let fromTurns = turns.completedTasks()
        return fromTurns.isEmpty ? index.completedTasks() : fromTurns
    }

    /// Only the thread database knows about archiving; the index cannot tell.
    public func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? {
        turns.liveSessionIDs(processes: processes)
    }
}
