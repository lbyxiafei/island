import Foundation

/// Global ⌃⌘1…⌃⌘9: open the N-th row of the task list (the same row ⌘N picks
/// in the keyboard-mode overlay) without summoning the overlay first.
///
/// Only modifier pairs or triples are offered: a single ⌘ or ⌃ plus a digit
/// would take tab switching or Spaces away from every other app.
public struct RowHotkeys: Equatable, Sendable {
    public static let presets: [Set<HotkeySpec.Modifier>] = [
        [.control, .command], [.option, .command], [.control, .option],
        [.control, .option, .command],
    ]

    /// One registered key: `row` is 1-based, like the overlay's keycaps.
    public struct Binding: Equatable, Sendable {
        public let row: Int
        public let spec: HotkeySpec
    }

    public var isEnabled: Bool
    public var modifiers: Set<HotkeySpec.Modifier>

    public init(isEnabled: Bool = true, modifiers: Set<HotkeySpec.Modifier> = [.control, .command])
    {
        self.isEnabled = isEnabled
        self.modifiers = modifiers
    }

    /// e.g. `⌃⌘`, in macOS convention order.
    public var symbols: String {
        HotkeySpec.Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined()
    }

    /// What to register: rows 1…9, minus a digit the summon hotkey already holds.
    public func bindings(avoiding summon: HotkeySpec?) -> [Binding] {
        guard isEnabled else { return [] }
        return (1...9).compactMap { row in
            let label = String(row)
            let spec = HotkeySpec(
                keyLabel: label, keyCode: HotkeySpec.keyCode(for: label), modifiers: modifiers)
            return spec == summon ? nil : Binding(row: row, spec: spec)
        }
    }

    /// The key that opens `row` (1-based), e.g. `⌃⌘2`; nil when none does.
    public func label(row: Int, avoiding summon: HotkeySpec?) -> String? {
        bindings(avoiding: summon).first { $0.row == row }?.spec.displayString
    }

    /// Keys for the listed task ids, in list order (what the pet's bubbles show).
    public func labels(forRows ids: [String], avoiding summon: HotkeySpec?) -> [String: String] {
        var labels: [String: String] = [:]
        for (index, id) in ids.enumerated() {
            if let label = label(row: index + 1, avoiding: summon) { labels[id] = label }
        }
        return labels
    }
}

public struct UserDefaultsRowHotkeyStore {
    public static let enabledKey = "IslandRowHotkeysEnabled"
    /// Persisted like a spec's modifiers: `ctrl+cmd`.
    public static let modifiersKey = "IslandRowHotkeyModifiers"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> RowHotkeys {
        let fallback = RowHotkeys()
        return RowHotkeys(
            isEnabled: defaults.object(forKey: Self.enabledKey) as? Bool ?? fallback.isEnabled,
            modifiers: defaults.string(forKey: Self.modifiersKey).flatMap(Self.modifiers(from:))
                ?? fallback.modifiers)
    }

    public func save(_ hotkeys: RowHotkeys) {
        defaults.set(hotkeys.isEnabled, forKey: Self.enabledKey)
        defaults.set(
            HotkeySpec.Modifier.allCases.filter(hotkeys.modifiers.contains).map(\.specName)
                .joined(separator: "+"),
            forKey: Self.modifiersKey)
    }

    private static func modifiers(from text: String) -> Set<HotkeySpec.Modifier>? {
        let names = text.split(separator: "+").map(String.init)
        let modifiers = Set(
            names.compactMap { name in HotkeySpec.Modifier.allCases.first { $0.specName == name } })
        return modifiers.count == names.count && RowHotkeys.presets.contains(modifiers)
            ? modifiers : nil
    }
}
