import XCTest

@testable import IslandCore

final class HotkeyConfigurationTests: XCTestCase {
    func testFallsBackToProductDefaultWhenUnset() throws {
        let configuration = HotkeyConfiguration.resolve(nil)

        XCTAssertEqual(configuration.spec, try HotkeySpec.parse("cmd+ctrl+,"))
        XCTAssertFalse(configuration.usedFallback)
    }

    func testUsesConfiguredHotkey() throws {
        let configuration = HotkeyConfiguration.resolve("cmd+shift+k")

        XCTAssertEqual(configuration.spec, try HotkeySpec.parse("cmd+shift+k"))
        XCTAssertFalse(configuration.usedFallback)
    }

    /// The app must still come up with a working hotkey when the spec is a typo,
    /// and must be able to report that it fell back.
    func testFallsBackWhenSpecCannotBeParsed() throws {
        for raw in ["", "   ", "bogus", "hyper+,", "cmd+$"] {
            let configuration = HotkeyConfiguration.resolve(raw)
            XCTAssertEqual(configuration.spec, try HotkeySpec.parse("cmd+ctrl+,"), "raw: \(raw)")
            XCTAssertTrue(configuration.usedFallback, "raw: \(raw)")
        }
    }
}
