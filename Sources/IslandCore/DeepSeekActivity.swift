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
public struct DeepSeekActivitySource: AgentActivitySource {
    public let agent = AgentKind.deepseek

    static let bundleID = "com.deepseek.dsh"

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
}
