import Foundation

/// Where island's log goes when nobody is watching stderr. Launched at login
/// (or with `open`), stderr is /dev/null, so without this a bug seen only in
/// that instance leaves no trace (issue `terminal-reopen-stops-working`).
public enum LogFile {
    /// One previous file is kept, so the log stays under twice this size.
    public static let maxBytes = 1_000_000

    public static func url(
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        userHome.appendingPathComponent("Library/Logs/island.log")
    }

    public static func previousURL(
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        userHome.appendingPathComponent("Library/Logs/island.log.1")
    }

    /// Checked once at launch; `size` is nil when there is no file yet.
    public static func shouldRotate(size: Int?) -> Bool {
        (size ?? 0) >= maxBytes
    }

    /// A terminal run keeps logging to the terminal.
    public static func redirectsStderr(stderrIsTerminal: Bool) -> Bool {
        !stderrIsTerminal
    }

    public static func line(
        _ message: String, at date: Date = Date(), timeZone: TimeZone = .current
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return "\(formatter.string(from: date)) [island] \(message)\n"
    }
}
