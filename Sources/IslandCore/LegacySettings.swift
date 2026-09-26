import Foundation

/// island shipped as `com.binyanli.island.poc` before it was signed for
/// distribution as `com.commallama.island`. UserDefaults are stored per bundle
/// id, so the first launch under the new id copies the old settings across.
public enum LegacySettings {
    public static let bundleID = "com.binyanli.island.poc"

    /// Every setting island stores; window positions and the like are left behind.
    public static let keys = [
        UserDefaultsHotkeyStore.key,
        UserDefaultsHotkeyStore.enabledKey,
        UserDefaultsOverlayStore.key,
        UserDefaultsOverlayStore.hintsKey,
    ]

    private static let doneKey = "IslandMigratedLegacySettings"

    /// Copies each setting the new bundle does not have yet, once. Returns the
    /// keys it copied.
    @discardableResult
    public static func migrate(from old: UserDefaults, to new: UserDefaults) -> [String] {
        guard !new.bool(forKey: doneKey) else { return [] }
        new.set(true, forKey: doneKey)
        var copied: [String] = []
        for key in keys where new.object(forKey: key) == nil {
            guard let value = old.object(forKey: key) else { continue }
            new.set(value, forKey: key)
            copied.append(key)
        }
        return copied
    }
}
