import Foundation
import IslandCore

/// Runs `/usr/bin/sqlite3 -json`. Only SELECT/ATTACH statements are ever passed,
/// and `sqlite3` ships with macOS, so this adds no dependency.
///
/// Note: the Codex databases fail to open with sqlite3's `-readonly` flag on
/// this machine (the connection cannot recover the WAL), so the read-write
/// default is used with read-only queries.
struct ProcessSQLiteQuerying: SQLiteQuerying {
    private let executable = "/usr/bin/sqlite3"

    func query(database: URL, sql: String) -> String? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-json", database.path, sql]
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
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
