import XCTest

@testable import IslandCore

final class AccessibilityHintTests: XCTestCase {
    func testShowsOnlyWhileDeepSeekIsWatchedInstalledAndUntrusted() {
        let title = AccessibilityHint.menuTitle
        XCTAssertEqual(
            title(false, true, true), "Allow Accessibility to open DeepSeek sessions…")
        XCTAssertNil(title(true, true, true))
        XCTAssertNil(title(false, false, true))
        XCTAssertNil(title(false, true, false))
    }

    func testOpensThePrivacyPane() {
        XCTAssertEqual(
            AccessibilityHint.settingsURL,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
