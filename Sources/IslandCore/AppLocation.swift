import Foundation

/// Where the running bundle lives, as far as installing it goes.
public enum AppLocation: Equatable, Sendable {
    /// A stable path; the login item and a relaunch will find it again.
    case installed
    /// Gatekeeper's App Translocation: a random read-only copy that disappears
    /// once the app quits.
    case translocated
    /// Run straight from a mounted dmg; it disappears when the image is ejected.
    case diskImage

    public static func classify(bundlePath: String) -> AppLocation {
        if bundlePath.contains("/AppTranslocation/") { return .translocated }
        if bundlePath.hasPrefix("/Volumes/") { return .diskImage }
        return .installed
    }

    /// Whether island should offer to copy itself into /Applications.
    public var needsMove: Bool { self != .installed }
}

/// A process to spawn, kept as plain data so the choice of tool is tested.
public struct LaunchCommand: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
}

/// The copy-to-/Applications-and-relaunch flow, minus the file operations.
public enum MoveToApplications {
    public struct Prompt: Equatable, Sendable {
        public let message: String
        public let informativeText: String
    }

    public static let moveButton = "Move to Applications"
    public static let laterButton = "Not Now"

    public static func destination(forBundlePath bundlePath: String) -> String {
        "/Applications/" + URL(fileURLWithPath: bundlePath).lastPathComponent
    }

    public static func prompt(for location: AppLocation) -> Prompt? {
        let why: String
        switch location {
        case .installed:
            return nil
        case .translocated:
            why =
                "macOS is running island from a temporary, read-only copy because it was not moved into Applications."
        case .diskImage:
            why = "island is running from the disk image, which goes away once it is ejected."
        }
        return Prompt(
            message: "Move island to your Applications folder?",
            informativeText: why
                + " Launch at login only works from Applications. island can copy itself there and reopen."
        )
    }

    /// A copy made outside Finder keeps the dmg's quarantine flag, and a
    /// quarantined app that was not moved by Finder is translocated again.
    public static func clearQuarantineCommand(appPath: String) -> LaunchCommand {
        LaunchCommand(
            executable: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", appPath]
        )
    }

    /// Detached from this process: waits for `pid` to exit, then opens the copy.
    public static func relaunchCommand(pid: Int32, appPath: String) -> LaunchCommand {
        LaunchCommand(
            executable: "/bin/sh",
            arguments: [
                "-c",
                "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$2\"",
                "sh", String(pid), appPath,
            ]
        )
    }
}
