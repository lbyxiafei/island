import XCTest

@testable import IslandCore

final class AppleScriptOutcomeTests: XCTestCase {
    func testSuccessKeepsTheTrimmedOutput() {
        XCTAssertEqual(
            AppleScriptOutcome.classify(status: 0, output: " 37C0\n", error: ""), .output("37C0"))
    }

    /// What osascript prints when the user said no (or never answered) in the
    /// macOS automation prompt.
    func testRefusedAutomationIsNotAuthorized() {
        XCTAssertEqual(
            AppleScriptOutcome.classify(
                status: 1, output: "",
                error: "execution error: Not authorized to send Apple events to cmux. (-1743)\n"),
            .notAuthorized)
        XCTAssertEqual(
            AppleScriptOutcome.classify(
                status: 1, output: "", error: "execution error: … (-1744)"),
            .notAuthorized)
    }

    func testAnyOtherFailureIsJustAFailure() {
        XCTAssertEqual(
            AppleScriptOutcome.classify(status: 1, output: "", error: "syntax error (-2741)"),
            .failed)
        XCTAssertEqual(AppleScriptOutcome.output("x").text, "x")
        XCTAssertEqual(AppleScriptOutcome.failed.text, "")
        XCTAssertEqual(AppleScriptOutcome.notAuthorized.text, "")
    }
}

final class AutomationDenialsTests: XCTestCase {
    func testNoHintUntilSomethingIsRefused() {
        XCTAssertNil(AutomationDenials().menuTitle)
    }

    func testRefusalsShowUpOnceEachInOrder() {
        var denials = AutomationDenials()
        denials.record(AutomationCheck(appName: "cmux", authorized: false))
        denials.record(AutomationCheck(appName: "Ghostty", authorized: false))
        denials.record(AutomationCheck(appName: "cmux", authorized: false))
        XCTAssertEqual(denials.appNames, ["cmux", "Ghostty"])
        XCTAssertEqual(denials.menuTitle, "Allow island to control cmux, Ghostty…")
    }

    func testAGrantClearsThatApp() {
        var denials = AutomationDenials()
        denials.record(AutomationCheck(appName: "cmux", authorized: false))
        denials.record(AutomationCheck(appName: "cmux", authorized: true))
        XCTAssertNil(denials.menuTitle)
    }

    func testSettingsLinkOpensTheAutomationPane() {
        XCTAssertEqual(
            AutomationDenials.settingsURL,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
}
