import Foundation

/// One agent's on-disk session store, reduced to the one question island asks:
/// "which runs have finished?" — the detection half of an agent integration;
/// the declarative half is its `AgentProfile`.
///
/// Implementations must be total: a missing directory, a half-written file or a
/// malformed line yields fewer tasks, never a crash. Each task is tagged with
/// one of `agent.profile.scenarios`, so the user can switch that kind of run
/// off without the source knowing about settings.
public protocol AgentActivitySource: Sendable {
    var agent: AgentKind { get }
    func completedTasks() -> [AgentTask]
    /// The ids of the sessions that are still open, or nil when the source
    /// cannot tell (see `SessionPresence`).
    func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>?
}

/// Runs every source and returns their completed tasks, newest first.
public struct AgentActivityScanner: Sendable {
    let sources: [any AgentActivitySource]

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
            ClaudeDesktopActivitySource.standard(home: home),
            PiActivitySource.standard(home: home),
            CodexActivitySource.standard(home: home, sqlite: sqlite),
        ])
    }

    /// Runs of switched-off scenarios are dropped, and an agent with every
    /// scenario off is not read at all.
    public func completedTasks(
        settings: AgentScenarioSettings = AgentScenarioSettings()
    ) -> [AgentTask] {
        let agents = settings.enabledAgents
        return
            sources
            .filter { agents.contains($0.agent) }
            .flatMap { $0.completedTasks() }
            .filter(settings.allows)
            .sorted { $0.completedAt > $1.completedAt }
    }
}

// MARK: - Claude Code

