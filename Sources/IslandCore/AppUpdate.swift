import Foundation

/// A `major.minor.patch` release number, as `scripts/publish.sh` stamps it.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Accepts `1.2.3`, `v1.2.3` and `1.2` (patch 0); anything else is nil.
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") { trimmed.removeFirst() }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
            parts.allSatisfy({
                !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber)
            })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers.count > 2 ? numbers[2] : 0)
    }

    /// `scripts/build-app.sh` stamps local builds 0.0.0.
    public var isDevelopment: Bool { self == AppVersion(major: 0, minor: 0, patch: 0) }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// Where releases are announced: the cask in the public tap that
/// `scripts/publish.sh` rewrites on every release.
public enum UpdateSource {
    public static let cask = "lbyxiafei/tap/island"
    public static let caskURL = URL(
        string: "https://raw.githubusercontent.com/lbyxiafei/homebrew-tap/main/Casks/island.rb")!
    public static let releasesURL = URL(
        string: "https://github.com/lbyxiafei/homebrew-tap/releases/latest")!

    /// The `version "x.y.z"` stanza of a cask file.
    public static func version(fromCask text: String) -> AppVersion? {
        for line in text.split(whereSeparator: \.isNewline) {
            let words = line.trimmingCharacters(in: .whitespaces)
            guard words.hasPrefix("version ") else { continue }
            let value = words.dropFirst("version ".count)
                .trimmingCharacters(in: .whitespaces)
            guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
                return nil
            }
            return AppVersion(String(value.dropFirst().dropLast()))
        }
        return nil
    }
}

/// What Settings → Updates and the menu say about the running version.
public enum UpdateStatus: Equatable, Sendable {
    case checking
    /// The last check failed (offline, GitHub down); stays quiet.
    case unknown
    case upToDate
    case available(AppVersion)
    /// A local 0.0.0 build: never asks to upgrade.
    case development

    public static func resolve(current: AppVersion, latest: AppVersion?) -> UpdateStatus {
        if current.isDevelopment { return .development }
        guard let latest else { return .unknown }
        return latest > current ? .available(latest) : .upToDate
    }

    /// Whether the Updates tab and the menu should draw the user's eye.
    public var needsAttention: Bool {
        if case .available = self { return true }
        return false
    }

    public var tabLabel: String { needsAttention ? "Updates 🔴" : "Updates" }

    public func summary(current: AppVersion) -> String {
        switch self {
        case .checking:
            return "Checking for updates…"
        case .unknown:
            return "Could not check for updates (you have \(current))."
        case .upToDate:
            return "island \(current) is up to date."
        case .available(let latest):
            return "island \(latest) is available — you have \(current)."
        case .development:
            return "This is a development build (\(current)); install with Homebrew to get updates."
        }
    }
}

/// How an available update gets installed.
public enum UpgradeMethod: Equatable, Sendable {
    /// Installed with `brew install --cask`: upgrade in place, then relaunch.
    case brew(executable: String)
    /// Installed from a dmg (or without brew): open the release page.
    case download

    /// Apple silicon prefix first, then Intel.
    static let prefixes = ["/opt/homebrew", "/usr/local"]

    public static func detect(fileExists: (String) -> Bool) -> UpgradeMethod {
        for prefix in prefixes
        where fileExists(prefix + "/bin/brew") && fileExists(prefix + "/Caskroom/island") {
            return .brew(executable: prefix + "/bin/brew")
        }
        return .download
    }

    public func buttonTitle(for version: AppVersion) -> String {
        switch self {
        case .brew: return "Upgrade to \(version) & Relaunch"
        case .download: return "Download \(version)…"
        }
    }

    /// Detached from island: waits for `pid` to exit (so the cask's `quit`
    /// step finds nothing running), upgrades, and reopens island whether or
    /// not brew succeeded, logging the exit status for the next launch.
    public static func upgradeCommand(pid: Int32, brew: String, logPath: String) -> LaunchCommand {
        let script = [
            "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done",
            "{ date; \"$2\" update && \"$2\" upgrade --cask \"$3\"; } >>\"$4\" 2>&1",
            "echo \"\(UpgradeLog.resultPrefix)$?\" >>\"$4\"",
            "exec /usr/bin/open -b \"$5\"",
        ].joined(separator: "; ")
        return LaunchCommand(
            executable: "/bin/sh",
            arguments: [
                "-c", script, "sh", String(pid), brew, UpdateSource.cask, logPath,
                "com.commallama.island",
            ]
        )
    }
}

/// The log the detached upgrade appends to.
public enum UpgradeLog {
    public static let resultPrefix = "island-upgrade: exit "

    /// The exit status of the most recent upgrade, if the log records one.
    public static func lastExitStatus(in log: String) -> Int32? {
        guard
            let line = log.split(whereSeparator: \.isNewline).last(where: {
                $0.hasPrefix(resultPrefix)
            })
        else { return nil }
        return Int32(line.dropFirst(resultPrefix.count))
    }
}

/// Remembers whether island checks for updates on its own.
public struct UserDefaultsUpdateStore {
    public static let autoCheckKey = "IslandAutoCheckUpdates"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadAutoCheck() -> Bool {
        defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
    }

    public func saveAutoCheck(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.autoCheckKey)
    }
}
