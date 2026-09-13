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

        The app has no Dock icon and no menu; stop it with Ctrl-C when started
        from a terminal, or `pkill -x Island` when started with `open`.
        """
    )
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
