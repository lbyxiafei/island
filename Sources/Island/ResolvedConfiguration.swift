import Foundation
import IslandCore

/// Everything the app reads from the environment and from what the user set in
/// the app, resolved once at startup.
struct ResolvedConfiguration {
    static let hotkeyEnvironmentKey = "ISLAND_HOTKEY"
    static let durationEnvironmentKey = "ISLAND_OVERLAY_SECONDS"
    static let taskLimitEnvironmentKey = "ISLAND_TASK_LIMIT"

    let hotkey: HotkeyConfiguration
    let hotkeyEnabled: Bool
    let duration: OverlayDuration
    let taskLimit: Int

    init(environment: [String: String], store: HotkeyStoring = UserDefaultsHotkeyStore()) {
        hotkey = HotkeyConfiguration.resolve(
            environment[Self.hotkeyEnvironmentKey],
            stored: store.loadHotkeyText()
        )
        hotkeyEnabled = HotkeySettingsCoordinator.initialEnabled(stored: store.loadHotkeyEnabled())
        duration = OverlayDuration.resolve(environment[Self.durationEnvironmentKey])
        taskLimit = TaskLimit.resolve(environment[Self.taskLimitEnvironmentKey])
    }

    var summary: String {
        var lines = [
            "hotkey            \(hotkey.spec.displayString)  (\(sourceNote)\(hotkeyEnabled ? "" : ", disabled"))",
            "overlay duration  \(Self.secondsText(duration.seconds))s",
            "task limit        \(taskLimit)",
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
