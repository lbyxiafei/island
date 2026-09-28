import XCTest

@testable import IslandCore

final class FeedbackTests: XCTestCase {
    private let environment = FeedbackEnvironment(appVersion: "0.2.0", osVersion: "26.6.2")

    func testBlankMessagesAreNotSendable() {
        XCTAssertNil(FeedbackReport(message: "  \n\t ", environment: environment))
        XCTAssertNotNil(FeedbackReport(message: " hi ", environment: environment))
    }

    func testBodyKeepsTheMessageAndAddsTheEnvironment() throws {
        let report = try XCTUnwrap(
            FeedbackReport(message: "  The overlay flickers.\n", environment: environment))

        XCTAssertEqual(
            report.body, "The overlay flickers.\n\n—\nisland 0.2.0 · macOS 26.6.2")
    }

    func testTitleIsTheFirstLineShortened() throws {
        let long = String(repeating: "a", count: 100)
        let report = try XCTUnwrap(
            FeedbackReport(message: "\(long)\nsecond line", environment: environment))
        let short = try XCTUnwrap(
            FeedbackReport(message: "\n  Crash on launch  \nmore", environment: environment))

        XCTAssertEqual(report.title, String(repeating: "a", count: 79) + "…")
        XCTAssertEqual(short.title, "Crash on launch")
    }

    func testMailGoesToTheMaintainerWithEverythingEncoded() throws {
        let report = try XCTUnwrap(
            FeedbackReport(message: "a & b = c + d?\n中文", environment: environment))
        let url = try XCTUnwrap(report.mailURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(components.path, FeedbackReport.address)
        XCTAssertEqual(FeedbackReport.address, "lbyxiafei@gmail.com")
        let query = try XCTUnwrap(components.percentEncodedQuery)
        // `+` and `&` inside values must not read as a space or a new field.
        XCTAssertFalse(query.contains("+"), query)
        XCTAssertEqual(query.components(separatedBy: "&").count, 2, query)
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["subject"], "island feedback (0.2.0)")
        XCTAssertEqual(items["body"], report.body)
    }

    func testIssueOpensPrefilledOnTheSourceRepo() throws {
        let report = try XCTUnwrap(
            FeedbackReport(message: "Idea: sounds", environment: environment))
        let url = try XCTUnwrap(report.issueURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/lbyxiafei/island/issues/new")
        XCTAssertEqual(items["title"], "Idea: sounds")
        XCTAssertEqual(items["body"], report.body)
    }

    func testClipboardTextNamesWhereToSendIt() throws {
        let report = try XCTUnwrap(FeedbackReport(message: "hello", environment: environment))

        XCTAssertEqual(
            report.clipboardText,
            "To: lbyxiafei@gmail.com\nSubject: island feedback (0.2.0)\n\n" + report.body)
    }
}
