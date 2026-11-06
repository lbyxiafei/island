import CoreGraphics
import Foundation

/// Pet mode (issue pet-mode): a small always-on-top companion that sits on the
/// desktop and, when a run finishes, shows its title in a speech bubble next to
/// itself. Everything here is the testable half; the windows live in the app.

/// The built-in looks, drawn as emoji so they need no bundled art.
public enum PetCharacter: String, CaseIterable, Sendable {
    case cat, dog, fox, penguin, whale, robot, ghost

    public var emoji: String {
        switch self {
        case .cat: return "🐱"
        case .dog: return "🐶"
        case .fox: return "🦊"
        case .penguin: return "🐧"
        case .whale: return "🐳"
        case .robot: return "🤖"
        case .ghost: return "👻"
        }
    }

    public var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What the pet looks like: a built-in character or the user's own image.
public enum PetAvatar: Equatable, Sendable {
    case builtIn(PetCharacter)
    case image(path: String)

    static let imagePrefix = "image:"

    /// Persisted form: `cat`, or `image:/path/to/file.png`.
    public var spec: String {
        switch self {
        case .builtIn(let character): return character.rawValue
        case .image(let path): return Self.imagePrefix + path
        }
    }

    public init?(spec: String) {
        if spec.hasPrefix(Self.imagePrefix) {
            let path = String(spec.dropFirst(Self.imagePrefix.count))
            guard !path.isEmpty else { return nil }
            self = .image(path: path)
        } else if let character = PetCharacter(rawValue: spec) {
            self = .builtIn(character)
        } else {
            return nil
        }
    }
}

public struct PetSettings: Equatable, Sendable {
    public static let defaultIdleOpacity = 0.4

    public var isEnabled: Bool
    public var avatar: PetAvatar
    /// How visible the pet is while nothing waits: 0 is fully transparent.
    public var idleOpacity: Double {
        didSet { idleOpacity = Self.clamped(idleOpacity) }
    }
    /// The idle bob and the hop when a run arrives.
    public var animates: Bool

    public init(
        isEnabled: Bool = false,
        avatar: PetAvatar = .builtIn(.cat),
        idleOpacity: Double = PetSettings.defaultIdleOpacity,
        animates: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.avatar = avatar
        self.idleOpacity = Self.clamped(idleOpacity)
        self.animates = animates
    }

    /// A finished run waiting, or the pointer over the pet, shows it in full.
    public func opacity(hasUnread: Bool, hovering: Bool) -> Double {
        hasUnread || hovering ? 1 : idleOpacity
    }

    private static func clamped(_ value: Double) -> Double {
        value.isNaN ? defaultIdleOpacity : min(max(value, 0), 1)
    }
}

/// Remembers the pet settings and where the user dragged the pet.
public struct UserDefaultsPetStore {
    public static let enabledKey = "IslandPetEnabled"
    public static let avatarKey = "IslandPetAvatar"
    public static let idleOpacityKey = "IslandPetIdleOpacity"
    public static let animatesKey = "IslandPetAnimates"
    public static let originKey = "IslandPetOrigin"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> PetSettings {
        let fallback = PetSettings()
        return PetSettings(
            isEnabled: defaults.object(forKey: Self.enabledKey) as? Bool ?? fallback.isEnabled,
            avatar: defaults.string(forKey: Self.avatarKey).flatMap(PetAvatar.init(spec:))
                ?? fallback.avatar,
            idleOpacity: defaults.object(forKey: Self.idleOpacityKey) as? Double
                ?? fallback.idleOpacity,
            animates: defaults.object(forKey: Self.animatesKey) as? Bool ?? fallback.animates)
    }

    public func save(_ settings: PetSettings) {
        defaults.set(settings.isEnabled, forKey: Self.enabledKey)
        defaults.set(settings.avatar.spec, forKey: Self.avatarKey)
        defaults.set(settings.idleOpacity, forKey: Self.idleOpacityKey)
        defaults.set(settings.animates, forKey: Self.animatesKey)
    }

