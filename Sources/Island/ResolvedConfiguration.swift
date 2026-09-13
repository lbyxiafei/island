import Foundation
import IslandCore

/// Everything the app reads from the environment, resolved once at startup.
struct ResolvedConfiguration {
    static let hotkeyEnvironmentKey = "ISLAND_HOTKEY"
    static let durationEnvironmentKey = "ISLAND_OVERLAY_SECONDS"

    let hotkey: HotkeyConfiguration
    let duration: OverlayDuration

    init(environment: [String: String]) {
        hotkey = HotkeyConfiguration.resolve(environment[Self.hotkeyEnvironmentKey])
        duration = OverlayDuration.resolve(environment[Self.durationEnvironmentKey])
    }

    var summary: String {
        let seconds = Self.secondsText(duration.seconds)
        var lines = [
            "hotkey            \(hotkey.spec.displayString)",
            "overlay duration  \(seconds)s",
        ]
        if hotkey.usedFallback {
            lines.append(
                "warning           \(Self.hotkeyEnvironmentKey) unusable; using \(HotkeyConfiguration.fallbackText)"
            )
        }
        if duration.usedFallback {
            lines.append(
                "warning           \(Self.durationEnvironmentKey) unusable; using \(Self.secondsText(OverlayDuration.fallbackSeconds))s"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// `5` instead of `5.0`; `2.5` stays `2.5`.
    static func secondsText(_ seconds: TimeInterval) -> String {
        String(format: "%g", seconds)
    }
}
