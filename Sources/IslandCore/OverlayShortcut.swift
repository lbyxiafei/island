import Foundation

/// The ⌘-shortcuts the keyboard-mode overlay understands: ⌘, opens settings,
/// ⌘1…⌘9 open the row with that keycap.
///
/// `key` is the event's `charactersIgnoringModifiers`. CJK input sources such
/// as Pinyin report fullwidth characters there (⌘, arrives as "，"), so the key
/// is folded to its halfwidth form before matching.
public enum OverlayShortcut: Equatable, Sendable {
    case openSettings
    case openRow(Int)

    public static func parse(key: String?, isCommandOnly: Bool) -> OverlayShortcut? {
        guard isCommandOnly,
            let key = key?.applyingTransform(.fullwidthToHalfwidth, reverse: false)
        else { return nil }
        if key == "," { return .openSettings }
        guard key.count == 1, let digit = Int(key), (1...9).contains(digit) else { return nil }
        return .openRow(digit)
    }
}
