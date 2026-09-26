import AppKit
import IslandCore

/// Executes the plan `AgentReopen` produces: switch tmux to the task's pane,
/// bring the exact terminal tab showing it forward (cmux / Ghostty / Terminal /
/// iTerm2 / VS Code), activate a desktop app, or put the resume command on the
/// clipboard.
///
/// Everything here is best effort — PLAN § Design accepts "second best" — so a
/// missing `tmux` or a dead app degrades to the next step instead of failing.
///
/// Every step shells out (`ps`, `tmux`, `osascript`, which waits on the macOS
/// automation prompt), so callers run it off the main thread.
final class AgentReopenExecutor: Sendable {
    private static let tmuxCandidates = [
        "/opt/homebrew/bin/tmux",
        "/usr/local/bin/tmux",
        "/opt/local/bin/tmux",
        "/usr/bin/tmux",
    ]

    /// Terminals to fall back on when tmux has no attached client to trace.
    private static let hostingBundleIDs = [
        "com.cmuxterm.app",
        "com.microsoft.VSCode",
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
    ]

    private let tabFocuser = TerminalTabFocuser()
    /// Reports whether a scriptable terminal let island control it.
    private let onAutomation: @Sendable (AutomationCheck) -> Void

    init(onAutomation: @escaping @Sendable (AutomationCheck) -> Void = { _ in }) {
        self.onAutomation = onAutomation
    }

