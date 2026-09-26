import XCTest

@testable import IslandCore

final class LegacySettingsTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "island.tests.\(UUID().uuidString)"
        suites.append(suite)
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    func testCopiesTheSettingsOfTheOldBundleID() throws {
        let old = try makeDefaults()
        let new = try makeDefaults()
        old.set("ctrl+cmd+e", forKey: "IslandHotkeyText")
        old.set(false, forKey: "IslandOverlayShowsHints")
        old.set(262, forKey: "NSStatusItem Preferred Position Item-0")

        let copied = LegacySettings.migrate(from: old, to: new)

        XCTAssertEqual(copied, ["IslandHotkeyText", "IslandOverlayShowsHints"])
        XCTAssertEqual(new.string(forKey: "IslandHotkeyText"), "ctrl+cmd+e")
        XCTAssertEqual(new.object(forKey: "IslandOverlayShowsHints") as? Bool, false)
        XCTAssertNil(new.object(forKey: "NSStatusItem Preferred Position Item-0"))
    }

    func testNeverOverwritesWhatTheNewBundleAlreadyHas() throws {
        let old = try makeDefaults()
        let new = try makeDefaults()
        old.set("frosty", forKey: "IslandOverlayTheme")
        new.set("lagoon", forKey: "IslandOverlayTheme")

        XCTAssertEqual(LegacySettings.migrate(from: old, to: new), [])
        XCTAssertEqual(new.string(forKey: "IslandOverlayTheme"), "lagoon")
    }

    /// A user who later clears a setting must not get the old value back.
    func testRunsOnlyOnce() throws {
        let old = try makeDefaults()
        let new = try makeDefaults()
        old.set("ctrl+cmd+e", forKey: "IslandHotkeyText")
        _ = LegacySettings.migrate(from: old, to: new)
        new.removeObject(forKey: "IslandHotkeyText")

        XCTAssertEqual(LegacySettings.migrate(from: old, to: new), [])
        XCTAssertNil(new.string(forKey: "IslandHotkeyText"))
    }

    func testCoversEverySettingIslandStores() {
        XCTAssertEqual(
            Set(LegacySettings.keys),
            [
                UserDefaultsHotkeyStore.key, UserDefaultsHotkeyStore.enabledKey,
                UserDefaultsOverlayStore.key, UserDefaultsOverlayStore.hintsKey,
            ])
        XCTAssertEqual(LegacySettings.bundleID, "com.binyanli.island.poc")
    }
}
