import XCTest

@testable import IslandCore

final class AgentTaskTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(AgentKind.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(AgentKind.pi.displayName, "pi")
        XCTAssertEqual(AgentKind.codex.displayName, "Codex")
    }

    func testIDCombinesAgentSessionAndCompletionTime() {
        let task = makeTask(
            agent: .pi, sessionID: "abc", completedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(task.id, "pi:abc:100000")
    }

    func testSessionKeyIgnoresCompletionTime() {
        let first = makeTask(
            agent: .pi, sessionID: "abc", completedAt: Date(timeIntervalSince1970: 1))
        let second = makeTask(
            agent: .pi, sessionID: "abc", completedAt: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(first.sessionKey, "pi:abc")
        XCTAssertEqual(first.sessionKey, second.sessionKey)
    }

    func testAnotherTurnOfTheSameSessionIsADifferentRun() {
        let first = makeTask(
            agent: .codex, sessionID: "abc", completedAt: Date(timeIntervalSince1970: 1))
        let second = makeTask(
            agent: .codex, sessionID: "abc", completedAt: Date(timeIntervalSince1970: 2))

        XCTAssertNotEqual(first.id, second.id)
    }

    func testFallbackTitleUsesTheDirectoryName() {
        XCTAssertEqual(AgentTask.fallbackTitle(cwd: "/Users/x/Repos/island"), "island")
    }

    func testFallbackTitleForMissingOrEmptyWorkingDirectory() {
        XCTAssertEqual(AgentTask.fallbackTitle(cwd: nil), "(untitled)")
        XCTAssertEqual(AgentTask.fallbackTitle(cwd: ""), "(untitled)")
        XCTAssertEqual(AgentTask.fallbackTitle(cwd: "/"), "(untitled)")
    }
}

final class AgentFilesTests: XCTestCase {
    func testMissingDirectoryYieldsNothing() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-missing-\(UUID().uuidString)")

        XCTAssertEqual(AgentFiles.directoryContents(missing), [])
    }

    func testExistingDirectoryIsListed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-listing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.jsonl")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            AgentFiles.directoryContents(directory).map(\.lastPathComponent), ["a.jsonl"])
    }
}

final class AgentTimestampTests: XCTestCase {
    func testParsesFractionalSeconds() {
        XCTAssertEqual(
            AgentTimestamp.date(from: "2026-09-24T20:32:48.241Z"),
            Date(timeIntervalSince1970: 1790281968.241)
        )
    }

    func testParsesWholeSeconds() {
        XCTAssertEqual(
            AgentTimestamp.date(from: "2026-09-24T20:32:48Z"),
            Date(timeIntervalSince1970: 1_790_281_968)
        )
    }

    func testRejectsGarbage() {
        XCTAssertNil(AgentTimestamp.date(from: "not a date"))
    }
}

