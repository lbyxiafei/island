import AppKit
import IslandCore

let arguments = Set(CommandLine.arguments.dropFirst())

// Before anything reads settings: carry them over from the pre-release bundle id.
if Bundle.main.bundleIdentifier != LegacySettings.bundleID,
    let legacy = UserDefaults(suiteName: LegacySettings.bundleID)
{
    let copied = LegacySettings.migrate(from: legacy, to: .standard)
    if !copied.isEmpty {
        FileHandle.standardError.write(
            Data("[island] migrated settings from \(LegacySettings.bundleID): \(copied)\n".utf8))
    }
}

let configuration = ResolvedConfiguration(environment: ProcessInfo.processInfo.environment)

if arguments.contains("--help") || arguments.contains("-h") {
    print(
        """
        island — POC overlay window summoned by a global hotkey.

        usage: Island [--print-config | --help]

        environment:
          ISLAND_HOTKEY=cmd+ctrl+,        hotkey that summons the overlay
          ISLAND_OVERLAY_SECONDS=5        how long the pop-up stays on screen (settings override it)

        flags (login-item flags must run from inside the app bundle):
          --print-config                  resolve the environment and exit
          --scan-agents                   list completed agent tasks and exit
          --reopen-plan <pid> [--perform] print how island would reopen a task on that pid (and do it)
          --in-view <pid> [cwd]           whether a task on that pid is the tab in front of the user
          --login-item-status             report the launch-at-login state
          --login-item-enable             start at login from now on
          --login-item-disable            stop starting at login

        The app lives in the menu bar: summon, settings (hotkey), launch at
        login, quit. `pkill -x Island` also works.
        """
    )
    exit(EXIT_SUCCESS)
}

if arguments.contains("--login-item-status") {
    print(LoginItemController().status.rawValue)
    exit(EXIT_SUCCESS)
}

if arguments.contains("--login-item-enable") || arguments.contains("--login-item-disable") {
    let enable = arguments.contains("--login-item-enable")
    do {
        let controller = LoginItemController()
        try controller.setEnabled(enable)
        print(
            "launch at login \(enable ? "enabled" : "disabled") (status: \(controller.status.rawValue))"
        )
        exit(EXIT_SUCCESS)
    } catch {
        print("launch at login failed: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
    }
}

if arguments.contains("--scan-agents") {
    let tasks = AgentActivityScanner.standard(sqlite: ProcessSQLiteQuerying()).completedTasks()
    if tasks.isEmpty {
        print("no completed agent tasks found")
    } else {
        let formatter = ISO8601DateFormatter()
        for task in tasks {
            print(
                "\(formatter.string(from: task.completedAt))  \(task.agent.rawValue)  \(task.title)  [\(task.cwd ?? "-")]  \(task.host)  \(task.resumeCommand ?? "-")"
            )
        }
    }
    exit(EXIT_SUCCESS)
}

/// The task the debug flags act on. One argument: a pid to treat as the agent
/// process (optionally followed by its working directory). Two: an agent name
/// and a working directory, which exercises the no-pid host resolution.
func debugTask(after flag: Int) -> AgentTask? {
    let rest = Array(CommandLine.arguments.dropFirst(flag + 1).prefix(2))
        .filter { !$0.hasPrefix("--") }
    guard let first = rest.first else { return nil }
    let cwd = rest.count > 1 && !rest[1].isEmpty ? rest[1] : nil
    if let pid = Int32(first) {
        return AgentTask(
            agent: .claudeCode, sessionID: "debug", title: "debug", cwd: cwd,
            completedAt: Date(), host: .terminal(processID: pid),
            resumeCommand: "claude --resume debug")
    }
    guard let agent = AgentKind(rawValue: first), let cwd else { return nil }
    return AgentTask(
        agent: agent, sessionID: "debug", title: "debug", cwd: cwd, completedAt: Date(),
        host: .unknown, resumeCommand: "\(agent.rawValue) --resume debug")
}

if let flag = CommandLine.arguments.firstIndex(of: "--reopen-plan") {
    guard let task = debugTask(after: flag) else {
        print("usage: --reopen-plan <pid> | <agent: claude-code|pi|codex> <cwd> [--perform]")
        exit(EXIT_FAILURE)
    }
    let executor = AgentReopenExecutor()
    let plan = executor.plan(for: task)
    print(plan)
    if CommandLine.arguments.contains("--perform") {
        executor.perform(plan, for: task)
    }
    exit(EXIT_SUCCESS)
}

if let flag = CommandLine.arguments.firstIndex(of: "--in-view") {
    guard let task = debugTask(after: flag) else {
        print("usage: --in-view <pid> [cwd] | <agent: claude-code|pi|codex> <cwd>")
        exit(EXIT_FAILURE)
    }
    let front = NSWorkspace.shared.frontmostApplication
    let frontmost = front.map {
        RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier)
    }
    let seen = AgentReopenExecutor().tasksInView([task], frontmost: frontmost)
    print(
        "frontmost \(front?.bundleIdentifier ?? "-"): \(seen.isEmpty ? "not in view" : "in view")")
    exit(EXIT_SUCCESS)
}

if arguments.contains("--print-config") {
    print(configuration.summary)
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate(configuration: configuration)
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
