import Foundation

/// The pop-up shown when a run finishes: whether it shows at all, and for how
/// long. The menu bar count is not part of it — that one always updates.
public struct PopupSettings: Equatable, Sendable {
    /// Longer than this is no longer a pop-up; settings refuses it.
    public static let maxSeconds: TimeInterval = 600

    public var isEnabled: Bool
    public var seconds: TimeInterval

    public init(isEnabled: Bool, seconds: TimeInterval) {
        self.isEnabled = isEnabled
        self.seconds = seconds
    }

    /// What the settings field accepts: a positive number of seconds.
    public static func seconds(from text: String) -> TimeInterval? {
        guard let value = TimeInterval(text.trimmingCharacters(in: .whitespaces)),
            value.isFinite, value > 0, value <= maxSeconds
        else { return nil }
        return value
    }
}

/// Remembers the pop-up settings; unset values fall back to the environment
/// (`ISLAND_OVERLAY_SECONDS`) and then to the built-in default.
public struct UserDefaultsPopupStore {
    public static let enabledKey = "IslandPopupEnabled"
    public static let secondsKey = "IslandPopupSeconds"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(fallback: OverlayDuration) -> PopupSettings {
        let stored = defaults.object(forKey: Self.secondsKey) as? Double
        let seconds = stored.flatMap { PopupSettings.seconds(from: String($0)) }
        return PopupSettings(
            isEnabled: defaults.object(forKey: Self.enabledKey) as? Bool ?? true,
            seconds: seconds ?? fallback.seconds)
    }

    public func save(_ settings: PopupSettings) {
        defaults.set(settings.isEnabled, forKey: Self.enabledKey)
        defaults.set(settings.seconds, forKey: Self.secondsKey)
    }
}
