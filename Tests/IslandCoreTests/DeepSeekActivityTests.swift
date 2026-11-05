import XCTest

@testable import IslandCore

final class DeepSeekActivityTests: XCTestCase {
    private var temporary: [URL] = []

    override func tearDown() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []
    }

    func testAgentKind() {
        XCTAssertEqual(AgentKind.deepseek.rawValue, "deepseek")
        XCTAssertEqual(AgentKind.deepseek.displayName, "DeepSeek")
        XCTAssertEqual(AgentKind.deepseek.profile.appBundleIDs, ["com.deepseek.dsh"])
        XCTAssertEqual(AgentKind.deepseek.profile.scenarios, [.deepseekApp])
    }

    /// Issue deepseek-harness-source: a session whose last turn closed is a
    /// finished run, timed by its last message, and brings the app forward.
    func testAClosedTurnBecomesATask() throws {
        let task = try XCTUnwrap(
            DeepSeekActivitySource.task(
                sessionID: "session-abc",
                from: cache(title: "执行计划任务", lastMessageAt: 1_792_278_028_606)))

        XCTAssertEqual(task.agent, .deepseek)
        XCTAssertEqual(task.sessionID, "session-abc")
        XCTAssertEqual(task.title, "执行计划任务")
        XCTAssertEqual(task.cwd, "/Users/me/Repos/doc-triage")
        XCTAssertEqual(task.completedAt, Date(timeIntervalSince1970: 1_792_278_028.606))
        XCTAssertEqual(task.host, .desktop(bundleID: "com.deepseek.dsh"))
        XCTAssertNil(task.resumeCommand)
        XCTAssertEqual(task.deepLink, "dsh://open")
        XCTAssertEqual(task.scenario, AgentScenario.deepseekApp.id)
    }

    /// The title is generated after the first turn; until then the first
    /// prompt stands in, and with no prompt the directory does.
    func testAnUntitledSessionFallsBackToItsFirstPromptThenItsDirectory() throws {
        XCTAssertEqual(
            DeepSeekActivitySource.task(
                sessionID: "s", from: cache(title: nil, firstPrompt: "  read AGENTS.md  "))?
                .title,
            "read AGENTS.md")
        XCTAssertEqual(
            DeepSeekActivitySource.task(sessionID: "s", from: cache(title: nil))?.title,
            "doc-triage")
    }

    /// A turn still running (an open turn, or a step that started but has not
    /// ended) and a session that never ran a turn are not finished runs.
    func testOpenAndEmptySessionsAreSkipped() {
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: cache(openTurn: 4)))
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: cache(lastStep: "start")))
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: cache(lastTurn: 0)))
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: cache(lastMessageAt: nil)))
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: Data("{".utf8)))
        XCTAssertNil(DeepSeekActivitySource.task(sessionID: "s", from: Data("{}".utf8)))
    }

    /// The working directory row wins over the one the session was created in.
    func testTheCurrentWorkingDirectoryWins() {
        XCTAssertEqual(
            DeepSeekActivitySource.task(
                sessionID: "s", from: cache(workingDirectory: "/Users/me/elsewhere"))?.cwd,
            "/Users/me/elsewhere")
    }

    /// Every `session-<id>.json` in the cache directory is read; other files
    /// and a missing directory yield nothing.
    func testReadsEverySessionFileInTheCacheDirectory() throws {
        let root = try directory()
        try cache(title: "one", lastMessageAt: 2_000)
            .write(to: root.appendingPathComponent("session-1.json"))
        try cache(title: "two", lastMessageAt: 1_000)
            .write(to: root.appendingPathComponent("session-2.json"))
        try cache(openTurn: 1).write(to: root.appendingPathComponent("session-3.json"))
        try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let tasks = DeepSeekActivitySource(cacheDirectory: root).completedTasks()

        XCTAssertEqual(tasks.map(\.sessionID).sorted(), ["session-1", "session-2"])
        XCTAssertEqual(
            DeepSeekActivitySource(cacheDirectory: root.appendingPathComponent("missing"))
                .completedTasks(), [])
        XCTAssertEqual(DeepSeekActivitySource.standard(home: root).completedTasks(), [])
    }

    func testTheScannerReadsDeepSeek() throws {
        let home = try directory()
        let sessions = home.appendingPathComponent(".dsh/storages/session_projcache/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try cache(title: "ds").write(to: sessions.appendingPathComponent("session-9.json"))

        let tasks = AgentActivityScanner.standard(home: home).completedTasks()

        XCTAssertEqual(tasks.map(\.agent), [.deepseek])
    }

    // MARK: - Fixtures

    /// The shape of `~/.dsh/storages/session_projcache/sessions/<id>.json`
    /// (DeepSeek Harness 0.2.1), trimmed to the rows island reads.
    private func cache(
        title: String? = "t",
        firstPrompt: String? = nil,
        openTurn: Int? = nil,
        lastStep: String? = "end",
        lastTurn: Int = 1,
        lastMessageAt: Int? = 1_000,
        workingDirectory: String? = nil
    ) -> Data {
        func row(_ value: Any?) -> [String: Any] {
            ["ver": 1, "seq": 9, "val": value ?? NSNull()]
        }
        var rows: [String: Any] = [
            "title": row(title),
            "turnBoundary": row([
                "openTurnStartSeq": openTurn.map { $0 as Any } ?? NSNull(),
                "lastStepStartSeq": 5,
                "lastStepBoundary": lastStep.map { ["kind": $0, "seq": 8] as Any } ?? NSNull(),
                "lastTurn": lastTurn,
            ]),
            "timeContext": row([
                "lastMessageTime": lastMessageAt.map { $0 as Any } ?? NSNull(),
                "lastInjectionTime": NSNull(),
            ]),
            "titleInput": row(
                firstPrompt.map { ["first": ["seq": 3, "text": $0], "count": 1] as [String: Any] }
                    ?? [
                        "first": NSNull(), "count": 0,
                    ]),
        ]
        if let workingDirectory { rows["workingDirectory"] = row(workingDirectory) }
        let root: [String: Any] = [
            "version": 7,
            "record": [
                "identity": ["formatVersion": 4, "cwd": "/Users/me/Repos/doc-triage"],
                "rows": rows,
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-deepseek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporary.append(url)
        return url
    }
}
