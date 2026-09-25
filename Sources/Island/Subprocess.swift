import Foundation
import IslandCore

/// Runs a command and returns its stdout, or nil when it cannot be started.
/// Shared by everything in island that shells out (`ps`, `tmux`, `osascript`, …).
enum Subprocess {
    static func run(_ arguments: [String]) -> String? {
        guard let result = runWithStatus(arguments) else { return nil }
        return result.output
    }

    /// Like `run`, but also keeps the exit status and stderr.
    static func runWithStatus(_ arguments: [String]) -> (
        status: Int32, output: String, error: String
    )? {
        guard let executable = arguments.first else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(arguments.dropFirst())
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return nil
        }
        // stderr is tiny for everything island runs, so reading stdout first
        // cannot deadlock on a full stderr pipe.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }

    /// Runs AppleScript through `osascript`; the first run against an app shows
    /// macOS's automation consent prompt (NSAppleEventsUsageDescription), and
    /// blocks until the user answers — never call this on the main thread.
    static func appleScript(_ source: String) -> AppleScriptOutcome {
        guard let result = runWithStatus(["/usr/bin/osascript", "-e", source]) else {
            return .failed
        }
        return AppleScriptOutcome.classify(
            status: result.status, output: result.output, error: result.error)
    }
}
