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
        let seconds = String(format: "%g", duration.seconds)
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
                "warning           \(Self.durationEnvironmentKey) unusable; using \(String(format: "%g", OverlayDuration.fallbackSeconds))s"
            )
        }
        return lines.joined(separator: "\n")
    }
}
