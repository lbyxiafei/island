import XCTest

@testable import IslandCore

final class HotkeySettingsCoordinatorTests: XCTestCase {
    func testAppliesAndRegistersANewHotkey() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            store: store,
            registrar: registrar
        )

        let outcome = settings.apply("cmd+shift+k")

        XCTAssertEqual(outcome, .applied(try HotkeySpec.parse("cmd+shift+k")))
        XCTAssertEqual(settings.current, try HotkeySpec.parse("cmd+shift+k"))
        XCTAssertEqual(registrar.registered, [try HotkeySpec.parse("cmd+shift+k")])
    }

    /// What gets persisted is the canonical form, so a reload parses to the
    /// same hotkey no matter how the user typed it.
    func testPersistsCanonicalText() throws {
        let store = FakeStore()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            store: store,
            registrar: FakeRegistrar()
        )

        _ = settings.apply("  CMD + shift + K ")

        XCTAssertEqual(store.saved, "shift+cmd+k")
    }

    func testRejectsUnparsableTextWithoutTouchingAnything() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let previous = try HotkeySpec.parse("cmd+ctrl+,")
        let settings = HotkeySettingsCoordinator(
            current: previous, store: store, registrar: registrar)

        let outcome = settings.apply("hyper+,")

        XCTAssertEqual(outcome, .invalidText(.unknownModifier("hyper")))
        XCTAssertEqual(settings.current, previous)
        XCTAssertTrue(registrar.registered.isEmpty)
        XCTAssertEqual(registrar.unregisterCount, 0)
        XCTAssertNil(store.saved)
    }

    /// If the OS refuses the new hotkey, the old one must come back — otherwise
    /// the app is left with no way to summon the overlay at all.
    func testRestoresPreviousHotkeyWhenRegistrationFails() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let previous = try HotkeySpec.parse("cmd+ctrl+,")
        let rejected = try HotkeySpec.parse("cmd+shift+k")
        registrar.rejects = rejected
        let settings = HotkeySettingsCoordinator(
            current: previous, store: store, registrar: registrar)

        let outcome = settings.apply("cmd+shift+k")

        XCTAssertEqual(outcome, .registrationFailed("hotkey is taken"))
        XCTAssertEqual(registrar.attempts, [rejected, previous])
        XCTAssertEqual(registrar.registered, [previous])
        XCTAssertEqual(settings.current, previous)
        XCTAssertNil(store.saved)
    }

    func testReapplyingTheSameHotkeyDoesNotChurnTheRegistration() throws {
        let registrar = FakeRegistrar()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            store: FakeStore(),
            registrar: registrar
        )

        let outcome = settings.apply("CMD+CTRL+,")

        XCTAssertEqual(outcome, .applied(try HotkeySpec.parse("cmd+ctrl+,")))
        XCTAssertEqual(registrar.unregisterCount, 0)
        XCTAssertTrue(registrar.registered.isEmpty)
    }
}

private final class FakeRegistrar: HotkeyRegistering {
    var registered: [HotkeySpec] = []
    var attempts: [HotkeySpec] = []
    var unregisterCount = 0
    var rejects: HotkeySpec?

    func register(_ spec: HotkeySpec) throws {
        attempts.append(spec)
        if spec == rejects { throw FakeError.taken }
        registered.append(spec)
    }

    func unregister() {
        unregisterCount += 1
    }

    enum FakeError: Error, LocalizedError {
        case taken
        var errorDescription: String? { "hotkey is taken" }
    }
}

private final class FakeStore: HotkeyStoring {
    var saved: String?
    private var text: String?

    func loadHotkeyText() -> String? { text }

    func saveHotkeyText(_ text: String?) {
        self.text = text
        saved = text
    }
}
