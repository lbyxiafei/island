import XCTest

@testable import IslandCore

final class TmuxClientTests: XCTestCase {
    func testParsesListClientsOutput() {
        let clients = TmuxClient.parse(
            """
            3510\t/dev/ttys000\tjob\t1790000000
            garbage
            4000\t/dev/ttys007\tisland\t1790000100
            """
        )
        XCTAssertEqual(
            clients,
            [
                TmuxClient(pid: 3510, tty: "/dev/ttys000", session: "job", activity: 1_790_000_000),
                TmuxClient(
                    pid: 4000, tty: "/dev/ttys007", session: "island", activity: 1_790_000_100),
            ])
    }

    func testMissingOrUnreadableActivityCountsAsNeverActive() {
        XCTAssertEqual(
            TmuxClient.parse("1\t/dev/ttys001\ts\n2\t/dev/ttys002\tt\tsoon"),
            [
                TmuxClient(pid: 1, tty: "/dev/ttys001", session: "s", activity: 0),
                TmuxClient(pid: 2, tty: "/dev/ttys002", session: "t", activity: 0),
            ])
    }

    /// Live 2026-09-25: the only client sat on `job` while the task was in
    /// `island`, so it has to be switched rather than left where it was.
    func testPicksTheClientAlreadyOnTheTargetSession() {
        let clients = [
            TmuxClient(pid: 1, tty: "/dev/ttys001", session: "island", activity: 10),
            TmuxClient(pid: 2, tty: "/dev/ttys002", session: "job", activity: 99),
        ]
        XCTAssertEqual(TmuxClient.pick(clients, forPane: "island:1.1")?.pid, 1)
    }

    func testOtherwisePicksTheMostRecentlyActiveClient() {
        let clients = [
            TmuxClient(pid: 1, tty: "/dev/ttys001", session: "a", activity: 10),
            TmuxClient(pid: 2, tty: "/dev/ttys002", session: "b", activity: 99),
        ]
        XCTAssertEqual(TmuxClient.pick(clients, forPane: "island:1.1")?.pid, 2)
        XCTAssertNil(TmuxClient.pick([], forPane: "island:1.1"))
    }

    func testSessionOfAPaneTarget() {
        XCTAssertEqual(TmuxClient.session(ofPane: "island:1.1"), "island")
        XCTAssertEqual(TmuxClient.session(ofPane: "solo"), "solo")
    }
}

final class ProcessEnvironmentTests: XCTestCase {
    func testPicksRequestedKeysOutOfPSEnvironmentOutput() {
        let output =
            "tmux TERM_PROGRAM=ghostty CMUX_WORKSPACE_ID=F9BE CMUX_SURFACE_ID=37C0B807 HOME=/Users/x\n"
        XCTAssertEqual(
            ProcessEnvironment.parse(output, keys: ["CMUX_SURFACE_ID", "TERM_PROGRAM", "MISSING"]),
            ["CMUX_SURFACE_ID": "37C0B807", "TERM_PROGRAM": "ghostty"])
    }

    func testIgnoresLookalikesInsideOtherTokens() {
        XCTAssertEqual(
            ProcessEnvironment.parse("cmd --flag=XCMUX_SURFACE_ID=nope", keys: ["CMUX_SURFACE_ID"]),
            [:])
    }

    func testTTYPathFromPS() {
        XCTAssertEqual(ProcessEnvironment.ttyPath(fromPS: " ttys012\n"), "/dev/ttys012")
        XCTAssertEqual(ProcessEnvironment.ttyPath(fromPS: "/dev/ttys003"), "/dev/ttys003")
        XCTAssertNil(ProcessEnvironment.ttyPath(fromPS: "??"))
        XCTAssertNil(ProcessEnvironment.ttyPath(fromPS: " \n"))
    }
}

final class TerminalTabFocusTests: XCTestCase {
    private let leaf = TerminalLeaf(pid: 3510, tty: "/dev/ttys000")

    func testCmuxUsesTheSurfaceIDItExportsToEveryTerminal() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.cmuxterm.app", leaf: leaf, chain: [3510],
                environment: ["CMUX_SURFACE_ID": "37C0"]),
            .scriptable(bundleID: "com.cmuxterm.app", match: .terminalID("37C0")))
    }

    func testCmuxWithoutAReadableEnvironmentFallsBackToATitleProbe() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.cmuxterm.app", leaf: leaf, chain: [3510], environment: [:]),
            .scriptable(bundleID: "com.cmuxterm.app", match: .titleProbe(tty: "/dev/ttys000")))
    }

    func testGhosttyHasNoTerminalIDSoItProbesTheTitle() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.mitchellh.ghostty", leaf: leaf, chain: [3510],
                environment: ["CMUX_SURFACE_ID": "ignored"]),
            .scriptable(bundleID: "com.mitchellh.ghostty", match: .titleProbe(tty: "/dev/ttys000")))
    }

    func testTerminalAndITermMatchOnTTY() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.apple.Terminal", leaf: leaf, chain: [], environment: [:]),
            .appleTerminal(tty: "/dev/ttys000"))
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.googlecode.iterm2", leaf: leaf, chain: [], environment: [:]),
            .iTerm(tty: "/dev/ttys000"))
    }

    func testVSCodeMatchesTheTerminalShellAnywhereInTheChain() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "com.microsoft.VSCode", leaf: leaf, chain: [89419, 30405, 30389],
                environment: [:]),
            .vscode(pids: [89419, 30405, 30389]))
    }

    func testNeedsATTYWhereTheMatchIsByTTY() {
        let noTTY = TerminalLeaf(pid: 1, tty: nil)
        for bundleID in [
            "com.cmuxterm.app", "com.mitchellh.ghostty", "com.apple.Terminal",
            "com.googlecode.iterm2",
        ] {
            XCTAssertEqual(
                TerminalTabFocus.plan(
                    hostBundleID: bundleID, leaf: noTTY, chain: [], environment: [:]),
                .none, bundleID)
        }
    }

    func testUnknownHostsOnlyGetActivated() {
        XCTAssertEqual(
            TerminalTabFocus.plan(
                hostBundleID: "dev.warp.Warp-Stable", leaf: leaf, chain: [], environment: [:]),
            .none)
        XCTAssertEqual(
            TerminalTabFocus.plan(hostBundleID: nil, leaf: leaf, chain: [], environment: [:]), .none
        )
    }
}

