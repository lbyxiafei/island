import Foundation
import IslandCore

/// Everything the app reads from the environment and from what the user set in
/// the app, resolved once at startup.
struct ResolvedConfiguration {
    static let hotkeyEnvironmentKey = "ISLAND_HOTKEY"
    static let durationEnvironmentKey = "ISLAND_OVERLAY_SECONDS"

    let hotkey: HotkeyConfiguration
    let duration: OverlayDuration

    init(environment: [String: String], store: HotkeyStoring = UserDefaultsHotkeyStore()) {
        hotkey = HotkeyConfiguration.resolve(
            environment[Self.hotkeyEnvironmentKey],
            stored: store.loadHotkeyText()
        )
        duration = OverlayDuration.resolve(environment[Self.durationEnvironmentKey])
    }

    var summary: String {
        var lines = [
            "hotkey            \(hotkey.spec.displayString)  (\(sourceNote))",
            "overlay duration  \(Self.secondsText(duration.seconds))s",
        ]
        if hotkey.usedFallback {
            lines.append(
                "warning           an unusable hotkey was ignored; using \(hotkey.spec.specText)"
            )
        }
        if duration.usedFallback {
            lines.append(
                "warning           \(Self.durationEnvironmentKey) unusable; using \(Self.secondsText(OverlayDuration.fallbackSeconds))s"
            )
        }
        return lines.joined(separator: "\n")
    }

    private var sourceNote: String {
        switch hotkey.source {
        case .menu: return "set in island"
        case .environment: return "from \(Self.hotkeyEnvironmentKey)"
        case .builtInDefault: return "default"
        }
    }

    /// `5` instead of `5.0`; `2.5` stays `2.5`.
    static func secondsText(_ seconds: TimeInterval) -> String {
        String(format: "%g", seconds)
    }
}
