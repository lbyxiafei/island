import XCTest

@testable import IslandCore

final class TaskVisibilityTests: XCTestCase {
    // agent 500 -> shell 400 -> Ghostty 300; tmux client 700 -> shell 600 -> Ghostty 300;
    // tmux pane shell 800 hosts agent 900.
    private let nodes = ProcessTree.parse(
        """
        500 400
        400 300
        700 600
        600 300
        900 800
        800 850
        850 1
        300 1
        """
    )
    private let ghostty = RunningApp(pid: 300, bundleID: TerminalTabFocus.ghosttyBundleID)
    private let finder = RunningApp(pid: 42, bundleID: "com.apple.finder")

    func testADesktopTaskIsInViewWhileItsAppIsFrontmost() {
        let task = makeTask(host: .desktop(bundleID: "com.openai.codex"))
        let codex = RunningApp(pid: 9, bundleID: "com.openai.codex")

        XCTAssertEqual(plan(task, frontmost: codex), .visible)
        XCTAssertEqual(plan(task, frontmost: finder), .hidden)
        XCTAssertEqual(plan(task, frontmost: nil), .hidden)
    }

    func testATaskWithNoKnownHostIsNeverAssumedInView() {
        XCTAssertEqual(plan(makeTask(host: .unknown), frontmost: ghostty), .hidden)
    }

    func testATerminalTaskAsksItsFrontmostHostAppAboutTheTab() {
        let task = makeTask(host: .terminal(processID: 500), cwd: "/repo")

        XCTAssertEqual(
            plan(task, frontmost: ghostty),
            .checkTab(
                host: ghostty, leaf: TerminalLeaf(pid: 500, tty: nil), chain: [500, 400, 300],
                cwd: "/repo"))
        XCTAssertEqual(plan(task, frontmost: finder), .hidden)
    }

    func testATmuxTaskIsCheckedThroughTheClientShowingItsPane() {
        let task = makeTask(host: .terminal(processID: 900), cwd: "/repo")
        let panes = [
            TmuxPane(pid: 800, windowTarget: "work:1", paneTarget: "work:1.1", isCurrent: true)
        ]
        let clients = [
            TmuxClient(pid: 700, tty: "/dev/ttys003", session: "work", activity: 1),
            TmuxClient(pid: 1234, tty: "/dev/ttys009", session: "other", activity: 9),
        ]

        XCTAssertEqual(
            plan(task, frontmost: ghostty, panes: panes, clients: clients),
            .checkTab(
                host: ghostty, leaf: TerminalLeaf(pid: 700, tty: "/dev/ttys003"),
                chain: [700, 600, 300], cwd: nil))
    }

    func testATmuxPaneOffScreenOrUnattachedIsHidden() {
        let task = makeTask(host: .terminal(processID: 900))
        let current = [
            TmuxPane(pid: 800, windowTarget: "work:1", paneTarget: "work:1.1", isCurrent: true)
        ]
        let behind = [
            TmuxPane(pid: 800, windowTarget: "work:2", paneTarget: "work:2.1", isCurrent: false)
        ]
        let attached = [TmuxClient(pid: 700, tty: "/dev/ttys003", session: "work", activity: 1)]
        let elsewhere = [TmuxClient(pid: 700, tty: "/dev/ttys003", session: "other", activity: 1)]

        XCTAssertEqual(plan(task, frontmost: ghostty, panes: behind, clients: attached), .hidden)
        XCTAssertEqual(plan(task, frontmost: ghostty, panes: current, clients: elsewhere), .hidden)
        XCTAssertEqual(plan(task, frontmost: finder, panes: current, clients: attached), .hidden)
    }

    // MARK: - Asking the app which tab it shows

    func testTerminalAndITermReportTheSelectedTTY() throws {
        let terminal = TerminalTabFocus.appleTerminal(tty: "/dev/ttys003")
        let iTerm = TerminalTabFocus.iTerm(tty: "/dev/ttys003")

        XCTAssertTrue(try XCTUnwrap(FocusedTab.script(for: terminal)).contains("selected tab"))
        XCTAssertTrue(try XCTUnwrap(FocusedTab.script(for: iTerm)).contains("current session"))
        XCTAssertTrue(FocusedTab.matches(terminal, output: "/dev/ttys003", cwd: nil))
        XCTAssertFalse(FocusedTab.matches(terminal, output: "/dev/ttys004", cwd: nil))
        XCTAssertTrue(FocusedTab.matches(iTerm, output: "/dev/ttys003", cwd: nil))
        XCTAssertFalse(FocusedTab.matches(iTerm, output: "", cwd: nil))
    }

