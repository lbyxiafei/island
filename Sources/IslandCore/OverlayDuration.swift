import Foundation

/// How long the overlay stays on screen after it pops up.
///
/// The value is read from the environment so the POC can be exercised without a
/// rebuild: `ISLAND_OVERLAY_SECONDS=2 ./Island.app/Contents/MacOS/Island`.
public struct OverlayDuration: Equatable, Sendable {
    public static let fallbackSeconds: TimeInterval = 5

    public let seconds: TimeInterval
    /// True when a configured value was unusable and the fallback was applied,
    /// so the caller can warn instead of silently ignoring the typo.
    public let usedFallback: Bool

    /// Unset means "use the default"; a present-but-unusable value is reported
    /// as a fallback so it does not go unnoticed.
    public static func resolve(_ raw: String?) -> OverlayDuration {
        guard let raw else {
            return OverlayDuration(seconds: fallbackSeconds, usedFallback: false)
        }

        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let seconds = TimeInterval(trimmed), seconds.isFinite, seconds > 0 {
            return OverlayDuration(seconds: seconds, usedFallback: false)
        }

        return OverlayDuration(seconds: fallbackSeconds, usedFallback: true)
    }
}
