import XCTest

@testable import IslandCore

final class RowHotkeysTests: XCTestCase {
    func testDefaultsToControlCommandDigits() {
        let hotkeys = RowHotkeys()
        XCTAssertTrue(hotkeys.isEnabled)
        XCTAssertEqual(hotkeys.modifiers, [.control, .command])
        XCTAssertEqual(hotkeys.symbols, "⌃⌘")
    }

    func testBindsDigitsOneToNine() throws {
        let bindings = RowHotkeys().bindings(avoiding: nil)
        XCTAssertEqual(bindings.map(\.row), Array(1...9))
        XCTAssertEqual(bindings[0].spec, try HotkeySpec.parse("ctrl+cmd+1"))
        XCTAssertEqual(bindings[8].spec, try HotkeySpec.parse("ctrl+cmd+9"))
    }

    func testSkipsTheDigitTheSummonHotkeyAlreadyTakes() throws {
        let summon = try HotkeySpec.parse("ctrl+cmd+3")
        let hotkeys = RowHotkeys()
        XCTAssertEqual(hotkeys.bindings(avoiding: summon).map(\.row), [1, 2, 4, 5, 6, 7, 8, 9])
        XCTAssertNil(hotkeys.label(row: 3, avoiding: summon))
        XCTAssertEqual(hotkeys.label(row: 4, avoiding: summon), "⌃⌘4")
    }

    func testSwitchedOffBindsNothingAndLabelsNothing() {
        let off = RowHotkeys(isEnabled: false)
        XCTAssertTrue(off.bindings(avoiding: nil).isEmpty)
        XCTAssertNil(off.label(row: 1, avoiding: nil))
    }

    func testLabelsOnlyRowsADigitReaches() {
        let hotkeys = RowHotkeys(modifiers: [.option, .command])
        XCTAssertEqual(hotkeys.label(row: 1, avoiding: nil), "⌥⌘1")
        XCTAssertEqual(hotkeys.label(row: 9, avoiding: nil), "⌥⌘9")
        XCTAssertNil(hotkeys.label(row: 0, avoiding: nil))
        XCTAssertNil(hotkeys.label(row: 10, avoiding: nil))
    }

    func testLabelsMapEachListedTaskToItsKey() {
        let labels = RowHotkeys().labels(forRows: ["a", "b", "c"], avoiding: nil)
        XCTAssertEqual(labels, ["a": "⌃⌘1", "b": "⌃⌘2", "c": "⌃⌘3"])
    }

    func testOnlyPresetsWithTwoOrMoreModifiersAreOffered() {
        // A single ⌘ or ⌃ plus a digit would steal tab switching and Spaces.
        XCTAssertTrue(RowHotkeys.presets.allSatisfy { $0.count >= 2 })
        XCTAssertEqual(RowHotkeys.presets.first, [.control, .command])
    }

    func testStoreRoundTripsAndFallsBack() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "row-hotkeys-\(UUID().uuidString)"))
        let store = UserDefaultsRowHotkeyStore(defaults: defaults)
        XCTAssertEqual(store.load(), RowHotkeys())

        store.save(RowHotkeys(isEnabled: false, modifiers: [.option, .command]))
        XCTAssertEqual(store.load(), RowHotkeys(isEnabled: false, modifiers: [.option, .command]))

        defaults.set("bogus", forKey: UserDefaultsRowHotkeyStore.modifiersKey)
        XCTAssertEqual(store.load().modifiers, [.control, .command])
        defaults.set("cmd", forKey: UserDefaultsRowHotkeyStore.modifiersKey)
        XCTAssertEqual(store.load().modifiers, [.control, .command])
    }
}