final class AgentJSONTests: XCTestCase {
    func testObjectFromLine() {
        XCTAssertEqual(JSON.object(fromLine: #"{"a":1}"#)?["a"] as? Int, 1)
        XCTAssertNil(JSON.object(fromLine: "not json"))
        XCTAssertNil(JSON.object(fromLine: "[1,2]"))
    }

    func testFirstTextAcceptsAPlainString() {
        XCTAssertEqual(JSON.firstText(in: "hello"), "hello")
    }

    func testFirstTextAcceptsTypedBlocks() {
        let content: [[String: Any]] = [
            ["type": "thinking", "thinking": "hidden"],
            ["type": "text", "text": "visible"],
        ]

        XCTAssertEqual(JSON.firstText(in: content), "visible")
    }

    func testFirstTextIgnoresEmptyOrUnknownShapes() {
        XCTAssertNil(JSON.firstText(in: nil))
        XCTAssertNil(JSON.firstText(in: ""))
        XCTAssertNil(JSON.firstText(in: [["type": "thinking", "thinking": "x"]]))
        XCTAssertNil(JSON.firstText(in: 42))
    }

    func testTruncatedCollapsesWhitespaceAndEllipsizes() {
        XCTAssertEqual(JSON.truncated("  a\n b\tc "), "a b c")
        XCTAssertEqual(JSON.truncated(String(repeating: "x", count: 80)).count, 73)
        XCTAssertTrue(JSON.truncated(String(repeating: "x", count: 80)).hasSuffix("…"))
    }
}

final class ClaudeCodeActivitySourceTests: XCTestCase {
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    private typealias State = ClaudeCodeActivitySource.ClaudeSessionState
    private typealias Transcript = ClaudeCodeActivitySource.Transcript

    private let finished = Transcript(
        customTitle: nil, aiTitle: nil, lastPrompt: nil, isComplete: true,
        completedAt: Date(timeIntervalSince1970: 1_790_268_825))

    func testIdleSessionWithAFinishedTurnBecomesATask() throws {
        let state = State(
            pid: 42, sessionId: "sess-1", cwd: "/Users/x/Repos/island", name: "island-6d",
            status: "idle", updatedAt: 1_790_268_999_000, nameSource: "user")

        let task = try XCTUnwrap(ClaudeCodeActivitySource.task(from: state, transcript: finished))

        XCTAssertEqual(task.agent, .claudeCode)
        XCTAssertEqual(task.sessionID, "sess-1")
        XCTAssertEqual(task.title, "island-6d")
        XCTAssertEqual(task.host, .terminal(processID: 42))
        XCTAssertEqual(task.resumeCommand, "claude --resume sess-1")
        // The turn's own end, not the session file's last write.
        XCTAssertEqual(task.completedAt, Date(timeIntervalSince1970: 1_790_268_825))
    }

    func testBusySessionIsNotATask() {
        let state = State(
            pid: 1, sessionId: "s", cwd: nil, name: nil, status: "busy", updatedAt: nil)

        XCTAssertNil(ClaudeCodeActivitySource.task(from: state, transcript: finished))
    }

    func testSessionWithoutAnIDIsIgnored() {
        let state = State(
            pid: 1, sessionId: "", cwd: nil, name: nil, status: "idle", updatedAt: nil)

        XCTAssertNil(ClaudeCodeActivitySource.task(from: state, transcript: finished))
    }

    /// Issue dropdown-title-ux #3: a freshly opened session is idle but has not
    /// finished anything, and an interrupted turn is not a finished one either.
    func testIdleWithoutAFinishedTurnIsNotATask() {
        let state = State(
            pid: 1, sessionId: "s", cwd: nil, name: nil, status: "idle", updatedAt: 1)
        let unfinished = Transcript(
            customTitle: nil, aiTitle: nil, lastPrompt: "hi", isComplete: false, completedAt: nil)

        XCTAssertNil(ClaudeCodeActivitySource.task(from: state, transcript: nil))
        XCTAssertNil(ClaudeCodeActivitySource.task(from: state, transcript: unfinished))
    }

    func testMissingPIDAndTurnTimeFallBackToUnknownHostAndTheSessionTime() throws {
        let state = State(
            pid: nil, sessionId: "s", cwd: nil, name: nil, status: "idle", updatedAt: 5_000)
        let untimed = Transcript(
            customTitle: nil, aiTitle: nil, lastPrompt: nil, isComplete: true, completedAt: nil)

        let task = try XCTUnwrap(ClaudeCodeActivitySource.task(from: state, transcript: untimed))

        XCTAssertEqual(task.host, .unknown)
        XCTAssertEqual(task.completedAt, Date(timeIntervalSince1970: 5))
        XCTAssertEqual(task.title, "(untitled)")
    }

    func testMissingAnyTimeFallsBackToNow() throws {
        let before = Date()
        let state = State(
            pid: nil, sessionId: "s", cwd: nil, name: nil, status: "idle", updatedAt: nil)
        let untimed = Transcript(
            customTitle: nil, aiTitle: nil, lastPrompt: nil, isComplete: true, completedAt: nil)

        let task = try XCTUnwrap(ClaudeCodeActivitySource.task(from: state, transcript: untimed))

        XCTAssertGreaterThanOrEqual(task.completedAt, before)
    }

    /// Issue dropdown-title-ux #1: `/rename` > AI title > last user prompt >
    /// directory. Claude's auto-derived `<dir>-<hex>` name is not a title.
    func testTitlePrefersRenameThenAITitleThenTheLastPrompt() {
        func title(_ name: String?, _ source: String?, _ transcript: Transcript) -> String? {
            ClaudeCodeActivitySource.task(
                from: State(
                    pid: 1, sessionId: "s", cwd: "/Users/x/Repos/dotfiles", name: name,
                    status: "idle", updatedAt: nil, nameSource: source),
                transcript: transcript
            )?.title
        }
        func scan(custom: String? = nil, ai: String? = nil, prompt: String? = nil) -> Transcript {
            Transcript(
                customTitle: custom, aiTitle: ai, lastPrompt: prompt, isComplete: true,
                completedAt: nil)
        }

        XCTAssertEqual(
            title("dotfiles-9e", "derived", scan(custom: "renamed", ai: "ai", prompt: "p")),
            "renamed")
        XCTAssertEqual(title("my name", "user", scan(ai: "ai", prompt: "p")), "my name")
        XCTAssertEqual(title("dotfiles-9e", "derived", scan(ai: "ai", prompt: "p")), "ai")
        XCTAssertEqual(
            title("dotfiles-9e", "derived", scan(prompt: "fix the list")), "fix the list")
        XCTAssertEqual(title("dotfiles-9e", "derived", scan()), "dotfiles")
        XCTAssertEqual(title("  ", nil, scan()), "dotfiles")
        XCTAssertEqual(title("legacy", nil, scan(ai: "ai")), "legacy")
    }

    func testCompletedTasksReadsSessionsAndTheirTranscripts() throws {
        let home = try makeTempHome()
        let sessions = home.appendingPathComponent(".claude/sessions")
        let project = home.appendingPathComponent(".claude/projects/-tmp-x")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            #"{"pid":7,"sessionId":"done","cwd":"/tmp/x","name":"x-1a","nameSource":"derived","status":"idle","updatedAt":1790268825080}"#,
            to: sessions.appendingPathComponent("7.json"))
        try write(
            #"{"pid":8,"sessionId":"busy","cwd":"/tmp/x","status":"busy","updatedAt":1790268825080}"#,
            to: sessions.appendingPathComponent("8.json"))
        try write(
            #"{"pid":9,"sessionId":"fresh","cwd":"/tmp/x","status":"idle","updatedAt":1790268825080}"#,
            to: sessions.appendingPathComponent("9.json"))
        try write(
            #"{"pid":10,"sessionId":"stopped","cwd":"/tmp/x","status":"idle","updatedAt":1790268825080}"#,
            to: sessions.appendingPathComponent("10.json"))
        try write("garbage", to: sessions.appendingPathComponent("11.json"))
        try write("secret", to: sessions.appendingPathComponent("7.abc.key"))
        try write("not json", to: sessions.appendingPathComponent("notes.txt"))
        try write(
            """
            {"type":"user","message":{"role":"user","content":"tidy the dotfiles"}}
            {"type":"ai-title","aiTitle":"Tidy dotfiles"}
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}
            {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
            """, to: project.appendingPathComponent("done.jsonl"))
        try write(
            """
            {"type":"user","message":{"role":"user","content":"go"}}
            {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
            """, to: project.appendingPathComponent("stopped.jsonl"))

        let tasks = ClaudeCodeActivitySource.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.sessionID), ["done"])
        XCTAssertEqual(tasks.first?.title, "Tidy dotfiles")
        XCTAssertEqual(
            tasks.first?.completedAt, AgentTimestamp.date(from: "2026-09-25T19:00:00.000Z"))
    }

    func testTranscriptsAreRereadOnlyWhenTheyChange() throws {
        let home = try makeTempHome()
        let sessions = home.appendingPathComponent(".claude/sessions")
        let project = home.appendingPathComponent(".claude/projects/-tmp-x")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            #"{"pid":7,"sessionId":"s","cwd":"/tmp/x","status":"idle","updatedAt":1}"#,
            to: sessions.appendingPathComponent("7.json"))
        let transcript = project.appendingPathComponent("s.jsonl")
        let firstTurn = """
            {"type":"user","message":{"role":"user","content":"one"}}
            {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
            """
        try write(firstTurn, to: transcript)
        let source = ClaudeCodeActivitySource.standard(home: home)

        XCTAssertEqual(source.completedTasks().map(\.title), ["one"])
        XCTAssertEqual(source.completedTasks().map(\.title), ["one"])

        try write(
            firstTurn + """

                {"type":"user","message":{"role":"user","content":"two"}}
                {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:05:00.000Z"}
                """, to: transcript)

        XCTAssertEqual(source.completedTasks().map(\.title), ["two"])
    }

    func testCompletedTasksOnAMissingDirectory() throws {
        let home = try makeTempHome()

        XCTAssertTrue(ClaudeCodeActivitySource.standard(home: home).completedTasks().isEmpty)
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class PiActivitySourceTests: XCTestCase {
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    func testAFinalStopMarksTheTurnComplete() throws {
        let contents = """
            {"type":"session","id":"01a0","timestamp":"2026-09-24T20:32:48.241Z","cwd":"/Users/x/Repos/island"}
            {"type":"message","id":"m1","timestamp":"2026-09-24T20:33:00.000Z","message":{"role":"user","content":"build the thing"}}
            {"type":"message","id":"m2","timestamp":"2026-09-24T20:34:00.000Z","message":{"role":"assistant","stopReason":"toolUse","content":[{"type":"text","text":"working"}]}}
            {"type":"message","id":"m3","timestamp":"2026-09-24T20:35:00.000Z","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"done"}]}}
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertTrue(scan.isComplete)
        XCTAssertEqual(scan.sessionID, "01a0")
        XCTAssertEqual(scan.cwd, "/Users/x/Repos/island")
        XCTAssertNil(scan.title)
        XCTAssertEqual(scan.lastMessage, "build the thing")
        XCTAssertEqual(scan.completedAt, AgentTimestamp.date(from: "2026-09-24T20:35:00.000Z"))
    }

    func testAnAssistantStillUsingToolsIsNotComplete() throws {
        let contents = """
            {"type":"session","id":"s","timestamp":"2026-09-24T20:32:48.241Z","cwd":"/tmp"}
            {"type":"message","timestamp":"2026-09-24T20:35:00.000Z","message":{"role":"assistant","stopReason":"toolUse"}}
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertFalse(scan.isComplete)
    }

    func testScanIgnoresFilesWithoutASessionHeader() {
        XCTAssertNil(PiActivitySource.scan(contents: "not json\n", fileModified: Date()))
        XCTAssertNil(PiActivitySource.scan(contents: "", fileModified: Date()))
    }

    func testScanToleratesMessageShapesItCannotRead() throws {
        let contents = """
            {"type":"session","id":"s","timestamp":"2026-09-24T20:32:48.241Z"}
            {"type":"message","message":{"role":"user","content":[{"type":"thinking","thinking":"x"}]}}
            {"type":"message","message":{"role":"assistant","stopReason":"stop"}}
            {"type":"message","message":{"role":"system","content":"x"}}
            {"type":"message"}
            {"type":"other"}
            not json
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertNil(scan.title)
        XCTAssertEqual(scan.completedAt, AgentTimestamp.date(from: "2026-09-24T20:32:48.241Z"))
    }

    func testScanFallsBackToTheFileModificationDate() throws {
        let modified = Date(timeIntervalSince1970: 5)
        let contents = #"{"type":"session","id":"s"}"#

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: modified))

        XCTAssertEqual(scan.completedAt, modified)
    }

    func testCompletedTasksPicksTheNewestSessionOfEachProject() throws {
        let home = try makeTempHome()
        let project = home.appendingPathComponent(".pi/agent/sessions/--tmp-island--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)

        let older = project.appendingPathComponent("2026-09-01T00-00-00-000Z_old.jsonl")
        let newer = project.appendingPathComponent("2026-09-24T00-00-00-000Z_new.jsonl")
        try write(
            """
            {"type":"session","id":"old","cwd":"/tmp/island"}
            {"type":"message","timestamp":"2026-09-01T00:01:00.000Z","message":{"role":"assistant","stopReason":"stop"}}
            """, to: older)
        try write(
            """
            {"type":"session","id":"new","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"user","content":"finish mvp"}}
            {"type":"message","timestamp":"2026-09-24T00:01:00.000Z","message":{"role":"assistant","stopReason":"stop"}}
            """, to: newer)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newer.path)
        try write(
            #"{"type":"session","id":"ignored"}"#,
            to: project.appendingPathComponent("notes.txt"))

        let tasks = PiActivitySource.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.sessionID), ["new"])
        XCTAssertEqual(tasks.first?.resumeCommand, "pi --session new")
    }

    func testIncompleteNewestSessionProducesNothing() throws {
        let home = try makeTempHome()
        let project = home.appendingPathComponent(".pi/agent/sessions/--tmp-island--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            """
            {"type":"session","id":"running","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"assistant","stopReason":"toolUse"}}
            """, to: project.appendingPathComponent("run.jsonl"))

        XCTAssertTrue(PiActivitySource.standard(home: home).completedTasks().isEmpty)
    }

    func testCompletedTasksOnAMissingRoot() throws {
        let home = try makeTempHome()

        XCTAssertTrue(PiActivitySource.standard(home: home).completedTasks().isEmpty)
    }

    func testTitleFallsBackToTheLastUserMessage() throws {
        let home = try makeTempHome()
        let project = home.appendingPathComponent(".pi/agent/sessions/--tmp-island--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            """
            {"type":"session","id":"quiet","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"user","content":"first ask"}}
            {"type":"message","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"answer"}]}}
            {"type":"message","message":{"role":"user","content":"follow-up ask"}}
            {"type":"message","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"all done here"}]}}
            """, to: project.appendingPathComponent("run.jsonl"))

        let tasks = PiActivitySource.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.title), ["follow-up ask"])
    }

    /// pi's `/name` writes a `session_info` entry; the latest one is the title.
    func testSessionNameIsTheTitle() throws {
        let contents = """
            {"type":"session","id":"s","cwd":"/tmp/island"}
            {"type":"session_info","name":"old name"}
            {"type":"message","message":{"role":"user","content":"do it"}}
            {"type":"session_info","name":"vs-space"}
            {"type":"session_info"}
            {"type":"message","message":{"role":"assistant","stopReason":"stop"}}
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertEqual(scan.title, "vs-space")
        XCTAssertEqual(scan.lastMessage, "do it")
    }

    func testAnAbortedTurnIsNotComplete() throws {
        let contents = """
            {"type":"session","id":"s","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"user","content":"go"}}
            {"type":"message","message":{"role":"assistant","stopReason":"aborted"}}
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertFalse(scan.isComplete)
    }

    func testTitleFallsBackToTheWorkingDirectoryWhenThereIsNoMessageAtAll() throws {
        let home = try makeTempHome()
        let project = home.appendingPathComponent(".pi/agent/sessions/--tmp-island--")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try write(
            """
            {"type":"session","id":"quiet","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"assistant","stopReason":"stop"}}
            """, to: project.appendingPathComponent("run.jsonl"))

        let tasks = PiActivitySource.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.title), ["island"])
    }

    func testScanCapturesTheLastUserText() throws {
        let contents = """
            {"type":"session","id":"s","cwd":"/tmp/island"}
            {"type":"message","message":{"role":"user","content":"one"}}
            {"type":"message","message":{"role":"user","content":[{"type":"text","text":"two"}]}}
            {"type":"message","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"all done"}]}}
            """

        let scan = try XCTUnwrap(
            PiActivitySource.scan(contents: contents, fileModified: .distantPast))

        XCTAssertNil(scan.title)
        XCTAssertEqual(scan.lastMessage, "two")
        XCTAssertTrue(scan.isComplete)
    }

    func testModifiedAtFallsBackForAnUnreadableFile() {
        let missing = URL(fileURLWithPath: "/nonexistent/island/nope.jsonl")

        XCTAssertEqual(PiActivitySource.modifiedAt(missing), .distantPast)
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-pi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }

    private func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class CodexActivitySourceTests: XCTestCase {
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    func testParsesTheThreadIndex() throws {
        let index = """
            {"id":"01a","thread_name":"评估 AI 玩游戏","updated_at":"2026-09-11T21:32:17.104859Z"}
            {"id":"01b","thread_name":"","updated_at":"2026-09-11T21:33:07.772Z"}
            {"id":"01c","updated_at":"2026-09-11T21:33:07.772Z"}
            broken json
            {"thread_name":"no id","updated_at":"2026-09-11T21:33:07.772Z"}
            {"id":"01d","thread_name":"no time"}
            """

        let tasks = CodexIndexActivitySource.parseIndex(index)

        XCTAssertEqual(tasks.map(\.sessionID), ["01a", "01b", "01c"])
        XCTAssertEqual(tasks.first?.title, "评估 AI 玩游戏")
        XCTAssertEqual(tasks.first?.host, .desktop(bundleID: "com.openai.codex"))
        XCTAssertEqual(tasks.first?.resumeCommand, "codex resume 01a")
        XCTAssertEqual(tasks.first?.deepLink, "codex://threads/01a")
        XCTAssertEqual(tasks.last?.title, "(untitled)")
    }

    func testCompletedTasksReadsTheIndexFile() throws {
        let home = try makeTempHome()
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"id":"x","thread_name":"task","updated_at":"2026-09-11T21:32:17.104859Z"}"#
            .write(
                to: directory.appendingPathComponent("session_index.jsonl"), atomically: true,
                encoding: .utf8)

        let tasks = CodexIndexActivitySource.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.sessionID), ["x"])
    }

    func testCompletedTasksWithoutAnIndexFile() throws {
        let home = try makeTempHome()

        XCTAssertTrue(CodexIndexActivitySource.standard(home: home).completedTasks().isEmpty)
    }

    // MARK: - Turn history (SQLite)

    func testParsesTurnHistoryRows() throws {
        let json = """
            [
              {"id":"01a","name":"评估 AI 玩游戏","title":"你有办法玩游戏吗","cwd":"/Users/x/Repos/compounding","completed_at":1789162387},
              {"id":"01b","name":null,"title":"raw first message","cwd":"/tmp","completed_at":1789162388},
              {"id":"01c","name":"","title":"","cwd":null,"completed_at":1789162389,"last_prompt":"user asked this last"},
              {"id":"01d","name":"","title":"","cwd":null,"completed_at":1789162390},
              {"id":"01e","name":"no time","cwd":"/tmp"},
              {"name":"no id","completed_at":1},
              "not an object"
            ]
            """

        let tasks = CodexTurnActivitySource.parse(json)

        XCTAssertEqual(tasks.map(\.sessionID), ["01a", "01b", "01c", "01d"])
        XCTAssertEqual(
            tasks.map(\.title),
            ["评估 AI 玩游戏", "raw first message", "user asked this last", "(untitled)"])
        XCTAssertEqual(tasks.first?.cwd, "/Users/x/Repos/compounding")
        XCTAssertEqual(tasks.first?.resumeCommand, "codex resume 01a")
        XCTAssertEqual(tasks.first?.deepLink, "codex://threads/01a")
        XCTAssertEqual(
            tasks.first?.completedAt, Date(timeIntervalSince1970: 1_789_162_387))
    }

    /// Issue dropdown-title-ux #1: without a name, the last thing the user
    /// asked beats the thread's first message.
    func testTheLastPromptBeatsTheFirstMessage() {
        let tasks = CodexTurnActivitySource.parse(
            #"[{"id":"t","name":null,"title":"first ask","last_prompt":"latest ask","completed_at":1}]"#
        )

        XCTAssertEqual(tasks.map(\.title), ["latest ask"])
        XCTAssertTrue(
            CodexTurnActivitySource.sql(history: URL(fileURLWithPath: "/h")).contains(
                "'userMessage'"))
    }

    func testTurnHistoryRejectsGarbage() {
        XCTAssertTrue(CodexTurnActivitySource.parse("").isEmpty)
        XCTAssertTrue(CodexTurnActivitySource.parse("not json").isEmpty)
        XCTAssertTrue(CodexTurnActivitySource.parse(#"{"a":1}"#).isEmpty)
    }

    func testTurnSourceAsksTheRunnerForJoinedRows() {
        let runner = StubSQLite(rows: #"[{"id":"t","name":"n","cwd":"/tmp","completed_at":5}]"#)
        let source = CodexTurnActivitySource(
            threadsDatabase: URL(fileURLWithPath: "/tmp/threads.sqlite"),
            historyDatabase: URL(fileURLWithPath: "/tmp/history.sqlite"),
            runner: runner
        )

        XCTAssertEqual(source.completedTasks().map(\.sessionID), ["t"])
        XCTAssertTrue(runner.lastSQL?.contains("attach database") == true)
        XCTAssertTrue(runner.lastSQL?.contains("'/tmp/history.sqlite'") == true)
    }

    func testTurnSourceIsEmptyWhenTheRunnerCannotRead() {
        let source = CodexTurnActivitySource(
            threadsDatabase: URL(fileURLWithPath: "/tmp/threads.sqlite"),
            historyDatabase: URL(fileURLWithPath: "/tmp/history.sqlite"),
            runner: StubSQLite(rows: nil)
        )

        XCTAssertTrue(source.completedTasks().isEmpty)
    }

    func testTurnsWinOverTheIndex() throws {
        let home = try makeTempHome()
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"id":"from-index","thread_name":"i","updated_at":"2026-09-11T21:32:17Z"}"#
            .write(
                to: directory.appendingPathComponent("session_index.jsonl"), atomically: true,
                encoding: .utf8)
        let source = CodexActivitySource.standard(
            home: home,
            sqlite: StubSQLite(
                rows: #"[{"id":"from-turns","name":"t","cwd":"/tmp","completed_at":5}]"#)
        )

        XCTAssertEqual(source.completedTasks().map(\.sessionID), ["from-turns"])
    }

    func testIndexIsUsedWhenThereAreNoTurns() throws {
        let home = try makeTempHome()
        let directory = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"id":"from-index","thread_name":"i","updated_at":"2026-09-11T21:32:17Z"}"#
            .write(
                to: directory.appendingPathComponent("session_index.jsonl"), atomically: true,
                encoding: .utf8)

        let source = CodexActivitySource.standard(home: home, sqlite: StubSQLite(rows: "[]"))

        XCTAssertEqual(source.completedTasks().map(\.sessionID), ["from-index"])
    }

    private func makeTempHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }
}

final class AgentActivityScannerTests: XCTestCase {
    func testMergesSourcesNewestFirst() {
        let scanner = AgentActivityScanner(sources: [
            StubSource(
                agent: .pi,
                tasks: [
                    makeTask(
                        agent: .pi, sessionID: "old", completedAt: Date(timeIntervalSince1970: 1))
                ]),
            StubSource(
                agent: .codex,
                tasks: [
                    makeTask(
                        agent: .codex, sessionID: "new", completedAt: Date(timeIntervalSince1970: 9)
                    )
                ]),
        ])

        XCTAssertEqual(scanner.completedTasks().map(\.sessionID), ["new", "old"])
    }

    func testStandardSourcesPointAtTheGivenHome() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-standard-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(AgentActivityScanner.standard(home: home).completedTasks(), [])
    }
}

private struct StubSQLite: SQLiteQuerying {
    let rows: String?
    // `nonisolated(unsafe)` would be needed for a class; a fresh value per test
    // keeps this a plain box.
    final class Box: @unchecked Sendable { var sql: String? }
    let box = Box()

    var lastSQL: String? { box.sql }

    func query(database: URL, sql: String) -> String? {
        box.sql = sql
        return rows
    }
}

private struct StubSource: AgentActivitySource {
    let agent: AgentKind
    let tasks: [AgentTask]

    func completedTasks() -> [AgentTask] { tasks }
}

private func makeTask(
    agent: AgentKind,
    sessionID: String,
    completedAt: Date
) -> AgentTask {
    AgentTask(
        agent: agent,
        sessionID: sessionID,
        title: sessionID,
        cwd: nil,
        completedAt: completedAt,
        host: .unknown,
        resumeCommand: nil
    )
}

final class TaskTitleTests: XCTestCase {
    func testPrefersTheAgentsOwnTitle() {
        XCTAssertEqual(
            TaskTitle.resolve(title: "island-6d", lastMessage: "done", cwd: "/tmp/x"), "island-6d")
    }

    func testFallsBackToTheLastMessage() {
        XCTAssertEqual(
            TaskTitle.resolve(title: "   ", lastMessage: "finished the task", cwd: "/tmp/x"),
            "finished the task"
        )
        XCTAssertEqual(TaskTitle.resolve(title: nil, lastMessage: "done", cwd: nil), "done")
    }

    func testFallsBackToTheDirectory() {
        XCTAssertEqual(
            TaskTitle.resolve(title: nil, lastMessage: "", cwd: "/Users/x/Repos/island"), "island")
        XCTAssertEqual(TaskTitle.resolve(title: nil, lastMessage: nil, cwd: nil), "(untitled)")
    }

    func testCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(TaskTitle.resolve(title: "a\n  b", lastMessage: nil, cwd: nil), "a b")
        XCTAssertEqual(
            TaskTitle.resolve(title: String(repeating: "x", count: 80), lastMessage: nil, cwd: nil)
                .count,
            73
        )
    }
}

final class ClaudeTranscriptTests: XCTestCase {
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    private func scan(_ contents: String) -> ClaudeCodeActivitySource.Transcript {
        ClaudeCodeActivitySource.scanTranscript(contents)
    }

    func testATurnEndingInTurnDurationIsComplete() {
        let transcript = scan(
            """
            {"type":"user","message":{"role":"user","content":"build it"}}
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
            {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
            """)

        XCTAssertTrue(transcript.isComplete)
        XCTAssertEqual(
            transcript.completedAt, AgentTimestamp.date(from: "2026-09-25T19:00:00.000Z"))
        XCTAssertEqual(transcript.lastPrompt, "build it")
    }

    func testAFreshSessionHasNothingComplete() {
        let transcript = scan(
            """
            {"type":"attachment","attachment":{"type":"hook_success"}}
            {"type":"system","subtype":"informational","content":"hello"}
            """)

        XCTAssertFalse(transcript.isComplete)
        XCTAssertNil(transcript.completedAt)
        XCTAssertNil(transcript.lastPrompt)
        XCTAssertFalse(scan("").isComplete)
    }

    func testAnEscapedTurnIsNotComplete() {
        XCTAssertFalse(
            scan(
                """
                {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T18:00:00.000Z"}
                {"type":"user","message":{"role":"user","content":"go"}}
                {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
                """
            ).isComplete)
        // Interrupting a tool call still writes a turn_duration.
        XCTAssertFalse(
            scan(
                """
                {"type":"user","message":{"role":"user","content":"go"}}
                {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}
                {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
                """
            ).isComplete)
    }

    func testATurnStillRunningIsNotComplete() {
        let transcript = scan(
            """
            {"type":"user","message":{"role":"user","content":"one"}}
            {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
            {"type":"user","message":{"role":"user","content":"two"}}
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}
            """)

        XCTAssertFalse(transcript.isComplete)
        XCTAssertEqual(transcript.lastPrompt, "two")
    }

    func testATurnAfterAnInterruptedOneCanComplete() {
        let transcript = scan(
            """
            {"type":"user","message":{"role":"user","content":"one"}}
            {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
            {"type":"user","message":{"role":"user","content":"two"}}
            {"type":"system","subtype":"turn_duration","timestamp":"2026-09-25T19:00:00.000Z"}
            """)

        XCTAssertTrue(transcript.isComplete)
        XCTAssertEqual(transcript.lastPrompt, "two")
    }

    func testAnUntimedTurnDurationStillCompletesTheTurn() {
        let transcript = scan(
            """
            {"type":"user","message":{"role":"user","content":"one"}}
            {"type":"system","subtype":"turn_duration"}
            """)

        XCTAssertTrue(transcript.isComplete)
        XCTAssertNil(transcript.completedAt)
    }

    func testTitlesTakeTheLatestValue() {
        let transcript = scan(
            """
            {"type":"ai-title","aiTitle":"first ai"}
            {"type":"custom-title","customTitle":"first rename"}
            {"type":"ai-title","aiTitle":"second ai"}
            {"type":"custom-title","customTitle":"second rename"}
            {"type":"ai-title"}
            {"type":"custom-title"}
            """)

        XCTAssertEqual(transcript.aiTitle, "second ai")
        XCTAssertEqual(transcript.customTitle, "second rename")
    }

    /// The last prompt is what the user typed: slash-command wrappers, injected
    /// meta messages, tool results, interrupts and side chains do not count.
    func testLastPromptSkipsWhatTheUserDidNotType() {
        let transcript = scan(
            """
            {"type":"user","message":{"role":"user","content":[{"type":"image"},{"type":"text","text":"typed this"}]}}
            {"type":"user","message":{"role":"user","content":"<command-name>/rename</command-name>"}}
            {"type":"user","message":{"role":"user","content":"<local-command-stdout>ok</local-command-stdout>"}}
            {"type":"user","isMeta":true,"message":{"role":"user","content":[{"type":"text","text":"skill body"}]}}
            {"type":"user","isSidechain":true,"message":{"role":"user","content":"subagent prompt"}}
            {"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"x"}]}}
            {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}
            {"type":"user"}
            not json
            """)

        XCTAssertEqual(transcript.lastPrompt, "typed this")
    }

    func testSessionFileIsFoundBySessionID() throws {
        let projects = try makeTempDirectory().appendingPathComponent("projects")
        let project = projects.appendingPathComponent("-tmp-island")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "x".write(
            to: project.appendingPathComponent("sess.jsonl"), atomically: true, encoding: .utf8)
        try "y".write(
            to: project.appendingPathComponent("other.jsonl"), atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ClaudeCodeActivitySource.sessionFile(sessionID: "sess", in: projects)?
                .lastPathComponent,
            "sess.jsonl"
        )
        XCTAssertNil(ClaudeCodeActivitySource.sessionFile(sessionID: "missing", in: projects))
        XCTAssertNil(ClaudeCodeActivitySource.sessionFile(sessionID: "sess", in: project))
    }

    func testTranscriptCacheReadsAFileAndToleratesAMissingOne() throws {
        let directory = try makeTempDirectory()
        let file = directory.appendingPathComponent("sess.jsonl")
        try #"{"type":"ai-title","aiTitle":"from disk"}"#
            .write(to: file, atomically: true, encoding: .utf8)
        let cache = ClaudeTranscriptCache()

        XCTAssertEqual(cache.transcript(at: file)?.aiTitle, "from disk")
        XCTAssertNil(cache.transcript(at: directory.appendingPathComponent("missing.jsonl")))
        let binary = directory.appendingPathComponent("binary.jsonl")
        try Data([0xFF, 0xFE, 0xFD]).write(to: binary)
        XCTAssertNil(cache.transcript(at: binary))
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }
}
