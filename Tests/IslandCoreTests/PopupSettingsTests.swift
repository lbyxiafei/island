import XCTest

@testable import IslandCore

final class PopupSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "PopupSettingsTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testPopsUpForTheEnvironmentDurationUntilChangedInSettings() {
        let store = UserDefaultsPopupStore(defaults: defaults)
        let settings = store.load(fallback: OverlayDuration.resolve("3"))

        XCTAssertEqual(settings, PopupSettings(isEnabled: true, seconds: 3))
    }

    func testRemembersWhatSettingsPicked() {
        let store = UserDefaultsPopupStore(defaults: defaults)

        store.save(PopupSettings(isEnabled: false, seconds: 12))

        XCTAssertEqual(
            store.load(fallback: OverlayDuration.resolve(nil)),
            PopupSettings(isEnabled: false, seconds: 12))
    }

    func testIgnoresAnUnusableStoredDuration() {
        defaults.set(-1.0, forKey: UserDefaultsPopupStore.secondsKey)

        XCTAssertEqual(
            UserDefaultsPopupStore(defaults: defaults).load(
                fallback: OverlayDuration.resolve(nil)
            ).seconds,
            5)
    }

    func testParsesTheSecondsTypedIntoSettings() {
        XCTAssertEqual(PopupSettings.seconds(from: " 8 "), 8)
        XCTAssertEqual(PopupSettings.seconds(from: "2.5"), 2.5)
        XCTAssertNil(PopupSettings.seconds(from: "0"))
        XCTAssertNil(PopupSettings.seconds(from: "-2"))
        XCTAssertNil(PopupSettings.seconds(from: "soon"))
        XCTAssertNil(PopupSettings.seconds(from: "inf"))
        XCTAssertNil(PopupSettings.seconds(from: "9999"))
    }
}
