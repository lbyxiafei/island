import Foundation

/// The directory agent sources read from (`~/.claude`, `~/.pi`, `~/.codex`, …).
/// `ISLAND_AGENT_HOME` points it elsewhere, e.g. at seeded data for a demo
/// recording that must not show the user's real sessions.
public enum AgentHome {
    public static let environmentKey = "ISLAND_AGENT_HOME"

    public static func resolve(
        _ text: String?,
        userHome: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return userHome
        }
        let path =
            text.hasPrefix("~/")
            ? userHome.path + "/" + text.dropFirst(2) : text
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
