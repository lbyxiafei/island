import Foundation
import IslandCore

/// The one place island writes its log: timestamped lines on stderr, which
/// `redirectToFileIfDetached` points at `~/Library/Logs/island.log` when no
/// terminal is attached.
enum Log {
    static func write(_ message: String) {
        FileHandle.standardError.write(Data(LogFile.line(message).utf8))
    }

    static func redirectToFileIfDetached() {
        guard LogFile.redirectsStderr(stderrIsTerminal: isatty(STDERR_FILENO) == 1) else { return }
        let url = LogFile.url()
        let manager = FileManager.default
        try? manager.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let size = (try? manager.attributesOfItem(atPath: url.path))?[.size] as? Int
        if LogFile.shouldRotate(size: size) {
            let previous = LogFile.previousURL()
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: url, to: previous)
        }
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return }
        dup2(descriptor, STDERR_FILENO)
        close(descriptor)
    }
}