final class TerminalScriptTests: XCTestCase {
    func testQuotesAppleScriptStrings() {
        XCTAssertEqual(TerminalScript.quoted(#"a"b\c"#), #""a\"b\\c""#)
    }

    func testScriptableFocusByID() {
        let script = TerminalScript.focus(bundleID: "com.cmuxterm.app", match: .terminalID("37C0"))
        XCTAssertTrue(script.contains(#"tell application id "com.cmuxterm.app""#))
        XCTAssertTrue(script.contains(#"if (id of t) is "37C0" then"#))
        XCTAssertTrue(script.contains("activate window w"))
        XCTAssertTrue(script.contains("focus t"))
    }

    func testScriptableFocusByProbedTitle() {
        let script = TerminalScript.focus(
            bundleID: "com.mitchellh.ghostty", match: .titleProbe(tty: "/dev/ttys012"), probe: "p-1"
        )
        XCTAssertTrue(script.contains(#"if (name of t) is "p-1" then"#))
    }

    func testListsTerminalsAndParsesTheListing() {
        // Inside `tell application "Ghostty"`, `tab` names Ghostty's tab class,
        // so the separators must be bound before entering the tell block.
        let listing = TerminalScript.listTerminals(bundleID: "com.mitchellh.ghostty")
        XCTAssertTrue(listing.hasPrefix("set separator to tab\nset newline to linefeed\n"))
        XCTAssertTrue(listing.contains(#"(id of t) & separator & (name of t) & newline"#))
        XCTAssertEqual(
            TerminalScript.parseListing("A\t✳ claude\nB\tzsh\tstill title\nbad\n"),
            ["A": "✳ claude", "B": "zsh\tstill title"])
    }

    func testAppleTerminalAndITermScriptsMatchTheTTY() throws {
        let terminal = TerminalScript.appleTerminal(tty: "/dev/ttys003")
        XCTAssertTrue(terminal.contains(#"if tty of t is "/dev/ttys003" then"#))
        XCTAssertTrue(terminal.contains("set selected of t to true"))
        // Live 2026-09-25: `set index` only sticks once Terminal is frontmost;
        // activating afterwards puts the previous front window back on top.
        let activation = try XCTUnwrap(terminal.range(of: "activate"))
        let reorder = try XCTUnwrap(terminal.range(of: "set index"))
        XCTAssertLessThan(activation.lowerBound, reorder.lowerBound)

        let iterm = TerminalScript.iTerm(tty: "/dev/ttys003")
        XCTAssertTrue(iterm.contains(#"if tty of s is "/dev/ttys003" then"#))
        XCTAssertTrue(iterm.contains("select s"))
        XCTAssertLessThan(
            try XCTUnwrap(iterm.range(of: "activate")).lowerBound,
            try XCTUnwrap(iterm.range(of: "select w")).lowerBound)
    }

    func testTitleEscapeSequence() {
        XCTAssertEqual(TerminalScript.titleSequence("hi"), "\u{1B}]2;hi\u{07}")
    }
}

final class VSCodeFocusTests: XCTestCase {
    func testRequestIsTheJSONTheExtensionReads() throws {
        let request = VSCodeFocusRequest(
            id: "r1", time: Date(timeIntervalSince1970: 1.5), pids: [3, 2])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try request.encoded()) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "r1")
        XCTAssertEqual(object["time"] as? Int, 1500)
        XCTAssertEqual(object["pids"] as? [Int], [3, 2])
    }

    func testResponsePrefersTheWorkspaceFile() {
        let workspace = VSCodeFocusResponse.decode(
            Data(#"{"workspaceFile":"/w/x.code-workspace","folders":["/a"]}"#.utf8))
        XCTAssertEqual(workspace?.windowPath, "/w/x.code-workspace")

        let folder = VSCodeFocusResponse.decode(
            Data(#"{"workspaceFile":null,"folders":["/a","/b"]}"#.utf8))
        XCTAssertEqual(folder?.windowPath, "/a")

        let fileOnly = VSCodeFocusResponse.decode(
            Data(#"{"workspaceFile":"/w/x.code-workspace"}"#.utf8))
        XCTAssertEqual(
            fileOnly, VSCodeFocusResponse(workspaceFile: "/w/x.code-workspace", folders: []))

        XCTAssertNil(VSCodeFocusResponse.decode(Data(#"{"folders":[]}"#.utf8))?.windowPath)
        XCTAssertNil(VSCodeFocusResponse.decode(Data("nope".utf8)))
    }

    func testInstalledVersionFromExtensionsJSON() {
        let json = Data(
            """
            [{"identifier":{"id":"jacobdufault.fuzzy-search"},"version":"0.0.3"},
             {"identifier":{"id":"BinYanLi.Island"},"version":"0.1.0"}]
            """.utf8)
        XCTAssertEqual(VSCodeExtension.installedVersion(in: json, id: "binyanli.island"), "0.1.0")
        XCTAssertNil(VSCodeExtension.installedVersion(in: json, id: "other.ext"))
        XCTAssertNil(VSCodeExtension.installedVersion(in: Data("{}".utf8), id: "binyanli.island"))
    }
}
