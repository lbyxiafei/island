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

    // MARK: - Enable / disable (PLAN § Scope #5)

    func testEnabledByDefaultWhenNothingWasStored() {
        XCTAssertTrue(HotkeySettingsCoordinator.initialEnabled(stored: nil))
        XCTAssertFalse(HotkeySettingsCoordinator.initialEnabled(stored: false))
        XCTAssertTrue(HotkeySettingsCoordinator.initialEnabled(stored: true))
    }

    func testStartRegistersWhenEnabled() throws {
        let registrar = FakeRegistrar()
        let spec = try HotkeySpec.parse("cmd+ctrl+,")
        let settings = HotkeySettingsCoordinator(
            current: spec, isEnabled: true, store: FakeStore(), registrar: registrar)

        try settings.start()

        XCTAssertEqual(registrar.registered, [spec])
    }

    func testStartIsANoOpWhenDisabled() throws {
        let registrar = FakeRegistrar()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            isEnabled: false,
            store: FakeStore(),
            registrar: registrar
        )

        try settings.start()

        XCTAssertTrue(registrar.registered.isEmpty)
    }

    func testDisablingUnregistersAndPersistsTheChoice() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            isEnabled: true,
            store: store,
            registrar: registrar
        )

        let outcome = settings.setEnabled(false)

        XCTAssertEqual(outcome, .disabled)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(registrar.unregisterCount, 1)
        XCTAssertEqual(store.savedEnabled, false)
    }

    func testReenablingRegistersTheKeptHotkey() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let spec = try HotkeySpec.parse("cmd+ctrl+,")
        let settings = HotkeySettingsCoordinator(
            current: spec, isEnabled: false, store: store, registrar: registrar)

        let outcome = settings.setEnabled(true)

        XCTAssertEqual(outcome, .enabled(spec))
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(registrar.registered, [spec])
        XCTAssertEqual(store.savedEnabled, true)
    }

    /// A refused re-enable must leave the app disabled instead of pretending.
    func testReenablingFailureStaysDisabledAndReportsTheReason() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let spec = try HotkeySpec.parse("cmd+ctrl+,")
        registrar.rejects = spec
        let settings = HotkeySettingsCoordinator(
            current: spec, isEnabled: false, store: store, registrar: registrar)

        let outcome = settings.setEnabled(true)

        XCTAssertEqual(outcome, .registrationFailed("hotkey is taken"))
        XCTAssertFalse(settings.isEnabled)
        XCTAssertTrue(registrar.registered.isEmpty)
        XCTAssertNil(store.savedEnabled)
    }

    /// While disabled the settings window can still record a key; it must be
    /// remembered without touching the OS registration.
    func testApplyingWhileDisabledStoresWithoutRegistering() throws {
        let registrar = FakeRegistrar()
        let store = FakeStore()
        let settings = HotkeySettingsCoordinator(
            current: try HotkeySpec.parse("cmd+ctrl+,"),
            isEnabled: false,
            store: store,
            registrar: registrar
        )

        let outcome = settings.apply("cmd+shift+k")

        XCTAssertEqual(outcome, .applied(try HotkeySpec.parse("cmd+shift+k")))
        XCTAssertEqual(settings.current, try HotkeySpec.parse("cmd+shift+k"))
        XCTAssertTrue(registrar.registered.isEmpty)
        XCTAssertEqual(registrar.unregisterCount, 0)
        XCTAssertEqual(store.saved, "shift+cmd+k")
        XCTAssertFalse(settings.isEnabled)
    }

    /// Toggling to the state you are already in must not re-register or write.
    func testSettingTheSameEnabledStateIsANoOp() throws {
        let spec = try HotkeySpec.parse("cmd+ctrl+,")
        let registrar = FakeRegistrar()
        let store = FakeStore()

        let alreadyOn = HotkeySettingsCoordinator(
            current: spec, isEnabled: true, store: store, registrar: registrar)
        XCTAssertEqual(alreadyOn.setEnabled(true), .enabled(spec))
        XCTAssertTrue(registrar.registered.isEmpty)
        XCTAssertEqual(registrar.unregisterCount, 0)
        XCTAssertNil(store.savedEnabled)

        let alreadyOff = HotkeySettingsCoordinator(
            current: spec, isEnabled: false, store: store, registrar: registrar)
        XCTAssertEqual(alreadyOff.setEnabled(false), .disabled)
        XCTAssertEqual(registrar.unregisterCount, 0)
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
    var savedEnabled: Bool?
    private var text: String?

    func loadHotkeyText() -> String? { text }

    func saveHotkeyText(_ text: String?) {
        self.text = text
        saved = text
    }

    func loadHotkeyEnabled() -> Bool? { savedEnabled }

    func saveHotkeyEnabled(_ enabled: Bool) {
        savedEnabled = enabled
    }
}
