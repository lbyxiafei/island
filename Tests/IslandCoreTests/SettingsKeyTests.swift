import XCTest

@testable import IslandCore

final class SettingsKeyTests: XCTestCase {
    private let escape: UInt32 = 53
    private let w: UInt32 = 13
    private let e: UInt32 = 14

    /// The bug: ⌘W pressed right after opening settings was recorded as the
    /// hotkey. Outside recording it must close the window instead.
    func testCommandWClosesTheWindowWhenNotRecording() {
        XCTAssertEqual(
            SettingsKey.action(isRecording: false, keyCode: w, modifiers: [.command]), .closeWindow)
    }

    func testEscapeClosesTheWindowWhenNotRecording() {
        XCTAssertEqual(
            SettingsKey.action(isRecording: false, keyCode: escape, modifiers: []), .closeWindow)
    }

    func testOtherKeysPassThroughWhenNotRecording() {
        XCTAssertEqual(
            SettingsKey.action(isRecording: false, keyCode: e, modifiers: [.command, .control]),
            .pass)
        XCTAssertEqual(SettingsKey.action(isRecording: false, keyCode: w, modifiers: []), .pass)
    }

    /// Once the user has clicked the field, any valid combo — even ⌘W — is
    /// what they asked to record.
    func testRecordingCapturesAValidCombination() {
        let action = SettingsKey.action(isRecording: true, keyCode: w, modifiers: [.command])

        guard case .record(let spec) = action else {
            return XCTFail("expected .record, got \(action)")
        }
        XCTAssertEqual(spec.displayString, "⌘W")
    }

    func testEscapeCancelsRecording() {
        XCTAssertEqual(
            SettingsKey.action(isRecording: true, keyCode: escape, modifiers: []), .cancelRecording)
    }

    func testRecordingRejectsKeysWithoutAModifier() {
        XCTAssertEqual(SettingsKey.action(isRecording: true, keyCode: e, modifiers: []), .reject)
    }
}
