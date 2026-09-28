import Foundation

/// What a report says about the machine, so the maintainer need not ask.
public struct FeedbackEnvironment: Equatable, Sendable {
    public let appVersion: String
    public let osVersion: String

    public init(appVersion: String, osVersion: String) {
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

/// A message typed into Settings → Feedback, ready to leave island by mail,
/// as a GitHub issue, or through the clipboard. There is no server: every
/// channel is opened on the user's side.
public struct FeedbackReport: Equatable, Sendable {
    public static let address = "lbyxiafei@gmail.com"
    static let issuesURL = "https://github.com/lbyxiafei/island/issues/new"
    static let titleLimit = 80

    public let message: String
    public let environment: FeedbackEnvironment

    /// Nil for a blank message: there is nothing to send.
    public init?(message: String, environment: FeedbackEnvironment) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.message = trimmed
        self.environment = environment
    }

    public var subject: String { "island feedback (\(environment.appVersion))" }

    public var body: String {
        "\(message)\n\n—\nisland \(environment.appVersion) · macOS \(environment.osVersion)"
    }

    /// The first line, cut to fit an issue title.
    public var title: String {
        let line = message.prefix(while: { !$0.isNewline })
            .trimmingCharacters(in: .whitespaces)
        guard line.count > Self.titleLimit else { return line }
        return String(line.prefix(Self.titleLimit - 1)) + "…"
    }

    public var mailURL: URL? {
        Self.url("mailto:" + Self.address, query: [("subject", subject), ("body", body)])
    }

    public var issueURL: URL? {
        Self.url(Self.issuesURL, query: [("title", title), ("body", body)])
    }

    /// For users without a mail client: everything needed to send it by hand.
    public var clipboardText: String {
        "To: \(Self.address)\nSubject: \(subject)\n\n\(body)"
    }

    /// Stricter than `URLComponents`, which leaves `+`, `&` and `=` alone —
    /// mail clients read `+` as a space and `&` as the next field. Only
    /// RFC 3986 unreserved bytes pass; everything else, UTF-8 included, is escaped.
    private static func encode(_ value: String) -> String {
        let unreserved = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        return value.utf8.map { byte in
            unreserved.contains(byte)
                ? String(UnicodeScalar(byte)) : String(format: "%%%02X", byte)
        }.joined()
    }

    private static func url(_ base: String, query: [(String, String)]) -> URL? {
        let encoded = query.map { name, value in name + "=" + encode(value) }
        return URL(string: base + "?" + encoded.joined(separator: "&"))
    }
}
