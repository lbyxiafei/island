import XCTest

@testable import IslandCore

final class OverlayShortcutTests: XCTestCase {
    func testCommandCommaOpensSettings() {
        XCTAssertEqual(OverlayShortcut.parse(key: ",", isCommandOnly: true), .openSettings)
    }

    /// The bug: with the Pinyin input source active, AppKit reports ⌘, with
    /// `charactersIgnoringModifiers == "，"` (fullwidth), so settings never opened.
    func testFullwidthCommaFromPinyinOpensSettings() {
        XCTAssertEqual(OverlayShortcut.parse(key: "，", isCommandOnly: true), .openSettings)
    }

    func testCommandDigitOpensThatRow() {
        XCTAssertEqual(OverlayShortcut.parse(key: "1", isCommandOnly: true), .openRow(1))
        XCTAssertEqual(OverlayShortcut.parse(key: "9", isCommandOnly: true), .openRow(9))
    }

    func testFullwidthDigitOpensThatRow() {
        XCTAssertEqual(OverlayShortcut.parse(key: "３", isCommandOnly: true), .openRow(3))
    }

    func testZeroIsNotARowShortcut() {
        XCTAssertNil(OverlayShortcut.parse(key: "0", isCommandOnly: true))
    }

    func testOtherModifiersAreIgnored() {
        XCTAssertNil(OverlayShortcut.parse(key: ",", isCommandOnly: false))
        XCTAssertNil(OverlayShortcut.parse(key: "1", isCommandOnly: false))
    }

    func testUnrelatedOrMissingKeysAreIgnored() {
        XCTAssertNil(OverlayShortcut.parse(key: "a", isCommandOnly: true))
        XCTAssertNil(OverlayShortcut.parse(key: "12", isCommandOnly: true))
        XCTAssertNil(OverlayShortcut.parse(key: "", isCommandOnly: true))
        XCTAssertNil(OverlayShortcut.parse(key: nil, isCommandOnly: true))
    }
}
