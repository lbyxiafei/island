import XCTest

@testable import IslandCore

final class AgentProfileTests: XCTestCase {
    func testEveryAgentHasAProfileInDisplayOrder() {
        XCTAssertEqual(AgentProfile.all.map(\.agent), AgentKind.allCases)
        for agent in AgentKind.allCases {
            XCTAssertEqual(agent.profile.agent, agent)
        }
    }

    func testEveryAgentDeclaresAtLeastOneScenarioItOwns() {
        for profile in AgentProfile.all {
            XCTAssertFalse(profile.scenarios.isEmpty, "\(profile.agent)")
            XCTAssertEqual(profile.primaryScenario, profile.scenarios.first)
            for scenario in profile.scenarios {
                XCTAssertEqual(scenario.agent, profile.agent)
                XCTAssertTrue(scenario.id.hasPrefix(profile.agent.rawValue + "."), scenario.id)
                XCTAssertFalse(scenario.title.isEmpty)
                XCTAssertFalse(scenario.detection.isEmpty)
                XCTAssertFalse(scenario.jumpBack.isEmpty)
            }
        }
    }

    /// Scenario ids are persisted in settings, so they must never collide.
    func testScenarioIDsAreUniqueAndResolvable() {
        let ids = AgentProfile.all.flatMap(\.scenarios).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertEqual(AgentScenario.named(id)?.id, id)
        }
        XCTAssertNil(AgentScenario.named("nope.nothing"))
    }

    func testProfilesCarryWhatUsedToBeSpreadOverSwitches() {
        XCTAssertEqual(AgentKind.claudeDesktop.displayName, "Claude")
        XCTAssertEqual(AgentKind.claudeCode.processNames, ["claude"])
        XCTAssertEqual(AgentKind.pi.processNames, ["pi"])
        XCTAssertEqual(AgentKind.codex.profile.appBundleIDs, ["com.openai.codex"])
        XCTAssertEqual(AgentKind.claudeCode.profile.symbolName, "sparkle")
    }

    func testATaskDefaultsToItsAgentsPrimaryScenario() {
        let plain = AgentTask(
            agent: .pi, sessionID: "s", title: "t", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 1), host: .unknown, resumeCommand: nil)
        XCTAssertEqual(plain.scenario, AgentScenario.piTerminal.id)

        let tagged = AgentTask(
            agent: .codex, sessionID: "s", title: "t", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 1), host: .unknown, resumeCommand: nil,
            scenario: AgentScenario.codexExec.id)
        XCTAssertEqual(tagged.scenario, AgentScenario.codexExec.id)
        XCTAssertEqual(tagged.withHost(.terminal(processID: 3)).scenario, tagged.scenario)
    }
}

final class AgentScenarioClassificationTests: XCTestCase {
    func testClaudeCodeEntryPoints() {
        let scenario = ClaudeCodeActivitySource.scenario(entrypoint:)
        XCTAssertEqual(scenario(nil), .claudeCodeTerminal)
        XCTAssertEqual(scenario("cli"), .claudeCodeTerminal)
        XCTAssertEqual(scenario("claude-vscode"), .claudeCodeEditor)
        XCTAssertEqual(scenario("claude-jetbrains"), .claudeCodeEditor)
        XCTAssertEqual(scenario("claude-desktop"), .claudeCodeDesktop)
        XCTAssertEqual(scenario("sdk-ts"), .claudeCodeHeadless)
        XCTAssertEqual(scenario("something-new"), .claudeCodeHeadless)
    }

    func testClaudeCodeTasksAreTaggedFromTheSessionFile() throws {
        let transcript = ClaudeCodeActivitySource.Transcript(
            customTitle: "t", aiTitle: nil, lastPrompt: nil, isComplete: true,
            completedAt: Date(timeIntervalSince1970: 5))
        var state = ClaudeCodeActivitySource.ClaudeSessionState(
            pid: 1, sessionId: "s", cwd: nil, name: nil, status: "idle", updatedAt: nil)
        state.entrypoint = "claude-desktop"

        let task = try XCTUnwrap(
            ClaudeCodeActivitySource.task(from: state, transcript: transcript))

        XCTAssertEqual(task.scenario, AgentScenario.claudeCodeDesktop.id)
    }