    public func loadOrigin() -> CGPoint? {
        guard let text = defaults.string(forKey: Self.originKey) else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGPoint(x: parts[0], y: parts[1])
    }

    public func saveOrigin(_ origin: CGPoint) {
        defaults.set("\(Double(origin.x)),\(Double(origin.y))", forKey: Self.originKey)
    }
}

/// Where the pet and its bubbles go. Coordinates are AppKit screen
/// coordinates: origin at the bottom left, y growing upward.
public enum PetLayout {
    /// More than this many bubbles fold into a "+N more" chip.
    public static let bubbleLimit = 3
    public static let gap: CGFloat = 8
    public static let margin: CGFloat = 24
    /// How far a press may wander and still count as a click.
    public static let dragThreshold: CGFloat = 3

    public struct Bubbles: Equatable, Sendable {
        public let shown: [AgentInbox.Entry]
        public let overflow: Int

        public init(shown: [AgentInbox.Entry], overflow: Int) {
            self.shown = shown
            self.overflow = overflow
        }
    }

    /// Unread runs, newest first, capped at `limit`.
    public static func bubbles(for unread: [AgentInbox.Entry], limit: Int = bubbleLimit)
        -> Bubbles
    {
        let newest = unread.sorted { $0.task.completedAt > $1.task.completedAt }
        let shown = Array(newest.prefix(max(0, limit)))
        return Bubbles(shown: shown, overflow: newest.count - shown.count)
    }

    public enum Growth: Equatable, Sendable {
        case up, down
    }

    /// From the lower half the stack grows upward, from the upper half down.
    public static func growth(of pet: CGRect, in screen: CGRect) -> Growth {
        pet.midY < screen.midY ? .up : .down
    }

    /// The bubble stack beside the pet, on the side with more room, aligned
    /// with the pet's bottom (growing up) or top (growing down), kept on screen.
    public static func bubbleFrame(size: CGSize, pet: CGRect, screen: CGRect) -> CGRect {
        let x = pet.midX > screen.midX ? pet.minX - gap - size.width : pet.maxX + gap
        let y = growth(of: pet, in: screen) == .up ? pet.minY : pet.maxY - size.height
        return CGRect(
            x: max(min(x, screen.maxX - size.width), screen.minX),
            y: max(min(y, screen.maxY - size.height), screen.minY),
            width: size.width, height: size.height)
    }

    /// `newestFirst` reordered top to bottom so the newest is next to the pet.
    public static func topToBottom<T>(_ newestFirst: [T], growth: Growth) -> [T] {
        growth == .up ? newestFirst.reversed() : newestFirst
    }

    public static func defaultOrigin(size: CGSize, screen: CGRect) -> CGPoint {
        CGPoint(x: screen.maxX - margin - size.width, y: screen.minY + margin)
    }

    /// The remembered spot, nudged fully onto the screen it overlaps most; the
    /// default corner of the first screen when it overlaps none (a display
    /// was unplugged) or nothing was remembered.
    public static func origin(remembered: CGPoint?, size: CGSize, screens: [CGRect]) -> CGPoint {
        guard let first = screens.first else { return .zero }
        guard let remembered else { return defaultOrigin(size: size, screen: first) }
        let rect = CGRect(origin: remembered, size: size)
        func overlap(_ screen: CGRect) -> CGFloat {
            let common = screen.intersection(rect)
            return common.isNull ? 0 : common.width * common.height
        }
        guard let screen = screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0
        else { return defaultOrigin(size: size, screen: first) }
        return CGPoint(
            x: max(min(remembered.x, screen.maxX - size.width), screen.minX),
            y: max(min(remembered.y, screen.maxY - size.height), screen.minY))
    }

    public static func isDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        hypot(end.x - start.x, end.y - start.y) > dragThreshold
    }
}
