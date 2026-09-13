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

    func testStoredSettingWinsOverEnvironment() throws {
        let configuration = HotkeyConfiguration.resolve("cmd+shift+k", stored: "cmd+opt+j")

        XCTAssertEqual(configuration.spec, try HotkeySpec.parse("cmd+opt+j"))
        XCTAssertEqual(configuration.source, .menu)
        XCTAssertFalse(configuration.usedFallback)
    }

    func testEnvironmentIsReportedAsSourceWhenNothingIsStored() throws {
        let configuration = HotkeyConfiguration.resolve("cmd+shift+k", stored: nil)

        XCTAssertEqual(configuration.source, .environment)
    }

    func testBuiltInDefaultIsReportedWhenNothingIsConfigured() {
        let configuration = HotkeyConfiguration.resolve(nil, stored: nil)

        XCTAssertEqual(configuration.source, .builtInDefault)
    }

    /// A bad stored value must not brick the hotkey: it falls through to the
    /// environment, and the fallback is reported.
    func testUnusableStoredValueFallsThroughToEnvironment() throws {
        let configuration = HotkeyConfiguration.resolve("cmd+shift+k", stored: "hyper+,")

        XCTAssertEqual(configuration.spec, try HotkeySpec.parse("cmd+shift+k"))
        XCTAssertEqual(configuration.source, .environment)
        XCTAssertTrue(configuration.usedFallback)
    }

    func testUnusableStoredAndEnvironmentValuesFallBackToBuiltInDefault() {
        let configuration = HotkeyConfiguration.resolve("nope", stored: "also-nope")

        XCTAssertEqual(configuration.spec, HotkeyConfiguration.fallbackSpec)
        XCTAssertEqual(configuration.source, .builtInDefault)
        XCTAssertTrue(configuration.usedFallback)
    }
}
