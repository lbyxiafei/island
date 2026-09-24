import XCTest

@testable import IslandCore

final class OverlayToggleTests: XCTestCase {
    func testHotkeyShowsTheOverlayWhenItIsNotOnScreen() {
        XCTAssertEqual(OverlayToggle.hotkeyPress(isOverlayVisible: false), .show)
    }

    /// PLAN § Scope #5: the hotkey toggles the overlay — a second press while it
    /// is on screen must hide it instead of only resetting the auto-hide timer.
    func testHotkeyHidesTheOverlayWhenItIsAlreadyOnScreen() {
        XCTAssertEqual(OverlayToggle.hotkeyPress(isOverlayVisible: true), .hide)
    }
}
