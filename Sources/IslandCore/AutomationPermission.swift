import Foundation

/// What one `osascript` run came back with.
public enum AppleScriptOutcome: Equatable, Sendable {
    case output(String)
    /// macOS refused the Apple event: the user declined island in Privacy &
    /// Security → Automation (-1743), or consent could not be asked (-1744).
    case notAuthorized
    case failed

    public static func classify(status: Int32, output: String, error: String) -> AppleScriptOutcome
    {
        if status == 0 {
            return .output(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if error.contains("(-1743)") || error.contains("(-1744)") {
            return .notAuthorized
        }
        return .failed
    }

    /// The script's result, or "" when it did not run.
    public var text: String {
        if case .output(let text) = self { return text }
        return ""
    }
}

/// Whether island was allowed to script a terminal app on the last try.
public struct AutomationCheck: Equatable, Sendable {
    public let appName: String
    public let authorized: Bool

    public init(appName: String, authorized: Bool) {
        self.appName = appName
        self.authorized = authorized
    }
}

/// Apps that refused automation, surfaced in the menu so a user who clicked
/// "Don't Allow" once knows why tabs stopped being focused and where to fix it.
public struct AutomationDenials: Equatable, Sendable {
    public static let settingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"

    public private(set) var appNames: [String] = []

    public init() {}

    public mutating func record(_ check: AutomationCheck) {
        if check.authorized {
            appNames.removeAll { $0 == check.appName }
        } else if !appNames.contains(check.appName) {
            appNames.append(check.appName)
        }
    }

    public var menuTitle: String? {
        appNames.isEmpty ? nil : "Allow island to control \(appNames.joined(separator: ", "))…"
    }
}
