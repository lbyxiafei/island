import Foundation

/// Where the effective hotkey came from, so the UI can say it out loud.
public enum HotkeySource: String, Equatable, Sendable {
    /// Chosen by the user in the app and persisted.
    case menu
    case environment
    case builtInDefault
}

/// The resolved global hotkey plus how it was decided.
///
/// Precedence: what the user set in the app > `ISLAND_HOTKEY` > the built-in
/// default. A value that cannot be parsed is skipped rather than fatal, and is
/// reported through `usedFallback` so the app can say so out loud.
public struct HotkeyConfiguration: Equatable, Sendable {
    public static let fallbackText = "cmd+ctrl+,"

    /// `try!` is safe here: `HotkeyConfigurationTests` parses `fallbackText` on
    /// every run, so an invalid literal fails the test suite, not the app.
    public static let fallbackSpec = try! HotkeySpec.parse(fallbackText)

    public let spec: HotkeySpec
    public let source: HotkeySource
    /// True when a value that was present had to be discarded.
    public let usedFallback: Bool

    public static func resolve(_ environmentText: String?, stored storedText: String? = nil)
        -> HotkeyConfiguration
    {
        let storedSpec = storedText.flatMap { try? HotkeySpec.parse($0) }
        let environmentSpec = environmentText.flatMap { try? HotkeySpec.parse($0) }
        let ignoredSomething =
            (storedText != nil && storedSpec == nil)
            || (environmentText != nil && environmentSpec == nil)

        if let storedSpec {
            return HotkeyConfiguration(
                spec: storedSpec, source: .menu, usedFallback: ignoredSomething)
        }
        if let environmentSpec {
            return HotkeyConfiguration(
                spec: environmentSpec,
                source: .environment,
                usedFallback: ignoredSomething
            )
        }
        return HotkeyConfiguration(
            spec: fallbackSpec,
            source: .builtInDefault,
            usedFallback: ignoredSomething
        )
    }
}