/// Claude Code keeps one live `~/.claude/sessions/<pid>.json` per running
/// process. Its `status` is no completion signal: it goes `idle` when a
/// session is just opened or the user presses esc, and stays `busy` after a
/// turn ends while a background task it started is still running. So every
/// session's transcript decides whether its latest turn finished.
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
                    let sessionID = state.sessionId, !sessionID.isEmpty,
                    let file = Self.sessionFile(sessionID: sessionID, in: projectsDirectory)
                else { return nil }
                return Self.task(from: state, transcript: transcripts.transcript(at: file))
            }
    }

    /// A session is open while its `<pid>.json` exists and that pid runs; a
    /// file that fails to decode (caught mid-write) makes the answer unknown.
    public func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? {
        var live: Set<String> = []
        for url in AgentFiles.directoryContents(sessionsDirectory) where url.pathExtension == "json"
        {
            guard let data = try? Data(contentsOf: url),
                let state = try? JSONDecoder().decode(ClaudeSessionState.self, from: data)
            else { return nil }
            guard let sessionID = state.sessionId, !sessionID.isEmpty else { continue }
            if let pid = state.pid, !processes.isRunning(pid) { continue }
            live.insert(sessionID)
        }
        return live
    }

    /// The transcript lives in `<projects>/<cwd-slug>/<sessionId>.jsonl`; the
    /// slug encoding is undocumented, so just look for the file by id.
    static func sessionFile(sessionID: String, in projectsDirectory: URL) -> URL? {
        AgentFiles.directoryContents(projectsDirectory)
            .map { $0.appendingPathComponent("\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func task(from state: ClaudeSessionState, transcript: Transcript?) -> AgentTask? {
        guard let sessionID = state.sessionId, !sessionID.isEmpty,
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
            resumeCommand: "claude --resume \(sessionID)",
            scenario: scenario(entrypoint: state.entrypoint).id
        )
    }

    /// The session file's `entrypoint` says who started the process. Only
    /// `cli` has been seen on this machine; the others follow Claude Code's
    /// `CLAUDE_CODE_ENTRYPOINT` naming, and anything unknown lands in headless.
    /// Files written before the field existed are terminal sessions.
    static func scenario(entrypoint: String?) -> AgentScenario {
        guard let entrypoint, entrypoint != "cli" else { return .claudeCodeTerminal }
        if entrypoint.contains("desktop") { return .claudeCodeDesktop }
        if entrypoint.contains("vscode") || entrypoint.contains("jetbrains") {
            return .claudeCodeEditor
        }
        return .claudeCodeHeadless
    }

    struct ClaudeSessionState: Decodable {
        let pid: Int32?
        let sessionId: String?
        let cwd: String?
        let name: String?
        /// `idle` / `busy`; informational only, see the type's comment.
        let status: String?
        let updatedAt: Double?
        var nameSource: String? = nil
        var entrypoint: String? = nil
    }

    /// What island needs from a transcript: the titles, what the user last
    /// asked, and whether the latest turn ran to its end.
    struct Transcript: Equatable {
        var customTitle: String?
        var aiTitle: String?
        var lastPrompt: String?
        var isComplete: Bool
        var completedAt: Date?
        /// The current turn was cut short; carried so a scan can resume.
        var isInterrupted = false
    }

    /// A turn is finished when a `system/turn_duration` entry follows the last
    /// prompt and nothing in between says the user interrupted it.
    /// `continuing` is the state after the lines before `contents`, so an
    /// appended chunk can be scanned without rereading the whole file.
    static func scanTranscript(
        _ contents: String, continuing: Transcript = Transcript(isComplete: false)
    ) -> Transcript {
        var transcript = continuing
        for line in contents.split(separator: "\n") {
            guard let object = JSON.object(fromLine: String(line)) else { continue }
            switch object["type"] as? String {
            case "custom-title":
                transcript.customTitle = object["customTitle"] as? String ?? transcript.customTitle
            case "ai-title":
                transcript.aiTitle = object["aiTitle"] as? String ?? transcript.aiTitle
            case "system" where object["subtype"] as? String == "turn_duration":
                transcript.isComplete = !transcript.isInterrupted
                transcript.completedAt =
                    (object["timestamp"] as? String).flatMap(AgentTimestamp.date(from:))
            case "user":
                guard object["isMeta"] as? Bool != true, object["isSidechain"] as? Bool != true,
                    let message = object["message"] as? [String: Any],
                    let text = JSON.firstText(in: message["content"])
                else { continue }
                if text.hasPrefix("[Request interrupted by user") {
                    transcript.isInterrupted = true
                    transcript.isComplete = false
                    continue
                }
                // A new turn starts, including one kicked off by a slash command.
                transcript.isInterrupted = false
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

/// Transcripts grow to hundreds of megabytes and a working session appends
/// to its own every few seconds, so each file is parsed once and afterwards
/// only its appended bytes are. A last line without its newline is consumed
/// only once it parses (it may be half-written); a file that shrank was
/// rewritten and is parsed again from the start.
final class ClaudeTranscriptCache: @unchecked Sendable {
    private struct Entry {
        /// Bytes consumed so far, always at a line boundary.
        var offset: UInt64 = 0
        var transcript = ClaudeCodeActivitySource.Transcript(isComplete: false)
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// nil when the file is missing or holds nothing readable yet.
    func transcript(at url: URL) -> ClaudeCodeActivitySource.Transcript? {
        guard let handle = try? FileHandle(forReadingFrom: url),
            let size = try? handle.seekToEnd()
        else { return nil }
        defer { try? handle.close() }
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[url.path] ?? Entry()
        if size < entry.offset { entry = Entry() }
        if size > entry.offset, (try? handle.seek(toOffset: entry.offset)) != nil,
            let appended = try? handle.readToEnd()
        {
            let chunk = Self.readableLines(in: appended)
            if let text = String(data: chunk, encoding: .utf8) {
                entry.transcript = ClaudeCodeActivitySource.scanTranscript(
                    text, continuing: entry.transcript)
                entry.offset += UInt64(chunk.count)
            }
        }
        entries[url.path] = entry
        return entry.offset == 0 && size > 0 ? nil : entry.transcript
    }

    /// The newline-terminated lines of `data`, plus its unterminated tail
    /// when that is already a whole JSON object.
    private static func readableLines(in data: Data) -> Data {
        let newline = data.lastIndex(of: UInt8(ascii: "\n"))
        let tailStart = newline.map { data.index(after: $0) } ?? data.startIndex
        let tail = data[tailStart...]
        if !tail.isEmpty, (try? JSONSerialization.jsonObject(with: tail)) is [String: Any] {
            return data
        }
        return data[data.startIndex..<tailStart]
    }
}

// MARK: - pi

/// pi writes `~/.pi/agent/sessions/<slug>/<ts>_<id>.jsonl`; the last assistant
/// message carries `stopReason`, and `stop` means the turn is over.
public struct PiActivitySource: AgentActivitySource {
    public let agent = AgentKind.pi

    private let sessionsRoot: URL
    private let scans = PiScanCache()

    public init(sessionsRoot: URL) {
        self.sessionsRoot = sessionsRoot
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PiActivitySource {
        PiActivitySource(sessionsRoot: home.appendingPathComponent(".pi/agent/sessions"))
    }

    public func completedTasks() -> [AgentTask] {
        newestScans().filter(\.isComplete).map { scan in
            AgentTask(
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

    /// pi records no pid, so a session is open while a pi process works in its
    /// directory and it is still that directory's newest session.
    public func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? {
        guard
            let directories = processes.workingDirectories(
                ofProcessesNamed: Set(agent.processNames))
        else { return nil }
        return Set(
            newestScans()
                .filter { $0.cwd.map(directories.contains) ?? false }
                .map(\.sessionID))
    }

    /// Only the newest session per project can be the one just finished.
    private func newestScans() -> [SessionScan] {
        AgentFiles.directoryContents(sessionsRoot).compactMap { project in
            let newest = AgentFiles.directoryContents(project)
                .filter { $0.pathExtension == "jsonl" }
                .max { Self.modifiedAt($0) < Self.modifiedAt($1) }
            return newest.flatMap(scans.scan(at:))
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

/// pi session files run to megabytes and are polled every few seconds, so a
/// file is parsed again only when its modification date or size changes.
/// Entries are a few strings each; one is left behind per finished session.
final class PiScanCache: @unchecked Sendable {
    private struct Entry {
        let modified: Date
        let size: Int
        let scan: PiActivitySource.SessionScan?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func scan(at url: URL) -> PiActivitySource.SessionScan? {
        // Straight from the file system: `URL.resourceValues` caches per URL
        // instance and would hide a change.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let modified = attributes[.modificationDate] as? Date,
            let size = (attributes[.size] as? NSNumber)?.intValue
        else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[url.path], entry.modified == modified, entry.size == size {
            return entry.scan
        }
        let scan = (try? String(contentsOf: url, encoding: .utf8)).flatMap {
            PiActivitySource.scan(contents: $0, fileModified: modified)
        }
        entries[url.path] = Entry(modified: modified, size: size, scan: scan)
        return scan
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
