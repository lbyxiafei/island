import XCTest

@testable import IslandCore

final class LogFileTests: XCTestCase {
    private let user = URL(fileURLWithPath: "/Users/someone")

    func testLivesInTheUserLogsFolder() {
        XCTAssertEqual(
            LogFile.url(userHome: user).path, "/Users/someone/Library/Logs/island.log")
    }

    func testKeepsOnePreviousFileNextToIt() {
        XCTAssertEqual(
            LogFile.previousURL(userHome: user).path,
            "/Users/someone/Library/Logs/island.log.1")
    }

    func testRotatesOnlyOnceTheFileReachesTheCap() {
        XCTAssertFalse(LogFile.shouldRotate(size: nil))
        XCTAssertFalse(LogFile.shouldRotate(size: LogFile.maxBytes - 1))
        XCTAssertTrue(LogFile.shouldRotate(size: LogFile.maxBytes))
    }

    func testStampsEachLineWithLocalTimeAndOffset() {
        let date = Date(timeIntervalSince1970: 1_790_885_131.873)
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(
            LogFile.line("tmux client /dev/ttys000 -> job:2.1", at: date, timeZone: pacific),
            "2026-10-01T13:05:31.873-07:00 [island] tmux client /dev/ttys000 -> job:2.1\n")
    }

    func testWritesToTheFileOnlyWhenStderrIsNotATerminal() {
        XCTAssertTrue(LogFile.redirectsStderr(stderrIsTerminal: false))
        XCTAssertFalse(LogFile.redirectsStderr(stderrIsTerminal: true))
    }
}
