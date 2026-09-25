import Foundation

/// An sRGB color, kept free of AppKit so themes can be tested here.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }
}

/// Everything the overlay needs to draw one theme.
public struct OverlayPalette: Equatable, Sendable {
    /// Picks the vibrancy material and the dark or light system appearance.
    public let isDark: Bool
    /// Tint drawn over the blurred background; a low alpha lets the blur show.
    public let background: ThemeColor
    public let cornerRadius: Double
    public let borderColor: ThemeColor
    public let borderWidth: Double
    public let queryBackground: ThemeColor
    public let queryText: ThemeColor
    public let title: ThemeColor
    public let subtitle: ThemeColor
    public let selectionBackground: ThemeColor
    public let selectionTitle: ThemeColor
    public let selectionSubtitle: ThemeColor
    public let shortcut: ThemeColor
    public let hint: ThemeColor
}

/// The overlay looks users can pick in settings, modelled on Alfred's themes.
public enum OverlayTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark
    case modernDark = "modern-dark"
    case frosty

    public static let fallback = OverlayTheme.system

    public static func resolve(stored: String?) -> OverlayTheme {
        stored.flatMap(OverlayTheme.init(rawValue:)) ?? fallback
    }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .modernDark: return "Modern Dark"
        case .frosty: return "Frosty"
        }
    }

    /// `system` follows the macOS appearance; the others are fixed.
    public func palette(systemIsDark: Bool) -> OverlayPalette {
        switch self {
        case .system: return systemIsDark ? Self.darkPalette : Self.lightPalette
        case .light: return Self.lightPalette
        case .dark: return Self.darkPalette
        case .modernDark: return Self.modernDarkPalette
        case .frosty: return Self.frostyPalette
        }
    }

    private static let white = ThemeColor(hex: 0xFFFFFF)
    private static let clear = ThemeColor(hex: 0x000000, alpha: 0)

    /// Alfred: pale translucent panel, deep purple highlight.
    private static let lightPalette = OverlayPalette(
        isDark: false,
        background: ThemeColor(hex: 0xECEBEB, alpha: 0.88),
        cornerRadius: 10,
        borderColor: clear,
        borderWidth: 0,
        queryBackground: ThemeColor(hex: 0xD6CCCC, alpha: 0.8),
        queryText: ThemeColor(hex: 0x111111),
        title: ThemeColor(hex: 0x1A1A1A),
        subtitle: ThemeColor(hex: 0x6E6E6E),
        selectionBackground: ThemeColor(hex: 0x5E1D73),
        selectionTitle: white,
        selectionSubtitle: ThemeColor(hex: 0xFFFFFF, alpha: 0.85),
        shortcut: ThemeColor(hex: 0x5E1D73),
        hint: ThemeColor(hex: 0x8A8A8A)
    )

    /// Alfred Dark: near-black panel, teal highlight.
    private static let darkPalette = OverlayPalette(
        isDark: true,
        background: ThemeColor(hex: 0x100808, alpha: 0.92),
        cornerRadius: 10,
        borderColor: clear,
        borderWidth: 0,
        queryBackground: ThemeColor(hex: 0x241010, alpha: 0.8),
        queryText: white,
        title: ThemeColor(hex: 0xF2F2F2),
        subtitle: ThemeColor(hex: 0xA6A6A6),
        selectionBackground: ThemeColor(hex: 0x367F87),
        selectionTitle: white,
        selectionSubtitle: ThemeColor(hex: 0xFFFFFF, alpha: 0.85),
        shortcut: ThemeColor(hex: 0xA6A6A6),
        hint: ThemeColor(hex: 0x7A7A7A)
    )

    /// Alfred Modern Dark: the dark look with rounder corners and an outline.
    private static let modernDarkPalette = OverlayPalette(
        isDark: true,
        background: ThemeColor(hex: 0x14110F, alpha: 0.9),
        cornerRadius: 18,
        borderColor: ThemeColor(hex: 0x000000, alpha: 0.9),
        borderWidth: 2,
        queryBackground: ThemeColor(hex: 0x3A1616, alpha: 0.55),
        queryText: white,
        title: ThemeColor(hex: 0xF2F2F2),
        subtitle: ThemeColor(hex: 0xB3B3B3),
        selectionBackground: ThemeColor(hex: 0x367F87),
        selectionTitle: white,
        selectionSubtitle: ThemeColor(hex: 0xFFFFFF, alpha: 0.85),
        shortcut: ThemeColor(hex: 0xB3B3B3),
        hint: ThemeColor(hex: 0x808080)
    )

    /// island's original HUD look: mostly blur, a faint teal tint.
    private static let frostyPalette = OverlayPalette(
        isDark: true,
        background: ThemeColor(hex: 0x1E3A40, alpha: 0.25),
        cornerRadius: 18,
        borderColor: ThemeColor(hex: 0xFFFFFF, alpha: 0.12),
        borderWidth: 1,
        queryBackground: ThemeColor(hex: 0xFFFFFF, alpha: 0.08),
        queryText: white,
        title: ThemeColor(hex: 0xFFFFFF, alpha: 0.95),
        subtitle: ThemeColor(hex: 0xFFFFFF, alpha: 0.6),
        selectionBackground: ThemeColor(hex: 0x7FD1D8, alpha: 0.3),
        selectionTitle: white,
        selectionSubtitle: ThemeColor(hex: 0xFFFFFF, alpha: 0.8),
        shortcut: ThemeColor(hex: 0xFFFFFF, alpha: 0.55),
        hint: ThemeColor(hex: 0xFFFFFF, alpha: 0.4)
    )
}

/// Remembers the picked theme across launches.
public struct UserDefaultsThemeStore {
    public static let key = "IslandOverlayTheme"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> OverlayTheme {
        OverlayTheme.resolve(stored: defaults.string(forKey: Self.key))
    }

    public func save(_ theme: OverlayTheme) {
        defaults.set(theme.rawValue, forKey: Self.key)
    }
}

/// Which icon a task row shows: the agent's own app when installed, else an
/// SF Symbol.
public enum AgentIcon {
    public static func bundleIDs(for agent: AgentKind) -> [String] {
        switch agent {
        case .claudeCode: return ["com.anthropic.claudefordesktop"]
        case .codex: return ["com.openai.codex"]
        case .pi: return []
        }
    }

    public static func symbolName(for agent: AgentKind) -> String {
        switch agent {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .pi: return "terminal"
        }
    }
}
