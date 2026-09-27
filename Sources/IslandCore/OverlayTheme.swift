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

    /// The `0xRRGGBB` this color was built from, ignoring alpha.
    public var hexValue: UInt32 {
        UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8
            | UInt32((blue * 255).rounded())
    }
}

/// Everything the overlay needs to draw one theme. The shape is fixed (the
/// island capsule); themes only change colors.
public struct OverlayPalette: Equatable, Sendable {
    /// Picks the vibrancy material and the dark or light system appearance.
    public let isDark: Bool
    /// Tint drawn over the blurred background; a lower alpha lets the blur show.
    public let background: ThemeColor
    public let border: ThemeColor
    /// The theme's signature color: the header dot and the selection tint.
    public let accent: ThemeColor
    public let title: ThemeColor
    public let subtitle: ThemeColor
    /// Translucent capsule behind the selected row, plus its outline.
    public let selectionBackground: ThemeColor
    public let selectionBorder: ThemeColor
    public let keycapBackground: ThemeColor
    public let keycapText: ThemeColor
    /// Row ages and the footer.
    public let muted: ThemeColor
}

/// The overlay looks users can pick in settings.
public enum OverlayTheme: String, CaseIterable, Sendable {
    case system
    case lagoon
    case coral
    case sand
    case midnight

    public static let fallback = OverlayTheme.system

    /// Values stored by the earlier themes (before the island look).
    private static let legacy: [String: OverlayTheme] = [
        "light": .sand, "dark": .midnight, "modern-dark": .midnight, "frosty": .lagoon,
    ]

    public static func resolve(stored: String?) -> OverlayTheme {
        guard let stored else { return fallback }
        return OverlayTheme(rawValue: stored) ?? legacy[stored] ?? fallback
    }

    public var displayName: String {
        switch self {
        case .system: return "System"
        case .lagoon: return "Lagoon"
        case .coral: return "Coral"
        case .sand: return "Sand"
        case .midnight: return "Midnight"
        }
    }

    /// `system` is Sand in light mode and Lagoon in dark mode.
    public func palette(systemIsDark: Bool) -> OverlayPalette {
        switch self {
        case .system: return systemIsDark ? Self.lagoonPalette : Self.sandPalette
        case .lagoon: return Self.lagoonPalette
        case .coral: return Self.coralPalette
        case .sand: return Self.sandPalette
        case .midnight: return Self.midnightPalette
        }
    }

    /// Builds a palette around one accent; the selection is always a light
    /// tint of the accent, never a solid bar.
    private static func palette(
        isDark: Bool, background: ThemeColor, accent: UInt32, title: ThemeColor,
        subtitle: UInt32, muted: UInt32
    ) -> OverlayPalette {
        let ink: UInt32 = isDark ? 0xFFFFFF : 0x000000
        return OverlayPalette(
            isDark: isDark,
            background: background,
            border: ThemeColor(hex: ink, alpha: isDark ? 0.12 : 0.08),
            accent: ThemeColor(hex: accent),
            title: title,
            subtitle: ThemeColor(hex: subtitle),
            selectionBackground: ThemeColor(hex: accent, alpha: isDark ? 0.16 : 0.12),
            selectionBorder: ThemeColor(hex: accent, alpha: 0.45),
            keycapBackground: ThemeColor(hex: ink, alpha: isDark ? 0.1 : 0.07),
            keycapText: ThemeColor(hex: subtitle),
            muted: ThemeColor(hex: muted)
        )
    }

    /// Deep sea blue with a lagoon-teal accent.
    private static let lagoonPalette = palette(
        isDark: true, background: ThemeColor(hex: 0x071A24, alpha: 0.9), accent: 0x3DD6C8,
        title: ThemeColor(hex: 0xF2FBFC), subtitle: 0x93B4BF, muted: 0x6A8C98)

    /// Warm dusk red with a coral accent.
    private static let coralPalette = palette(
        isDark: true, background: ThemeColor(hex: 0x241012, alpha: 0.9), accent: 0xFF7F66,
        title: ThemeColor(hex: 0xFFF4F0), subtitle: 0xC9A39C, muted: 0x9A7872)

    /// Beach sand with a sea-green accent; the only light theme.
    private static let sandPalette = palette(
        isDark: false, background: ThemeColor(hex: 0xF7F1E6, alpha: 0.92), accent: 0x0F8F86,
        title: ThemeColor(hex: 0x2A251E), subtitle: 0x7B705F, muted: 0x9C9282)

    /// Near-black like the hardware Dynamic Island, periwinkle accent.
    private static let midnightPalette = palette(
        isDark: true, background: ThemeColor(hex: 0x000000, alpha: 0.95), accent: 0x9B9BFF,
        title: ThemeColor(hex: 0xF5F5F7), subtitle: 0x8E8E93, muted: 0x6C6C70)
}

/// Remembers the overlay preferences picked in settings across launches.
public struct UserDefaultsOverlayStore {
    public static let key = "IslandOverlayTheme"
    public static let hintsKey = "IslandOverlayShowsHints"

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

    /// The keyboard-mode footer (`↑↓ move · ↩ open …`); on unless switched off.
    public func loadShowsHints() -> Bool {
        defaults.object(forKey: Self.hintsKey) as? Bool ?? true
    }

    public func saveShowsHints(_ shows: Bool) {
        defaults.set(shows, forKey: Self.hintsKey)
    }
}

/// The header's status text, which replaces the old `island` label.
public enum OverlayStatus {
    public static func text(unread: Int) -> String {
        unread > 0 ? "\(unread) new" : "All caught up"
    }
}

/// Which icon a task row shows: the agent's own app when installed, else an
/// SF Symbol.
public enum AgentIcon {
    public static func bundleIDs(for agent: AgentKind) -> [String] {
        agent.profile.appBundleIDs
    }

    public static func symbolName(for agent: AgentKind) -> String {
        agent.profile.symbolName
    }
}
