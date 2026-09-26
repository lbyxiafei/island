import AppKit
import IslandCore

/// Answers "is the user looking at this task right now?" from this machine's
/// live state, following the plan `TaskVisibility` makes. Read-only: it never
/// focuses, retitles or activates anything, and never triggers an automation
/// prompt — an app island may not script yet simply counts as "not in view".
///
/// Shells out (`ps`, `tmux`, `osascript`), so callers run it off the main thread.
extension AgentReopenExecutor {
    static let visibilityPaneFormat =
        "#{pane_pid}\t#{session_name}:#{window_index}.#{pane_index}\t#{window_active}#{pane_active}"

    /// The ids of `tasks` whose tab or app is the one in front of the user.
    func tasksInView(_ tasks: [AgentTask], frontmost: RunningApp?) -> Set<String> {
        guard let frontmost, !tasks.isEmpty else { return [] }
        let resolved = tasks.map { task in
            resolveHost(for: task).map { task.withHost($0) } ?? task
        }
        let inTerminals = resolved.contains {
            if case .terminal = $0.host { return true }
            return false
        }
        let nodes =
            inTerminals ? ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "") : []
        let panes =
            inTerminals
            ? TmuxPane.parse(
                run(tmuxArguments(["list-panes", "-a", "-F", Self.visibilityPaneFormat])) ?? "")
            : []
        let clients =
            panes.isEmpty
            ? []
            : TmuxClient.parse(
                run(tmuxArguments(["list-clients", "-F", Self.clientFormat])) ?? "")
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier) }

        var seen: Set<String> = []
        for task in resolved {
            let plan = TaskVisibility.plan(
                for: task, frontmost: frontmost, apps: apps, processNodes: nodes,
                tmuxPanes: panes, tmuxClients: clients)
            switch plan {
            case .hidden:
                continue
            case .visible:
                seen.insert(task.id)
            case .checkTab(let host, let leaf, let chain, let cwd):
                if isFocused(leaf, in: host, chain: chain, cwd: cwd) {
                    seen.insert(task.id)
                }
            }
        }
        return seen
    }

    private func isFocused(
        _ leaf: TerminalLeaf, in host: RunningApp, chain: [Int32], cwd: String?
    ) -> Bool {
        guard let bundleID = host.bundleID else { return false }
        if bundleID == TerminalTabFocus.vscodeBundleID {
            return VSCodeWindowState.shows(chain, in: Self.vscodeWindows())
        }
        guard Self.mayScript(bundleID) else { return false }
        let tty =
            leaf.tty
            ?? ProcessEnvironment.ttyPath(
                fromPS: run(["/bin/ps", "-o", "tty=", "-p", String(leaf.pid)]) ?? "")
        let environment =
            bundleID == TerminalTabFocus.cmuxBundleID
            ? ProcessEnvironment.parse(
                run(["/bin/ps", "eww", "-o", "command=", "-p", String(leaf.pid)]) ?? "",
                keys: [TerminalTabFocus.surfaceKey])
            : [:]
        let focus = TerminalTabFocus.plan(
            hostBundleID: bundleID, leaf: TerminalLeaf(pid: leaf.pid, tty: tty), chain: chain,
            environment: environment)
        guard let script = FocusedTab.script(for: focus) else { return false }
        return FocusedTab.matches(focus, output: Subprocess.appleScript(script).text, cwd: cwd)
    }

    /// What each open VS Code window last published; files left behind by a
    /// window that died without cleaning up are skipped.
    private static func vscodeWindows() -> [VSCodeWindowState] {
        let directory = TerminalTabFocuser.vscodeDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix(VSCodeWindowState.filePrefix) }.compactMap { name in
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
                let window = VSCodeWindowState.decode(data), kill(window.pid, 0) == 0
            else { return nil }
            return window
        }
    }

    /// True only when the user already let island script `bundleID`; never asks.
    private static func mayScript(_ bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.utf8CString.withUnsafeBufferPointer { buffer in
            AECreateDesc(
                typeApplicationBundleID, buffer.baseAddress, buffer.count - 1, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
            == noErr
    }
}