    /// Builds the plan from this machine's live process and tmux state. Task
    /// hosts are resolved here (not in the sources) because only some agents
    /// record a pid; pi is found by working directory.
    func plan(for task: AgentTask) -> AgentReopenAction {
        let resolved = resolveHost(for: task).map { task.withHost($0) } ?? task
        let nodes = ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "")
        let panes = TmuxPane.parse(
            run(tmuxArguments(["list-panes", "-a", "-F", Self.paneFormat])) ?? "")
        return AgentReopen.plan(for: resolved, processNodes: nodes, tmuxPanes: panes)
    }

    func perform(_ action: AgentReopenAction, for task: AgentTask) {
        switch action {
        case .focusTmux(let windowTarget, let paneTarget):
            focusTmux(windowTarget: windowTarget, paneTarget: paneTarget, task: task)
        case .focusHostApp(let pid, let cwd):
            if !focusHostApp(processID: pid, cwd: cwd) {
                copyResumeCommand(for: task)
            }
        case .activateApp(let bundleID):
            activate(bundleID: bundleID)
        case .openURL(let link, let fallbackBundleID):
            if let url = URL(string: link), NSWorkspace.shared.open(url) {
                log("opened \(link)")
            } else {
                activate(bundleID: fallbackBundleID)
            }
        case .copyToClipboard(let command):
            copy(command)
        case .nothing:
            log("nothing to focus or resume for this task")
        }
    }

    // MARK: - Host resolution

    /// Finds the running agent process for a task that has no pid, matching on
    /// working directory.
    func resolveHost(for task: AgentTask) -> AgentHost? {
        guard case .unknown = task.host else { return nil }
        let names = Set(task.agent.processNames)
        let processList = run(["/bin/ps", "-axo", "pid=,comm="]) ?? ""
        let pids = AgentProcess.pids(fromProcessList: processList, names: names)
        guard !pids.isEmpty else { return nil }

        let pidList = pids.map(String.init).joined(separator: ",")
        let output = run(["/usr/sbin/lsof", "-a", "-p", pidList, "-d", "cwd", "-Fpn"]) ?? ""
        guard let match = AgentProcess.match(AgentProcess.parseLsof(output), cwd: task.cwd) else {
            return nil
        }
        log("resolved \(task.agent.rawValue) host for \"\(task.title)\": pid \(match.pid)")
        return .terminal(processID: match.pid)
    }

    // MARK: - Actions

    /// Selects the pane, then switches a tmux client to it — `select-window`
    /// alone changes the session's current window but leaves every client on
    /// whatever session it was showing.
    private func focusTmux(windowTarget: String, paneTarget: String, task: AgentTask) {
        _ = run(tmuxArguments(["select-window", "-t", windowTarget]))
        _ = run(tmuxArguments(["select-pane", "-t", paneTarget]))
        let clients = TmuxClient.parse(
            run(tmuxArguments(["list-clients", "-F", Self.clientFormat])) ?? "")
        if let client = TmuxClient.pick(clients, forPane: paneTarget) {
            _ = run(tmuxArguments(["switch-client", "-c", client.tty, "-t", paneTarget]))
            log("tmux client \(client.tty) -> \(paneTarget)")
            if focusTerminal(TerminalLeaf(pid: client.pid, tty: client.tty), cwd: task.cwd) {
                return
            }
        } else {
            log("tmux -> \(paneTarget) (no attached client)")
        }
        activateAnyTerminal()
    }

    /// Last resort when tmux has no client island can trace to an app.
    private func activateAnyTerminal() {
        for bundleID in Self.hostingBundleIDs {
            guard
                let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    .first
            else { continue }
            app.activate()
            log("activated \(bundleID)")
            return
        }
        log("could not find the terminal hosting tmux")
    }

    private func focusHostApp(processID: Int32, cwd: String?) -> Bool {
        let tty = ProcessEnvironment.ttyPath(
            fromPS: run(["/bin/ps", "-o", "tty=", "-p", String(processID)]) ?? "")
        return focusTerminal(TerminalLeaf(pid: processID, tty: tty), cwd: cwd)
    }

    /// Walks the ancestor chain up to the GUI app showing `leaf`, focuses the
    /// tab holding it when that app is scriptable, and otherwise just brings
    /// the app forward. Returns false when `leaf` runs under no app at all.
    private func focusTerminal(_ leaf: TerminalLeaf, cwd: String?) -> Bool {
        let nodes = ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "")
        let chain = ProcessTree.ancestors(of: leaf.pid, in: nodes)
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        let apps = running.map {
            RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier)
        }
        guard let host = HostApp.nearest(in: chain, among: apps),
            let app = running.first(where: { $0.processIdentifier == host.pid })
        else { return false }

        let environment =
            host.bundleID == TerminalTabFocus.cmuxBundleID
            ? ProcessEnvironment.parse(
                run(["/bin/ps", "eww", "-o", "command=", "-p", String(leaf.pid)]) ?? "",
                keys: [TerminalTabFocus.surfaceKey])
            : [:]
        let focus = TerminalTabFocus.plan(
            hostBundleID: host.bundleID, leaf: leaf, chain: chain, environment: environment)
        let name = host.bundleID ?? "pid \(host.pid)"
        let result = tabFocuser.focus(focus)
        if focus.usesAppleScript, result != .notFound {
            let appName = app.localizedName ?? name
            onAutomation(AutomationCheck(appName: appName, authorized: result == .focused))
        }
        if result == .focused {
            log("focused \(focus) in \(name) for pid \(leaf.pid)")
            return true
        }

        if host.bundleID == TerminalTabFocus.vscodeBundleID, let cwd, !cwd.isEmpty {
            // Without the extension, the folder still picks the right window.
            _ = run(["/usr/bin/open", "-b", TerminalTabFocus.vscodeBundleID, cwd])
        } else {
            app.activate()
        }
        log("activated \(name) for pid \(leaf.pid) (tab \(result): \(focus))")
        return true
    }

    private func activate(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        {
            app.activate()
            log("activated \(bundleID)")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log("no app for bundle id \(bundleID)")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        log("launching \(bundleID)")
    }

    private func copyResumeCommand(for task: AgentTask) {
        guard let command = task.resumeCommand, !command.isEmpty else {
            log("could not find a window or a resume command for \"\(task.title)\"")
            return
        }
        copy(command)
    }

    private func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        log("copied to clipboard: \(command)")
    }

    // MARK: - Process plumbing

    static let paneFormat = "#{pane_pid}\t#{session_name}:#{window_index}.#{pane_index}"
    static let clientFormat =
        "#{client_pid}\t#{client_tty}\t#{client_session}\t#{client_activity}"

    func tmuxArguments(_ arguments: [String]) -> [String] {
        [tmuxPath()] + arguments
    }

    private func tmuxPath() -> String {
        Self.tmuxCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
    }

    func run(_ arguments: [String]) -> String? {
        Subprocess.run(arguments)
    }

    func log(_ message: String) {
        FileHandle.standardError.write(Data("[island] \(message)\n".utf8))
    }
}