    func testClaudeCodeSessionFileEntryPointIsDecoded() throws {
        let data = Data(
            #"{"pid":1,"sessionId":"s","status":"idle","entrypoint":"cli"}"#.utf8)
        let state = try JSONDecoder().decode(
            ClaudeCodeActivitySource.ClaudeSessionState.self, from: data)
        XCTAssertEqual(state.entrypoint, "cli")
    }

    func testCodexThreadSources() {
        let scenario = CodexTurnActivitySource.scenario(source:)
        XCTAssertEqual(scenario("cli"), .codexCLI)
        XCTAssertEqual(scenario("exec"), .codexExec)
        XCTAssertEqual(scenario("vscode"), .codexApp)
        XCTAssertEqual(scenario(nil), .codexApp)
    }

    func testCodexTurnRowsAreTaggedBySource() {
        let tasks = CodexTurnActivitySource.parse(
            #"[{"id":"a","source":"cli","completed_at":2},{"id":"b","completed_at":1}]"#)

        XCTAssertEqual(
            tasks.map(\.scenario), [AgentScenario.codexCLI.id, AgentScenario.codexApp.id])
        XCTAssertTrue(
            CodexTurnActivitySource.sql(history: URL(fileURLWithPath: "/h")).contains(
                "threads.source as source"))
    }

    func testCodexIndexRowsCountAsTheApp() {
        let tasks = CodexIndexActivitySource.parseIndex(
            #"{"id":"x","thread_name":"i","updated_at":"2026-09-11T21:32:17Z"}"#)
        XCTAssertEqual(tasks.map(\.scenario), [AgentScenario.codexApp.id])
    }

    func testSingleScenarioAgents() {
        let pi = PiActivitySource.scan(
            contents: #"{"type":"session","id":"p","cwd":"/tmp"}"#,
            fileModified: Date(timeIntervalSince1970: 1))
        XCTAssertNotNil(pi)
        XCTAssertEqual(AgentKind.pi.profile.scenarios, [.piTerminal])
        XCTAssertEqual(AgentKind.claudeDesktop.profile.scenarios, [.claudeDesktopChat])
    }
}

final class AgentScenarioSettingsTests: XCTestCase {
    func testEverythingIsOnByDefault() {
        let settings = AgentScenarioSettings()
        for scenario in AgentProfile.all.flatMap(\.scenarios) {
            XCTAssertTrue(settings.isEnabled(scenario.id))
        }
        XCTAssertEqual(settings.state(of: .codex), .on)
        XCTAssertEqual(settings.enabledAgents, Set(AgentKind.allCases))
    }

    func testSwitchingOneScenarioLeavesItsAgentMixed() {
        var settings = AgentScenarioSettings()
        settings.setEnabled(AgentScenario.codexExec.id, false)

        XCTAssertFalse(settings.isEnabled(AgentScenario.codexExec.id))
        XCTAssertTrue(settings.isEnabled(AgentScenario.codexCLI.id))
        XCTAssertEqual(settings.state(of: .codex), .mixed)
        XCTAssertEqual(settings.state(of: .pi), .on)

        settings.setEnabled(AgentScenario.codexExec.id, true)
        XCTAssertEqual(settings.state(of: .codex), .on)
    }

    func testSwitchingAnAgentSwitchesAllItsScenarios() {
        var settings = AgentScenarioSettings()
        settings.setAgent(.claudeCode, enabled: false)

        XCTAssertEqual(settings.state(of: .claudeCode), .off)
        XCTAssertFalse(settings.enabledAgents.contains(.claudeCode))
        XCTAssertTrue(
            AgentKind.claudeCode.profile.scenarios.allSatisfy { !settings.isEnabled($0.id) })

        settings.setAgent(.claudeCode, enabled: true)
        XCTAssertEqual(settings, AgentScenarioSettings())
    }

    func testAllowsOnlyTasksOfEnabledScenarios() {
        var settings = AgentScenarioSettings()
        settings.setEnabled(AgentScenario.codexCLI.id, false)

        XCTAssertFalse(settings.allows(task(.codex, scenario: .codexCLI)))
        XCTAssertTrue(settings.allows(task(.codex, scenario: .codexApp)))
    }

    private func task(_ agent: AgentKind, scenario: AgentScenario) -> AgentTask {
        AgentTask(
            agent: agent, sessionID: scenario.id, title: "t", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 1), host: .unknown, resumeCommand: nil,
            scenario: scenario.id)
    }
}

final class UserDefaultsAgentScenarioStoreTests: XCTestCase {
    private let suiteName = "island.tests.scenarios.\(UUID().uuidString)"
    private lazy var defaults = UserDefaults(suiteName: suiteName)!

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadsAllOnBeforeAnythingIsSaved() {
        XCTAssertEqual(UserDefaultsAgentScenarioStore(defaults: defaults).load(), .init())
    }

    /// Only the switched-off ids are stored, so a scenario added in a later
    /// version starts switched on.
    func testStoresTheScenariosSwitchedOff() {
        var settings = AgentScenarioSettings()
        settings.setEnabled(AgentScenario.piTerminal.id, false)
        UserDefaultsAgentScenarioStore(defaults: defaults).save(settings)

        XCTAssertEqual(UserDefaultsAgentScenarioStore(defaults: defaults).load(), settings)
        XCTAssertEqual(
            defaults.stringArray(forKey: UserDefaultsAgentScenarioStore.key),
            [AgentScenario.piTerminal.id])
    }
}

final class AgentScenarioScannerTests: XCTestCase {
    func testDropsRunsOfSwitchedOffScenarios() {
        let scanner = AgentActivityScanner(sources: [
            CountingSource(
                agent: .codex,
                tasks: [
                    run(.codex, "cli", scenario: .codexCLI, at: 2),
                    run(.codex, "app", scenario: .codexApp, at: 1),
                ])
        ])
        var settings = AgentScenarioSettings()
        settings.setEnabled(AgentScenario.codexCLI.id, false)

        XCTAssertEqual(scanner.completedTasks(settings: settings).map(\.sessionID), ["app"])
        XCTAssertEqual(scanner.completedTasks().map(\.sessionID), ["cli", "app"])
    }

    /// A switched-off agent is not read at all (no sqlite process, no parsing).
    func testSkipsTheSourcesOfSwitchedOffAgents() {
        let pi = CountingSource(agent: .pi, tasks: [run(.pi, "p", scenario: .piTerminal, at: 1)])
        let scanner = AgentActivityScanner(sources: [pi])
        var settings = AgentScenarioSettings()
        settings.setAgent(.pi, enabled: false)

        XCTAssertEqual(scanner.completedTasks(settings: settings), [])
        XCTAssertEqual(pi.calls.count, 0)
    }

    private func run(
        _ agent: AgentKind, _ sessionID: String, scenario: AgentScenario, at seconds: TimeInterval
    ) -> AgentTask {
        AgentTask(
            agent: agent, sessionID: sessionID, title: sessionID, cwd: nil,
            completedAt: Date(timeIntervalSince1970: seconds), host: .unknown,
            resumeCommand: nil, scenario: scenario.id)
    }
}

final class AgentInboxScenarioTests: XCTestCase {
    func testRemovingRowsKeepsThemFromComingBack() {
        let inbox = AgentInbox()
        let codex = AgentTask(
            agent: .codex, sessionID: "c", title: "c", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 1), host: .unknown, resumeCommand: nil,
            scenario: AgentScenario.codexCLI.id)
        let pi = AgentTask(
            agent: .pi, sessionID: "p", title: "p", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 2), host: .unknown, resumeCommand: nil)
        inbox.ingest([codex, pi])

        XCTAssertTrue(inbox.removeAll { $0.scenario == AgentScenario.codexCLI.id })
        XCTAssertEqual(inbox.allEntries.map(\.task), [pi])
        XCTAssertFalse(inbox.removeAll { $0.agent == .claudeDesktop })
        // Switching back on does not resurrect a run that already happened.
        XCTAssertFalse(inbox.ingest([codex]))
    }
}

private final class CountingSource: AgentActivitySource, @unchecked Sendable {
    let agent: AgentKind
    private let tasks: [AgentTask]
    private(set) var calls: [Date] = []

    init(agent: AgentKind, tasks: [AgentTask]) {
        self.agent = agent
        self.tasks = tasks
    }

    func completedTasks() -> [AgentTask] {
        calls.append(Date())
        return tasks
    }
}
