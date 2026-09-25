import Foundation

/// One agent's on-disk session store, reduced to the one question island asks:
/// "which runs have finished?"
///
/// Implementations must be total: a missing directory, a half-written file or a
/// malformed line yields fewer tasks, never a crash.
public protocol AgentActivitySource: Sendable {
    var agent: AgentKind { get }
    func completedTasks() -> [AgentTask]
}

/// Runs every source and returns their completed tasks, newest first.
public struct AgentActivityScanner: Sendable {
    private let sources: [any AgentActivitySource]

    public init(sources: [any AgentActivitySource]) {
        self.sources = sources
    }

    /// The sources wired to this machine's standard agent locations. `sqlite`
    /// is supplied by the app; core has no process plumbing of its own.
    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sqlite: any SQLiteQuerying = NoSQLiteQuerying()
    ) -> AgentActivityScanner {
        AgentActivityScanner(sources: [
            ClaudeCodeActivitySource.standard(home: home),
            PiActivitySource.standard(home: home),
            CodexActivitySource.standard(home: home, sqlite: sqlite),
        ])
    }

    public func completedTasks() -> [AgentTask] {
        sources.flatMap { $0.completedTasks() }
            .sorted { $0.completedAt > $1.completedAt }
    }
}

// MARK: - Claude Code

/// Claude Code keeps one live `~/.claude/sessions/<pid>.json` per running
/// process. `status` flips `busy` -> `idle` whenever the process goes quiet,
/// which also happens when a session is just opened or the user presses esc,
/// so the transcript decides whether a turn actually finished.
public struct ClaudeCodeActivitySource: AgentActivitySource {
    public let agent = AgentKind.claudeCode

    private let sessionsDirectory: URL
    private let projectsDirectory: URL
    private let transcripts = ClaudeTranscriptCache()

    public init(sessionsDirectory: URL, projectsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
        self.projectsDirectory = projectsDirectory
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeCodeActivitySource {
        ClaudeCodeActivitySource(
            sessionsDirectory: home.appendingPathComponent(".claude/sessions"),
            projectsDirectory: home.appendingPathComponent(".claude/projects")
        )
    }

    public func completedTasks() -> [AgentTask] {
        AgentFiles.directoryContents(sessionsDirectory)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                    let state = try? JSONDecoder().decode(ClaudeSessionState.self, from: data),
                    state.status == "idle",
                    let sessionID = state.sessionId, !sessionID.isEmpty,
                    let file = Self.sessionFile(sessionID: sessionID, in: projectsDirectory)
                else { return nil }
                return Self.task(from: state, transcript: transcripts.transcript(at: file))
            }
    }

    /// The transcript lives in `<projects>/<cwd-slug>/<sessionId>.jsonl`; the
    /// slug encoding is undocumented, so just look for the file by id.
    static func sessionFile(sessionID: String, in projectsDirectory: URL) -> URL? {
        AgentFiles.directoryContents(projectsDirectory)
            .map { $0.appendingPathComponent("\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func task(from state: ClaudeSessionState, transcript: Transcript?) -> AgentTask? {
        guard state.status == "idle", let sessionID = state.sessionId, !sessionID.isEmpty,
            let transcript, transcript.isComplete
        else { return nil }
        let completedAt =
            transcript.completedAt
            ?? state.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        // `derived` names are Claude's own `<dir>-<hex>` placeholders, not titles.
        let ownName = state.nameSource == "derived" ? nil : state.name
        let title = [transcript.customTitle, ownName, transcript.aiTitle]
            .compactMap { $0 }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return AgentTask(
            agent: .claudeCode,
            sessionID: sessionID,
            title: TaskTitle.resolve(
                title: title, lastMessage: transcript.lastPrompt, cwd: state.cwd),
            cwd: state.cwd,
            completedAt: completedAt,
            host: state.pid.map(AgentHost.terminal) ?? .unknown,
            resumeCommand: "claude --resume \(sessionID)"
        )
    }

    struct ClaudeSessionState: Decodable {
        let pid: Int32?
        let sessionId: String?
        let cwd: String?
        let name: String?
        let status: String?
        let updatedAt: Double?
        var nameSource: String? = nil
    }

    /// What island needs from a transcript: the titles, what the user last
    /// asked, and whether the latest turn ran to its end.
    struct Transcript: Equatable {
        var customTitle: String?
        var aiTitle: String?
        var lastPrompt: String?
        var isComplete: Bool
        var completedAt: Date?
    }

    /// A turn is finished when a `system/turn_duration` entry follows the last
    /// prompt and nothing in between says the user interrupted it.
    static func scanTranscript(_ contents: String) -> Transcript {
        var transcript = Transcript(isComplete: false)
        var interrupted = false
        for line in contents.split(separator: "\n") {
            guard let object = JSON.object(fromLine: String(line)) else { continue }
            switch object["type"] as? String {
            case "custom-title":
                transcript.customTitle = object["customTitle"] as? String ?? transcript.customTitle
            case "ai-title":
                transcript.aiTitle = object["aiTitle"] as? String ?? transcript.aiTitle
            case "system" where object["subtype"] as? String == "turn_duration":
                transcript.isComplete = !interrupted
                transcript.completedAt =
                    (object["timestamp"] as? String).flatMap(AgentTimestamp.date(from:))
            case "user":
                guard object["isMeta"] as? Bool != true, object["isSidechain"] as? Bool != true,
                    let message = object["message"] as? [String: Any],
                    let text = JSON.firstText(in: message["content"])
                else { continue }
                if text.hasPrefix("[Request interrupted by user") {
                    interrupted = true
                    transcript.isComplete = false
                    continue
                }
                // A new turn starts, including one kicked off by a slash command.
                interrupted = false
                transcript.isComplete = false
                transcript.completedAt = nil
                if !text.hasPrefix("<") { transcript.lastPrompt = text }
            default:
                break
            }
        }
        return transcript
    }
}

/// Transcripts grow to megabytes and are polled every few seconds, so each
/// file is parsed again only when its size or modification date changes.
final class ClaudeTranscriptCache: @unchecked Sendable {
    private struct Stamp: Equatable {
        let size: Int
        let modified: Date
    }

    private let lock = NSLock()
    private var entries: [String: (stamp: Stamp, transcript: ClaudeCodeActivitySource.Transcript)] =
        [:]

    func transcript(at url: URL) -> ClaudeCodeActivitySource.Transcript? {
        guard
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .contentModificationDateKey,
            ]),
            let size = values.fileSize, let modified = values.contentModificationDate
        else { return nil }
        let stamp = Stamp(size: size, modified: modified)
        lock.lock()
        defer { lock.unlock() }
        if let cached = entries[url.path], cached.stamp == stamp { return cached.transcript }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let transcript = ClaudeCodeActivitySource.scanTranscript(contents)
        entries[url.path] = (stamp, transcript)
        return transcript
    }
}

