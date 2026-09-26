import XCTest

@testable import IslandCore

final class AppLocationTests: XCTestCase {
    func testTranslocatedBundleIsClassifiedAsTranslocated() {
        let path =
            "/private/var/folders/xy/abc123/T/AppTranslocation/0F1E2D3C-AAAA-BBBB-CCCC-DDDDEEEEFFFF/d/Island.app"

        XCTAssertEqual(AppLocation.classify(bundlePath: path), .translocated)
    }

    func testBundleOnAMountedVolumeIsClassifiedAsDiskImage() {
        XCTAssertEqual(
            AppLocation.classify(bundlePath: "/Volumes/island 0.1.0/Island.app"), .diskImage)
    }

    func testApplicationsAndOtherWritablePathsAreInstalled() {
        for path in [
            "/Applications/Island.app",
            "/Users/me/Applications/Island.app",
            "/Users/me/Repos/island/build/Island.app",
            // Only the /Volumes root counts; a folder merely named Volumes does not.
            "/Users/me/Volumes/Island.app",
        ] {
            XCTAssertEqual(AppLocation.classify(bundlePath: path), .installed, path)
        }
    }

    func testOnlyTransientLocationsAskToMove() {
        XCTAssertTrue(AppLocation.translocated.needsMove)
        XCTAssertTrue(AppLocation.diskImage.needsMove)
        XCTAssertFalse(AppLocation.installed.needsMove)
    }

    func testDestinationKeepsTheBundleNameInsideApplications() {
        XCTAssertEqual(
            MoveToApplications.destination(
                forBundlePath: "/Volumes/island 0.1.0/Island.app"),
            "/Applications/Island.app"
        )
    }

    /// The relaunch has to wait for this instance to exit, otherwise two copies
    /// briefly fight over the hotkey and the login item.
    func testRelaunchWaitsForThisProcessThenOpensTheCopy() {
        let command = MoveToApplications.relaunchCommand(
            pid: 4242, appPath: "/Applications/Island.app")

        XCTAssertEqual(command.executable, "/bin/sh")
        XCTAssertEqual(command.arguments.first, "-c")
        let script = command.arguments[1]
        XCTAssertTrue(script.contains("kill -0 \"$1\""), script)
        XCTAssertTrue(script.contains("/usr/bin/open \"$2\""), script)
        // Values travel as positional arguments, never spliced into the script.
        XCTAssertEqual(
            Array(command.arguments.suffix(3)), ["sh", "4242", "/Applications/Island.app"])
    }

    func testQuarantineRemovalTargetsTheCopyRecursively() {
        let command = MoveToApplications.clearQuarantineCommand(appPath: "/Applications/Island.app")

        XCTAssertEqual(command.executable, "/usr/bin/xattr")
        XCTAssertEqual(
            command.arguments, ["-dr", "com.apple.quarantine", "/Applications/Island.app"])
    }

    func testPromptExplainsWhyForEachTransientLocation() throws {
        let translocated = try XCTUnwrap(MoveToApplications.prompt(for: .translocated))
        let diskImage = try XCTUnwrap(MoveToApplications.prompt(for: .diskImage))

        XCTAssertTrue(translocated.message.contains("Applications"))
        XCTAssertTrue(diskImage.informativeText.contains("disk image"))
        XCTAssertNotEqual(translocated.informativeText, diskImage.informativeText)
        XCTAssertNil(MoveToApplications.prompt(for: .installed))
    }
}
