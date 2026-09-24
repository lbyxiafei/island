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

    /// `specText` is what gets persisted, so it has to survive a round trip.
    func testSpecTextRoundTripsForEveryForm() throws {
        for text in ["cmd+ctrl+,", "⌃+⌥+⇧+⌘+,", "⌃⌥⇧⌘,", "cmd+shift+k", "command+control+space"] {
            let spec = try HotkeySpec.parse(text)
            XCTAssertEqual(try HotkeySpec.parse(spec.specText), spec, "spec: \(spec.specText)")
        }
    }

    /// The settings field shows what the menu shows, so that string has to
    /// survive being typed back in.
    func testDisplayStringRoundTrips() throws {
        for text in ["cmd+ctrl+,", "ctrl+opt+shift+cmd+,", "cmd+shift+k"] {
            let spec = try HotkeySpec.parse(text)
            XCTAssertEqual(
                try HotkeySpec.parse(spec.displayString), spec, "display: \(spec.displayString)")
        }
    }

    func testSpecTextUsesCanonicalOrderAndNames() throws {
        XCTAssertEqual(try HotkeySpec.parse("⌘+⌥+⇧+⌃+,").specText, "ctrl+opt+shift+cmd+,")
        XCTAssertEqual(try HotkeySpec.parse("cmd+ctrl+space").specText, "ctrl+cmd+space")
    }

    // MARK: - Capture (what the settings recorder hands us)

    func testCapturedBuildsSpecFromKeyCodeAndModifiers() {
        XCTAssertEqual(
            HotkeySpec.captured(keyCode: 43, modifiers: [.command, .control]),
            try? HotkeySpec.parse("cmd+ctrl+,")
        )
    }

    /// A bare key would swallow that key system-wide, so capture refuses it.
    func testCapturedRejectsAKeyWithoutModifiers() {
        XCTAssertNil(HotkeySpec.captured(keyCode: 40, modifiers: []))
    }

    func testCapturedRejectsAnUnknownKeyCode() {
        XCTAssertNil(HotkeySpec.captured(keyCode: 255, modifiers: [.command]))
    }

    /// Every bindable key must survive key-code capture; this is what keeps the
    /// reverse table honest when a key is added or removed.
    func testCapturedRoundTripsForEveryBindableKey() throws {
        let labels = [
            "a", "s", "d", "f", "h", "g", "z", "x", "c", "v", "b", "q", "w", "e", "r",
            "y", "t", "1", "2", "3", "4", "6", "5", "=", "9", "7", "-", "8", "0", "]",
            "o", "u", "[", "i", "p", "return", "l", "j", "'", "k", ";", "\\", ",",
            "/", "n", "m", ".", "tab", "space", "`", "escape",
        ]
        for label in labels {
            let spec = try HotkeySpec.parse("cmd+\(label)")
            XCTAssertEqual(
                HotkeySpec.captured(keyCode: spec.keyCode, modifiers: [.command]),
                spec,
                "key: \(label)"
            )
        }
    }
}
