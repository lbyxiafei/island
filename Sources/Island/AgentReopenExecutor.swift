import AppKit
import IslandCore

/// Executes the plan `AgentReopen` produces: focus the tmux pane hosting the
/// task, activate a desktop app, or put the resume command on the clipboard.
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

    /// Terminals island falls back to when it cannot tell which one hosts tmux.
    private static let terminalBundleIDs = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.microsoft.VSCode",
    ]

    /// Builds the plan from this machine's live process and tmux state.
    func plan(for task: AgentTask) -> AgentReopenAction {
        let nodes = ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "")
        let panes = TmuxPane.parse(
            run(tmuxArguments(["list-panes", "-a", "-F", Self.paneFormat])) ?? "")
        return AgentReopen.plan(for: task, processNodes: nodes, tmuxPanes: panes)
    }

    func perform(_ action: AgentReopenAction) {
        switch action {
        case .focusTmux(let windowTarget, let paneTarget):
            focusTmux(windowTarget: windowTarget, paneTarget: paneTarget)
        case .activateApp(let bundleID):
            activate(bundleID: bundleID)
        case .copyToClipboard(let command):
            copy(command)
        case .nothing:
            log("nothing to focus or resume for this task")
        }
    }

    // MARK: - Actions

    private func focusTmux(windowTarget: String, paneTarget: String) {
        _ = run(tmuxArguments(["select-window", "-t", windowTarget]))
        _ = run(tmuxArguments(["select-pane", "-t", paneTarget]))
        log("tmux -> \(paneTarget)")
        activateHostingTerminal()
    }

    /// The tmux client's ancestor chain ends at the GUI terminal showing it, so
    /// activating the first ancestor that is a real app brings that window up.
    private func activateHostingTerminal() {
        let clients =
            (run(tmuxArguments(["list-clients", "-F", "#{client_pid}"])) ?? "")
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        let nodes = ProcessTree.parse(run(["/bin/ps", "-axo", "pid=,ppid="]) ?? "")
        for client in clients {
            for ancestor in ProcessTree.ancestors(of: client, in: nodes) {
                guard let app = NSRunningApplication(processIdentifier: ancestor),
                    app.activationPolicy != .prohibited
                else { continue }
                app.activate()
                log("activated \(app.localizedName ?? "app") (pid \(ancestor))")
                return
            }
        }
        for bundleID in Self.terminalBundleIDs {
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
