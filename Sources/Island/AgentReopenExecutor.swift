import AppKit
import IslandCore

/// Executes the plan `AgentReopen` produces: focus the tmux pane hosting the
/// task, bring the app hosting its terminal forward, activate a desktop app, or
/// put the resume command on the clipboard.
///
/// Everything here is best effort — PLAN § Design accepts "second best" — so a
/// missing `tmux` or a dead app degrades to the next step instead of failing.
@MainActor
final class AgentReopenExecutor {
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

    /// VS Code can be pointed at a folder, which focuses the window showing it.
    private static let vscodeBundleID = "com.microsoft.VSCode"

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
    private func resolveHost(for task: AgentTask) -> AgentHost? {
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

    private func focusTmux(windowTarget: String, paneTarget: String, task: AgentTask) {
        _ = run(tmuxArguments(["select-window", "-t", windowTarget]))
        _ = run(tmuxArguments(["select-pane", "-t", paneTarget]))
        log("tmux -> \(paneTarget)")
        activateTmuxHost()
    }

    /// The tmux client's ancestor chain ends at the GUI terminal showing it, so
    /// focusing the first client we can place brings that window up.
    private func activateTmuxHost() {
        let clients =
            (run(tmuxArguments(["list-clients", "-F", "#{client_pid}"])) ?? "")
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        for client in clients where focusHostApp(processID: client, cwd: nil) {
            return
        }
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

    /// Walks the ancestor chain up to the GUI app showing the process. Returns
    /// false when the process is not running under any app.
    private func focusHostApp(processID: Int32, cwd: String?) -> Bool {
        let nodes = ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "")
        let chain = ProcessTree.ancestors(of: processID, in: nodes)
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
        }
        let apps = running.map {
            RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier)
        }
        guard let host = HostApp.nearest(in: chain, among: apps),
            let app = running.first(where: { $0.processIdentifier == host.pid })
        else { return false }

        let bundleID = host.bundleID ?? "pid \(host.pid)"
        if host.bundleID == Self.vscodeBundleID, let cwd, !cwd.isEmpty {
            // Focuses the VS Code window showing that folder.
            _ = run(["/usr/bin/open", "-b", Self.vscodeBundleID, cwd])
        } else {
            app.activate()
        }
        log("focused \(bundleID) for pid \(processID)")
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

    private static let paneFormat = "#{pane_pid}\t#{session_name}:#{window_index}.#{pane_index}"

    private func tmuxArguments(_ arguments: [String]) -> [String] {
        [tmuxPath()] + arguments
    }

    private func tmuxPath() -> String {
        Self.tmuxCandidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
    }

    private func run(_ arguments: [String]) -> String? {
        guard let executable = arguments.first else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[island] \(message)\n".utf8))
    }
}
