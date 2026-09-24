import Foundation

/// Registers and unregisters the system-wide hotkey. Implemented by the app with
/// Carbon; faked in tests.
public protocol HotkeyRegistering {
    func register(_ spec: HotkeySpec) throws
    func unregister()
}

/// Remembers the hotkey the user picked, and whether it is switched on.
public protocol HotkeyStoring {
    func loadHotkeyText() -> String?
    func saveHotkeyText(_ text: String?)
    func loadHotkeyEnabled() -> Bool?
    func saveHotkeyEnabled(_ enabled: Bool)
}

public enum HotkeyApplyOutcome: Equatable, Sendable {
    case applied(HotkeySpec)
    /// The text could not be parsed; nothing was changed.
    case invalidText(HotkeySpecError)
    /// The OS refused the swap; the previous hotkey was put back.
    case registrationFailed(String)
}

public enum HotkeyToggleOutcome: Equatable, Sendable {
    case enabled(HotkeySpec)
    case disabled
    /// The OS refused to register the hotkey; the app stays disabled.
    case registrationFailed(String)
}

/// Applies hotkey changes from the app's settings UI.
///
/// Invariants that matter: **while enabled, the app never ends up without a
/// working hotkey**. A failed swap restores the previous one, and a rejected
/// text never touches the registration or the stored value. Disabling is an
/// explicit user choice, so it is allowed to leave the app hotkey-less.
public final class HotkeySettingsCoordinator {
    public private(set) var current: HotkeySpec
    public private(set) var isEnabled: Bool

    private let store: HotkeyStoring
    private let registrar: HotkeyRegistering

    public init(
        current: HotkeySpec,
        isEnabled: Bool = true,
        store: HotkeyStoring,
        registrar: HotkeyRegistering
    ) {
        self.current = current
        self.isEnabled = isEnabled
        self.store = store
        self.registrar = registrar
    }

    /// `nil` (nothing stored yet) means enabled — the POC ships with a hotkey on.
    public static func initialEnabled(stored: Bool?) -> Bool {
        stored ?? true
    }

    /// Registers the hotkey at launch when it is switched on. Does nothing when
    /// the user has it switched off.
    public func start() throws {
        guard isEnabled else { return }
        try registrar.register(current)
    }

    public func apply(_ text: String) -> HotkeyApplyOutcome {
        let spec: HotkeySpec
        switch HotkeySpec.validate(text) {
        case .failure(let error):
            return .invalidText(error)
        case .success(let accepted):
            spec = accepted
        }

        // While switched off the new key is only remembered, not registered.
        if isEnabled, spec != current {
            registrar.unregister()
            do {
                try registrar.register(spec)
            } catch {
                // Best effort: without this the user would be left with no
                // hotkey at all, which is worse than a rejected change.
                try? registrar.register(current)
                return .registrationFailed(error.localizedDescription)
            }
        }
        current = spec

        store.saveHotkeyText(spec.specText)
        return .applied(spec)
    }

    public func setEnabled(_ enabled: Bool) -> HotkeyToggleOutcome {
        guard enabled != isEnabled else {
            return enabled ? .enabled(current) : .disabled
        }

        if enabled {
            do {
                try registrar.register(current)
            } catch {
                return .registrationFailed(error.localizedDescription)
            }
            isEnabled = true
            store.saveHotkeyEnabled(true)
            return .enabled(current)
        }

        registrar.unregister()
        isEnabled = false
        store.saveHotkeyEnabled(false)
        return .disabled
    }
}

/// Persists the hotkey the user picked in `UserDefaults` (Foundation only, so it
/// stays usable from the logic layer and from tests).
public struct UserDefaultsHotkeyStore: HotkeyStoring {
    public static let key = "IslandHotkeyText"
    public static let enabledKey = "IslandHotkeyEnabled"

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

    public func loadHotkeyEnabled() -> Bool? {
        defaults.object(forKey: Self.enabledKey) as? Bool
    }

    public func saveHotkeyEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
    }
}
