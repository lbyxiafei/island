import XCTest

@testable import IslandCore

final class LoginItemMenuPresentationTests: XCTestCase {
    func testEnabledIsCheckedWithoutHint() {
        let presentation = LoginItemMenuPresentation.make(for: .enabled)

        XCTAssertTrue(presentation.isChecked)
        XCTAssertNil(presentation.hint)
    }

    func testNotRegisteredIsUncheckedWithoutHint() {
        let presentation = LoginItemMenuPresentation.make(for: .notRegistered)

        XCTAssertFalse(presentation.isChecked)
        XCTAssertNil(presentation.hint)
    }

    /// These two states look identical in the menu (both unchecked) but need
    /// different user action, so each has to explain itself.
    func testBlockedStatesAreUncheckedAndExplainDifferentRemedies() throws {
        let needsApproval = LoginItemMenuPresentation.make(for: .requiresApproval)
        let appMissing = LoginItemMenuPresentation.make(for: .notFound)

        XCTAssertFalse(needsApproval.isChecked)
        XCTAssertFalse(appMissing.isChecked)
        let approvalHint = try XCTUnwrap(needsApproval.hint)
        let missingHint = try XCTUnwrap(appMissing.hint)
        XCTAssertNotEqual(approvalHint, missingHint)
    }
}
