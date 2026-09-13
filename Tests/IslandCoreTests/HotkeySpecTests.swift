import XCTest

@testable import IslandCore

final class HotkeySpecTests: XCTestCase {
    func testParsesModifiersAndKeyIntoDisplayString() throws {
        let spec = try HotkeySpec.parse("cmd+ctrl+,")

        XCTAssertEqual(spec.displayString, "⌃⌘,")
    }

    /// The app hands these straight to Carbon's `RegisterEventHotKey`.
    func testExposesVirtualKeyCodeAndModifiers() throws {
        let spec = try HotkeySpec.parse("cmd+ctrl+,")

        XCTAssertEqual(spec.keyCode, 43)
        XCTAssertEqual(spec.modifiers, [.command, .control])
    }

    func testToleratesWhitespaceAndCasing() throws {
        let spec = try HotkeySpec.parse("  Cmd + CONTROL + ,  ")

        XCTAssertEqual(spec.displayString, "⌃⌘,")
    }

    func testRendersLetterKeysUppercased() throws {
        let spec = try HotkeySpec.parse("cmd+shift+k")

        XCTAssertEqual(spec.displayString, "⇧⌘K")
        XCTAssertEqual(spec.keyCode, 40)
    }

    func testRendersNamedKeysCapitalized() throws {
        let spec = try HotkeySpec.parse("cmd+ctrl+space")

        XCTAssertEqual(spec.displayString, "⌃⌘Space")
        XCTAssertEqual(spec.keyCode, 49)
    }

    /// Both the macOS symbols and the latin names people actually type with.
    func testAcceptsEveryModifierAlias() throws {
        for text in ["⌃+⌥+⇧+⌘+,", "command+control+option+shift+,", "cmd+ctrl+alt+shift+,"] {
            XCTAssertEqual(try HotkeySpec.parse(text).displayString, "⌃⌥⇧⌘,", "spec: \(text)")
        }
    }

    func testRejectsEmptySpec() {
        XCTAssertThrowsError(try HotkeySpec.parse("   ")) { error in
            XCTAssertEqual(error as? HotkeySpecError, .empty)
        }
    }

    /// A bare key would swallow that key system-wide, so every hotkey needs a modifier.
    func testRejectsSpecWithoutModifier() {
        XCTAssertThrowsError(try HotkeySpec.parse("k")) { error in
            XCTAssertEqual(error as? HotkeySpecError, .missingModifier)
        }
    }

    func testReportsUnknownModifier() {
        XCTAssertThrowsError(try HotkeySpec.parse("cmd+hyper+,")) { error in
            XCTAssertEqual(error as? HotkeySpecError, .unknownModifier("hyper"))
        }
    }

    func testReportsUnknownKey() {
        XCTAssertThrowsError(try HotkeySpec.parse("cmd+$")) { error in
            XCTAssertEqual(error as? HotkeySpecError, .unknownKey("$"))
        }
    }
}
