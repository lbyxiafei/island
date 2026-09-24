import AppKit
import IslandCore

let arguments = Set(CommandLine.arguments.dropFirst())
let configuration = ResolvedConfiguration(environment: ProcessInfo.processInfo.environment)

if arguments.contains("--help") || arguments.contains("-h") {
    print(
        """
        island — POC overlay window summoned by a global hotkey.

        usage: Island [--print-config | --help]

        environment:
          ISLAND_HOTKEY=cmd+ctrl+,        hotkey that summons the overlay
          ISLAND_OVERLAY_SECONDS=5        how long the overlay stays on screen

        flags (login-item flags must run from inside the app bundle):
          --print-config                  resolve the environment and exit
          --scan-agents                   list completed agent tasks and exit
          --reopen-plan <pid>             print how island would reopen a task on that pid
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

if let flag = CommandLine.arguments.firstIndex(of: "--reopen-plan"),
    flag + 1 < CommandLine.arguments.count,
    let pid = Int32(CommandLine.arguments[flag + 1])
{
    let task = AgentTask(
        agent: .claudeCode,
        sessionID: "debug",
        title: "debug",
        cwd: nil,
        completedAt: Date(),
        host: .terminal(processID: pid),
        resumeCommand: "claude --resume debug"
    )
    print(AgentReopenExecutor().plan(for: task))
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
