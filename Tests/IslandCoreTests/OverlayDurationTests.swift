import XCTest

@testable import IslandCore

final class OverlayDurationTests: XCTestCase {
    func testDefaultsToFiveSecondsWhenUnset() {
        let duration = OverlayDuration.resolve(nil)

        XCTAssertEqual(duration.seconds, 5)
        XCTAssertFalse(duration.usedFallback)
    }

    func testUsesConfiguredSeconds() {
        let duration = OverlayDuration.resolve("2.5")

        XCTAssertEqual(duration.seconds, 2.5)
        XCTAssertFalse(duration.usedFallback)
    }

    func testTrimsSurroundingWhitespace() {
        let duration = OverlayDuration.resolve(" 12 ")

        XCTAssertEqual(duration.seconds, 12)
    }

    /// A typo must not leave the overlay on screen forever or make it invisible.
    func testFallsBackWhenValueIsNotUsable() {
        for raw in ["", "   ", "abc", "0", "-3", "nan", "inf"] {
            let duration = OverlayDuration.resolve(raw)
            XCTAssertEqual(duration.seconds, 5, "raw: \(raw)")
            XCTAssertTrue(duration.usedFallback, "raw: \(raw)")
        }
    }
}