// MARK: - pi

/// pi writes `~/.pi/agent/sessions/<slug>/<ts>_<id>.jsonl`; the last assistant
/// message carries `stopReason`, and `stop` means the turn is over.
public struct PiActivitySource: AgentActivitySource {
    public let agent = AgentKind.pi

    private let sessionsRoot: URL

    public init(sessionsRoot: URL) {
        self.sessionsRoot = sessionsRoot
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PiActivitySource {
        PiActivitySource(sessionsRoot: home.appendingPathComponent(".pi/agent/sessions"))
    }

    public func completedTasks() -> [AgentTask] {
        AgentFiles.directoryContents(sessionsRoot).compactMap { project -> AgentTask? in
            let files = AgentFiles.directoryContents(project)
            // Only the newest session per project can be the one just finished.
            let newest =
                files
                .filter { $0.pathExtension == "jsonl" }
                .max { Self.modifiedAt($0) < Self.modifiedAt($1) }
            guard let newest,
                let contents = try? String(contentsOf: newest, encoding: .utf8),
                let scan = Self.scan(contents: contents, fileModified: Self.modifiedAt(newest)),
                scan.isComplete
            else { return nil }
            return AgentTask(
                agent: .pi,
                sessionID: scan.sessionID,
                title: TaskTitle.resolve(
                    title: scan.title, lastMessage: scan.lastMessage, cwd: scan.cwd),
                cwd: scan.cwd,
                completedAt: scan.completedAt,
                host: .unknown,
                resumeCommand: "pi --session \(scan.sessionID)"
            )
        }
    }

    static func modifiedAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    struct SessionScan: Equatable {
        let sessionID: String
        let cwd: String?
        /// The `/name` the user gave the session, if any.
        let title: String?
        /// The last thing the user asked — the fallback when there is no title.
        let lastMessage: String?
        let completedAt: Date
        let isComplete: Bool
    }

    /// Pure parser over a whole pi session file, so tests can feed fixtures.
    static func scan(contents: String, fileModified: Date) -> SessionScan? {
        var sessionID: String?
        var cwd: String?
        var sessionName: String?
        var lastUserText: String?
        var lastAssistantStop: String?
        var lastAssistantDate: Date?
        var lastTimestamp: Date?

        for line in contents.split(separator: "\n") {
            guard let object = JSON.object(fromLine: String(line)) else { continue }
            if let timestamp = object["timestamp"] as? String,
                let date = AgentTimestamp.date(from: timestamp)
            {
                lastTimestamp = date
            }
            switch object["type"] as? String {
            case "session":
                sessionID = object["id"] as? String
                cwd = object["cwd"] as? String
            case "session_info":
                sessionName = object["name"] as? String ?? sessionName
            case "message":
                guard let message = object["message"] as? [String: Any] else { continue }
                switch message["role"] as? String {
                case "user":
                    lastUserText = JSON.firstText(in: message["content"]) ?? lastUserText
                case "assistant":
                    lastAssistantStop = message["stopReason"] as? String
                    lastAssistantDate =
                        (object["timestamp"] as? String).flatMap(AgentTimestamp.date(from:))
                default:
                    break
                }
            default:
                break
            }
        }

        guard let sessionID else { return nil }
        return SessionScan(
            sessionID: sessionID,
            cwd: cwd,
            title: sessionName,
            lastMessage: lastUserText,
            completedAt: lastAssistantDate ?? lastTimestamp ?? fileModified,
            isComplete: lastAssistantStop == "stop"
        )
    }
}

// MARK: - Shared JSON helpers

enum AgentFiles {
    /// Directory listing that treats "does not exist" as "nothing to report".
    static func directoryContents(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))
            ?? []
    }
}

enum AgentTimestamp {
    /// Codex and pi emit fractional seconds; Claude Code does not.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

enum JSON {
    static func object(fromLine line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    /// Content is either a bare string or a list of typed blocks; take the first
    /// block that carries human text.
    static func firstText(in content: Any?) -> String? {
        if let text = content as? String, !text.isEmpty { return text }
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks {
            if let text = block["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    static func truncated(_ text: String, limit: Int = 72) -> String {
        let collapsed =
            text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.count <= limit ? collapsed : String(collapsed.prefix(limit)) + "…"
    }
}
