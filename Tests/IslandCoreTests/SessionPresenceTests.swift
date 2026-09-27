import XCTest

@testable import IslandCore

final class SessionPresenceTests: XCTestCase {
    func testASessionMissingFromItsAgentsLiveSetIsGone() {
        let presence = SessionPresence(live: [.claudeCode: ["open"]])

        XCTAssertFalse(presence.isGone(task(.claudeCode, "open")))
        XCTAssertTrue(presence.isGone(task(.claudeCode, "closed")))
    }

    /// An agent that cannot tell keeps every row: removing a live session is
    /// worse than keeping a dead one.
    func testAnAgentWithoutALiveSetKeepsEverything() {
        let presence = SessionPresence(live: [.claudeCode: []])

        XCTAssertFalse(presence.isGone(task(.claudeDesktop, "chat")))
        XCTAssertFalse(SessionPresence(live: [:]).isGone(task(.pi, "p")))
    }

    func testTheDefaultInspectorAssumesEverythingRunsAndKnowsNoDirectories() {
        let inspector = NoProcessInspecting()

        XCTAssertTrue(inspector.isRunning(42))
        XCTAssertNil(inspector.workingDirectories(ofProcessesNamed: ["pi"]))
    }

    func testScannerCollectsLiveSetsOnlyForTheAskedAgents() {
        let asked = LiveStub(agent: .claudeCode, live: ["a"])
        let skipped = LiveStub(agent: .codex, live: ["c"])
        let scanner = AgentActivityScanner(sources: [asked, skipped])

        let presence = scanner.presence(of: [.claudeCode], processes: NoProcessInspecting())

        XCTAssertEqual(presence, SessionPresence(live: [.claudeCode: ["a"]]))
        XCTAssertEqual(asked.calls.count, 1)
        XCTAssertEqual(skipped.calls.count, 0)
    }

    func testOneSourceThatCannotTellMakesItsWholeAgentUnknown() {
        let scanner = AgentActivityScanner(sources: [
            LiveStub(agent: .codex, live: ["a"]),
            LiveStub(agent: .codex, live: nil),
            LiveStub(agent: .pi, live: ["p"]),
            LiveStub(agent: .pi, live: ["q"]),
        ])

        let presence = scanner.presence(of: [.codex, .pi], processes: NoProcessInspecting())

        XCTAssertEqual(presence, SessionPresence(live: [.pi: ["p", "q"]]))
    }

    /// Claude Desktop keeps chats on the server; its local cache cannot say
    /// whether one was deleted.
    func testSourcesCannotTellByDefault() {
        let source = ClaudeDesktopActivitySource(blobRoot: URL(fileURLWithPath: "/nonexistent"))

        XCTAssertNil(source.liveSessionIDs(processes: NoProcessInspecting()))
    }

    private func task(_ agent: AgentKind, _ sessionID: String) -> AgentTask {
        AgentTask(
            agent: agent, sessionID: sessionID, title: sessionID, cwd: nil,
            completedAt: Date(timeIntervalSince1970: 1), host: .unknown, resumeCommand: nil)
    }
}

/// Answers from fixed tables, recording what it was asked.
struct StubProcesses: ProcessInspecting {
    var running: Set<Int32> = []
    var directories: Set<String>? = nil

    func isRunning(_ pid: Int32) -> Bool { running.contains(pid) }

    func workingDirectories(ofProcessesNamed names: Set<String>) -> Set<String>? {
        directories
    }
}

private final class LiveStub: AgentActivitySource, @unchecked Sendable {
    let agent: AgentKind
    let live: Set<String>?
    var calls: [Int] = []

    init(agent: AgentKind, live: Set<String>?) {
        self.agent = agent
        self.live = live
    }

    func completedTasks() -> [AgentTask] { [] }

    func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? {
        calls.append(1)
        return live
    }
}
