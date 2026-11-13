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
        return DeepSeekSidebar.rowShows(name, title)
    }
}

/// How island picks a session in DeepSeek's sidebar, which it reads and
/// presses through Accessibility: each session is a row whose text is the
/// session's title, grouped under a row per workspace. Only the open
/// workspace's sessions are listed, so a session elsewhere needs its
/// workspace row pressed first; `~/.dsh/storages/workspace.json` says which
/// workspace holds it.
public enum DeepSeekSidebar {
    public static func workspacesFile(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".dsh/storages/workspace.json")
    }

    /// The sidebar row naming the workspace that holds `sessionID`. The default
    /// workspace is listed as "Default workspace", whatever its folder is called.
    public static func workspaceLabel(_ sessionID: String, _ workspacesJSON: Data) -> String? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: workspacesJSON)) as? [String: Any],
            let workspaces = (root["tables"] as? [String: Any])?["workspaces"]
                as? [String: [String: Any]]
        else { return nil }
        let defaultID = (root["global"] as? [String: Any])?["defaultWorkspaceId"] as? String
        for (id, workspace) in workspaces
        where (workspace["sessionIds"] as? [String])?.contains(sessionID) == true {
            return id == defaultID ? "Default workspace" : workspace["title"] as? String
        }
        return nil
    }

    /// Whether a sidebar row whose text is `text` is the session island lists
    /// as `title` (cleaned and truncated by `TaskTitle`).
    public static func rowShows(_ text: String?, _ title: String) -> Bool {
        guard let text else { return false }
        return TaskTitle.resolve(title: text, lastMessage: nil, cwd: nil) == title
    }
}

/// The menu item that says why DeepSeek sessions neither open exactly nor
/// clear when the user reads them: island cannot read or press DeepSeek's
/// window without the Accessibility grant.
public enum AccessibilityHint {
    public static let settingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    /// Nil unless the grant is missing while DeepSeek is installed and watched.
    public static func menuTitle(
        _ trusted: Bool, _ watchesDeepSeek: Bool, _ deepSeekInstalled: Bool
    ) -> String? {
        trusted || !watchesDeepSeek || !deepSeekInstalled
            ? nil : "Allow Accessibility to open DeepSeek sessions…"
    }
}
