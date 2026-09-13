import XCTest

@testable import IslandCore

final class UserDefaultsHotkeyStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "island.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadsNothingBeforeAnythingIsSaved() {
        let store = UserDefaultsHotkeyStore(defaults: defaults)

        XCTAssertNil(store.loadHotkeyText())
    }

    func testSavedTextSurvivesANewStoreInstance() {
        UserDefaultsHotkeyStore(defaults: defaults).saveHotkeyText("cmd+shift+k")

        XCTAssertEqual(UserDefaultsHotkeyStore(defaults: defaults).loadHotkeyText(), "cmd+shift+k")
    }

    func testSavingNothingClearsTheStoredText() {
        let store = UserDefaultsHotkeyStore(defaults: defaults)
        store.saveHotkeyText("cmd+shift+k")

        store.saveHotkeyText(nil)

        XCTAssertNil(store.loadHotkeyText())
    }
}
