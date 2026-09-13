import Foundation

/// A single key that a hotkey is bound to, described by the character it produces
/// on a US layout (e.g. `,`) plus its macOS virtual key code.
public struct HotkeySpec: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case control
        case option
        case shift
        case command

        /// Name used in the persisted, reparsable form of a spec.
        var specName: String {
            switch self {
            case .control: return "ctrl"
            case .option: return "opt"
            case .shift: return "shift"
            case .command: return "cmd"
            }
        }

        /// Symbols in the conventional macOS order: ⌃⌥⇧⌘.
        var symbol: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    public let keyLabel: String
    public let keyCode: UInt32
    public let modifiers: Set<Modifier>

    /// Canonical, reparsable form — what gets persisted. `displayString` is for
    /// humans and cannot be fed back to `parse`.
    public var specText: String {
        (Modifier.allCases.filter(modifiers.contains).map(\.specName) + [keyLabel])
            .joined(separator: "+")
    }

    /// e.g. `⌃⌘,` — what the user should press, in macOS convention order.
    public var displayString: String {
        Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined() + displayKeyLabel
    }

    private var displayKeyLabel: String {
        keyLabel.count == 1 ? keyLabel.uppercased() : keyLabel.capitalized
    }
}

public enum HotkeySpecError: Error, Equatable, Sendable {
    case empty
    case missingModifier
    case unknownModifier(String)
    case unknownKey(String)
}

extension HotkeySpec {
    /// Parses a spec such as `cmd+ctrl+,` or the compact `⌃⌘,` macOS shows in
    /// its own menus.
    ///
    /// Throwing adapter over `validate`, for callers that treat a bad spec as a
    /// programmer error (tests, config bootstrap).
    public static func parse(_ text: String) throws -> HotkeySpec {
        switch validate(text) {
        case .success(let spec): return spec
        case .failure(let error): throw error
        }
    }

    /// Same grammar as `parse`, but returns the failure instead of throwing it —
    /// what the settings UI needs, and free of unreachable catch branches.
    public static func validate(_ text: String) -> Result<HotkeySpec, HotkeySpecError> {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let tokens = expanded(trimmed).split(separator: "+", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        guard tokens.count >= 2 else { return .failure(.missingModifier) }

        var modifiers: Set<Modifier> = []
        for token in tokens.dropLast() {
            guard let modifier = modifierAliases[token] else {
                return .failure(.unknownModifier(token))
            }
            modifiers.insert(modifier)
        }

        // `count >= 2` above guarantees the index is in range; taking the key
        // through an index keeps this free of an unreachable nil branch.
        let keyLabel = tokens[tokens.count - 1]
        guard let keyCode = virtualKeyCodes[keyLabel] else {
            return .failure(.unknownKey(keyLabel))
        }

        return .success(HotkeySpec(keyLabel: keyLabel, keyCode: keyCode, modifiers: modifiers))
    }

    /// Turns the compact form into the explicit one: `⌃⌘,` -> `⌃+⌘+,`. Without
    /// this, the string `displayString` produces could not be fed back in.
    private static func expanded(_ text: String) -> String {
        text.map { compactModifiers.contains(String($0)) ? "+\($0)+" : String($0) }.joined()
    }

    private static let compactModifiers: Set<String> = ["⌘", "⌃", "⌥", "⇧"]

    private static let modifierAliases: [String: Modifier] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "ctrl": .control, "control": .control, "⌃": .control,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "shift": .shift, "⇧": .shift,
    ]

    /// US-layout virtual key codes (`kVK_ANSI_*` in `Carbon.HIToolbox`).
    private static let virtualKeyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "escape": 53,
    ]
}
