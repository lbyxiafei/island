import Foundation

/// DeepSeek Harness (an Electron app) logs each session as a zstd-compressed
/// event stream, but also keeps a plain-JSON projection of every session's
/// state in `~/.dsh/storages/session_projcache/sessions/session-<id>.json`,
/// rewritten as the session runs. island reads only that projection.
///
/// `turnBoundary` tells a finished turn apart: `openTurnStartSeq` is set while
/// a turn runs and cleared when it ends, and the last step boundary is an
/// `end`. `timeContext.lastMessageTime` (epoch ms) is the turn's last message.
/// The app registers only `dsh://open`, which brings its window forward; it
/// has no link to a single session.
///
/// Teammates and subagents a session spawns get files of their own, marked by
/// a `subagent.identity`; they are steps of the parent's run, not conversations
/// the user opens, so they are skipped. The main window's title is the open
/// session's title, which is how island tells which session is on screen.
public struct DeepSeekActivitySource: AgentActivitySource {
    public let agent = AgentKind.deepseek

    public static let bundleID = "com.deepseek.dsh"

    static let windowTitleSuffix = " — DeepSeek Harness"

    private let cacheDirectory: URL

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> DeepSeekActivitySource {
        DeepSeekActivitySource(
            cacheDirectory: home.appendingPathComponent(".dsh/storages/session_projcache/sessions"))
    }

    public func completedTasks() -> [AgentTask] {
        AgentFiles.directoryContents(cacheDirectory)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                (try? Data(contentsOf: url)).flatMap {
                    Self.task(sessionID: url.deletingPathExtension().lastPathComponent, from: $0)
                }
            }
    }

    static func task(sessionID: String, from data: Data) -> AgentTask? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let record = root["record"] as? [String: Any],
            let rows = record["rows"] as? [String: Any]
        else { return nil }
        func value(_ row: String) -> Any? { (rows[row] as? [String: Any])?["val"] }
        if (value("subagent") as? [String: Any])?["identity"] is [String: Any] { return nil }

        guard let boundary = value("turnBoundary") as? [String: Any],
            boundary["openTurnStartSeq"] is NSNull,
            (boundary["lastStepBoundary"] as? [String: Any])?["kind"] as? String == "end",
            let lastTurn = boundary["lastTurn"] as? Int, lastTurn > 0,
            let lastMessage = (value("timeContext") as? [String: Any])?["lastMessageTime"]
                as? Double
        else { return nil }

        let identity = record["identity"] as? [String: Any]
        let cwd = value("workingDirectory") as? String ?? identity?["cwd"] as? String
        let firstPrompt =
            ((value("titleInput") as? [String: Any])?["first"] as? [String: Any])?[
                "text"] as? String
        return AgentTask(
            agent: .deepseek,
            sessionID: sessionID,
            title: TaskTitle.resolve(
                title: value("title") as? String, lastMessage: firstPrompt, cwd: cwd),
            cwd: cwd,
            completedAt: Date(timeIntervalSince1970: lastMessage / 1000),
            host: .desktop(bundleID: bundleID),
            resumeCommand: nil,
            deepLink: "dsh://open"
        )
    }

    /// Whether the app's focused window, titled `windowTitle`, shows the
    /// session island lists as `title` (already cleaned by `TaskTitle`).
    public static func windowShows(_ windowTitle: String?, _ title: String) -> Bool {
        guard var name = windowTitle else { return false }
        if name.hasSuffix(windowTitleSuffix) { name.removeLast(windowTitleSuffix.count) }
        return TaskTitle.resolve(title: name, lastMessage: nil, cwd: nil) == title
    }
}