    func testCmuxComparesTheFocusedTerminalWithTheSurfaceID() throws {
        let focus = TerminalTabFocus.scriptable(
            bundleID: TerminalTabFocus.cmuxBundleID, match: .terminalID("S1"))
        let script = try XCTUnwrap(FocusedTab.script(for: focus))

        XCTAssertTrue(script.contains("focused terminal of selected tab of front window"))
        XCTAssertTrue(script.contains(TerminalTabFocus.cmuxBundleID))
        XCTAssertTrue(FocusedTab.matches(focus, output: "S1\nS1\t/a\nS2\t/b", cwd: nil))
        XCTAssertFalse(FocusedTab.matches(focus, output: "S2\nS1\t/a\nS2\t/b", cwd: nil))
    }

    func testGhosttyNeedsTheFocusedTerminalToBeTheOnlyOneInTheTaskDirectory() {
        let focus = TerminalTabFocus.scriptable(
            bundleID: TerminalTabFocus.ghosttyBundleID, match: .titleProbe(tty: "/dev/ttys003"))

        XCTAssertTrue(FocusedTab.matches(focus, output: "A\nA\t/repo\nB\t/other", cwd: "/repo"))
        XCTAssertFalse(FocusedTab.matches(focus, output: "B\nA\t/repo\nB\t/other", cwd: "/repo"))
        // Two tabs in the same directory: cannot tell which one runs the task.
        XCTAssertFalse(FocusedTab.matches(focus, output: "A\nA\t/repo\nB\t/repo", cwd: "/repo"))
        XCTAssertFalse(FocusedTab.matches(focus, output: "A\nA\t/repo\nB\t/other", cwd: nil))
        // A single terminal is necessarily the one showing the task.
        XCTAssertTrue(FocusedTab.matches(focus, output: "A\nA\t/elsewhere", cwd: nil))
        XCTAssertFalse(FocusedTab.matches(focus, output: "", cwd: nil))
    }

    func testVSCodeAndUnknownHostsCannotBeAsked() {
        XCTAssertNil(FocusedTab.script(for: .vscode(pids: [1])))
        XCTAssertNil(FocusedTab.script(for: .none))
        XCTAssertFalse(FocusedTab.matches(.vscode(pids: [1]), output: "x", cwd: nil))
        XCTAssertFalse(FocusedTab.matches(.none, output: "x", cwd: nil))
    }

    func testVSCodeShowsTheTaskWhenAFocusedWindowHasItsTerminalActive() throws {
        let focused = try XCTUnwrap(
            VSCodeWindowState.decode(Data(#"{"pid":7,"focused":true,"terminalPid":400}"#.utf8)))
        let blurred = try XCTUnwrap(
            VSCodeWindowState.decode(Data(#"{"pid":8,"focused":false,"terminalPid":400}"#.utf8)))
        let other = try XCTUnwrap(
            VSCodeWindowState.decode(Data(#"{"pid":9,"focused":true,"terminalPid":999}"#.utf8)))
        let chain: [Int32] = [500, 400, 300]

        XCTAssertEqual(focused, VSCodeWindowState(pid: 7, isFocused: true, terminalPID: 400))
        XCTAssertTrue(VSCodeWindowState.shows(chain, in: [blurred, focused]))
        XCTAssertFalse(VSCodeWindowState.shows(chain, in: [blurred, other]))
        XCTAssertFalse(VSCodeWindowState.shows(chain, in: []))
    }

    func testVSCodeWindowStateToleratesMissingOrBrokenFields() {
        XCTAssertEqual(
            VSCodeWindowState.decode(Data(#"{"pid":7,"focused":true,"terminalPid":null}"#.utf8)),
            VSCodeWindowState(pid: 7, isFocused: true, terminalPID: nil))
        XCTAssertEqual(
            VSCodeWindowState.decode(Data(#"{"pid":7}"#.utf8)),
            VSCodeWindowState(pid: 7, isFocused: false, terminalPID: nil))
        XCTAssertNil(VSCodeWindowState.decode(Data(#"{"focused":true}"#.utf8)))
        XCTAssertNil(VSCodeWindowState.decode(Data("not json".utf8)))
    }

    // MARK: - Helpers

    private func plan(
        _ task: AgentTask,
        frontmost: RunningApp?,
        panes: [TmuxPane] = [],
        clients: [TmuxClient] = []
    ) -> TaskViewPlan {
        TaskVisibility.plan(
            for: task,
            frontmost: frontmost,
            apps: [ghostty, finder],
            processNodes: nodes,
            tmuxPanes: panes,
            tmuxClients: clients
        )
    }

    private func makeTask(host: AgentHost, cwd: String? = nil) -> AgentTask {
        AgentTask(
            agent: .claudeCode,
            sessionID: "s",
            title: "t",
            cwd: cwd,
            completedAt: Date(timeIntervalSince1970: 1),
            host: host,
            resumeCommand: nil
        )
    }
}
