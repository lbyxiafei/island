import Foundation

/// Registers and unregisters the system-wide hotkey. Implemented by the app with
/// Carbon; faked in tests.
public protocol HotkeyRegistering {
    func register(_ spec: HotkeySpec) throws
    func unregister()
}

/// Remembers the hotkey the user picked.
public protocol HotkeyStoring {
    func loadHotkeyText() -> String?
    func saveHotkeyText(_ text: String?)
}

public enum HotkeyApplyOutcome: Equatable, Sendable {
    case applied(HotkeySpec)
    /// The text could not be parsed; nothing was changed.
    case invalidText(HotkeySpecError)
    /// The OS refused the swap; the previous hotkey was put back.
    case registrationFailed(String)
}

/// Applies hotkey changes from the app's settings UI.
///
/// The invariant that matters: **the app never ends up without a working
/// hotkey**. A failed swap restores the previous one, and a rejected text never
/// touches the registration or the stored value.
public final class HotkeySettingsCoordinator {
    public private(set) var current: HotkeySpec

    private let store: HotkeyStoring
    private let registrar: HotkeyRegistering

    public init(current: HotkeySpec, store: HotkeyStoring, registrar: HotkeyRegistering) {
        self.current = current
        self.store = store
        self.registrar = registrar
    }

    public func apply(_ text: String) -> HotkeyApplyOutcome {
        let spec: HotkeySpec
        switch HotkeySpec.validate(text) {
        case .failure(let error):
            return .invalidText(error)
        case .success(let accepted):
            spec = accepted
        }

        if spec != current {
            registrar.unregister()
            do {
                try registrar.register(spec)
            } catch {
                // Best effort: without this the user would be left with no
                // hotkey at all, which is worse than a rejected change.
                try? registrar.register(current)
                return .registrationFailed(error.localizedDescription)
            }
            current = spec
        }

        store.saveHotkeyText(spec.specText)
        return .applied(spec)
    }
}

/// Persists the hotkey the user picked in `UserDefaults` (Foundation only, so it
/// stays usable from the logic layer and from tests).
public struct UserDefaultsHotkeyStore: HotkeyStoring {
    public static let key = "IslandHotkeyText"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadHotkeyText() -> String? {
        defaults.string(forKey: Self.key)
    }

    public func saveHotkeyText(_ text: String?) {
        if let text {
            defaults.set(text, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }
}
