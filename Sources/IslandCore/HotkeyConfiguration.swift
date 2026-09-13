import Foundation

/// The resolved global hotkey, plus whether the configured value had to be
/// discarded. Same contract as `OverlayDuration`: unset is normal, unusable is
/// reported so the app can say so out loud.
public struct HotkeyConfiguration: Equatable, Sendable {
    public static let fallbackText = "cmd+ctrl+,"

    /// `try!` is safe here: `HotkeyConfigurationTests` parses `fallbackText` on
    /// every run, so an invalid literal fails the test suite, not the app.
    public static let fallbackSpec = try! HotkeySpec.parse(fallbackText)

    public let spec: HotkeySpec
    public let usedFallback: Bool

    public static func resolve(_ raw: String?) -> HotkeyConfiguration {
        guard let raw else {
            return HotkeyConfiguration(spec: fallbackSpec, usedFallback: false)
        }

        guard let spec = try? HotkeySpec.parse(raw) else {
            return HotkeyConfiguration(spec: fallbackSpec, usedFallback: true)
        }

        return HotkeyConfiguration(spec: spec, usedFallback: false)
    }
}
