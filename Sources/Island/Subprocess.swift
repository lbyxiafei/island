import Foundation

/// Runs a command and returns its stdout, or nil when it cannot be started.
/// Shared by everything in island that shells out (`ps`, `tmux`, `osascript`, …).
enum Subprocess {
    static func run(_ arguments: [String]) -> String? {
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

    /// Runs AppleScript through `osascript`; the first run against an app shows
    /// macOS's automation consent prompt (NSAppleEventsUsageDescription).
    static func appleScript(_ source: String) -> String {
        (run(["/usr/bin/osascript", "-e", source]) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
