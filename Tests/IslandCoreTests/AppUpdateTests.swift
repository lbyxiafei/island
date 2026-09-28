import XCTest

@testable import IslandCore

final class AppUpdateTests: XCTestCase {
    // MARK: - AppVersion

    func testParsesDottedVersionsWithOrWithoutAVPrefix() {
        XCTAssertEqual(AppVersion("0.2.1"), AppVersion(major: 0, minor: 2, patch: 1))
        XCTAssertEqual(AppVersion(" v1.10.0\n"), AppVersion(major: 1, minor: 10, patch: 0))
        XCTAssertEqual(AppVersion("2.3"), AppVersion(major: 2, minor: 3, patch: 0))
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("1.x.0"))
        XCTAssertNil(AppVersion("1.2.3.4"))
        XCTAssertNil(AppVersion("-1.0.0"))
    }

    func testComparesNumericallyNotAlphabetically() throws {
        let older = try XCTUnwrap(AppVersion("0.9.0"))
        let newer = try XCTUnwrap(AppVersion("0.10.0"))

        XCTAssertLessThan(older, newer)
        XCTAssertLessThan(AppVersion(major: 1, minor: 2, patch: 3), AppVersion("1.2.4")!)
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("2.0.0")!)
        XCTAssertEqual(newer.description, "0.10.0")
    }

    func testLocalBuildsAreDevelopmentVersions() {
        XCTAssertTrue(AppVersion("0.0.0")!.isDevelopment)
        XCTAssertFalse(AppVersion("0.1.0")!.isDevelopment)
    }

    // MARK: - Cask

    func testReadsTheVersionOutOfTheCask() {
        let cask = """
            cask "island" do
              version "0.3.2"
              sha256 "53cb"

              url "https://github.com/x/releases/download/island-v#{version}/island-#{version}.dmg"
            end
            """

        XCTAssertEqual(UpdateSource.version(fromCask: cask), AppVersion("0.3.2"))
    }

    func testACaskWithoutAUsableVersionYieldsNothing() {
        XCTAssertNil(UpdateSource.version(fromCask: "cask \"island\" do\nend"))
        XCTAssertNil(UpdateSource.version(fromCask: "  version :latest"))
        XCTAssertNil(UpdateSource.version(fromCask: "  version \"soon\""))
    }

    func testSourcesPointAtThePublicTap() {
        XCTAssertEqual(
            UpdateSource.caskURL.absoluteString,
            "https://raw.githubusercontent.com/lbyxiafei/homebrew-tap/main/Casks/island.rb")
        XCTAssertEqual(
            UpdateSource.releasesURL.absoluteString,
            "https://github.com/lbyxiafei/homebrew-tap/releases/latest")
        XCTAssertEqual(UpdateSource.cask, "lbyxiafei/tap/island")
    }

    // MARK: - Status

    func testNewerLatestIsAnAvailableUpdate() {
        let status = UpdateStatus.resolve(
            current: AppVersion("0.1.0")!, latest: AppVersion("0.2.0"))

        XCTAssertEqual(status, .available(AppVersion("0.2.0")!))
        XCTAssertTrue(status.needsAttention)
    }

    func testSameOrOlderLatestIsUpToDate() {
        XCTAssertEqual(
            UpdateStatus.resolve(current: AppVersion("0.2.0")!, latest: AppVersion("0.2.0")),
            .upToDate)
        XCTAssertEqual(
            UpdateStatus.resolve(current: AppVersion("0.3.0")!, latest: AppVersion("0.2.0")),
            .upToDate)
        XCTAssertFalse(UpdateStatus.upToDate.needsAttention)
    }

    func testAFailedCheckIsUnknownAndQuiet() {
        let status = UpdateStatus.resolve(current: AppVersion("0.1.0")!, latest: nil)

        XCTAssertEqual(status, .unknown)
        XCTAssertFalse(status.needsAttention)
    }

    /// A local build is 0.0.0; nagging the developer about every release is noise.
    func testDevelopmentBuildsNeverAskToUpgrade() {
        let status = UpdateStatus.resolve(
            current: AppVersion("0.0.0")!, latest: AppVersion("0.5.0"))

        XCTAssertEqual(status, .development)
        XCTAssertFalse(status.needsAttention)
    }

    func testStatusLinesDescribeEachState() {
        let current = AppVersion("0.1.0")!
        XCTAssertEqual(
            UpdateStatus.available(AppVersion("0.2.0")!).summary(current: current),
            "island 0.2.0 is available — you have 0.1.0.")
        XCTAssertEqual(
            UpdateStatus.upToDate.summary(current: current), "island 0.1.0 is up to date.")
        XCTAssertEqual(
            UpdateStatus.unknown.summary(current: current),
            "Could not check for updates (you have 0.1.0).")
        XCTAssertTrue(
            UpdateStatus.development.summary(current: AppVersion("0.0.0")!).contains(
                "development build"))
        XCTAssertEqual(UpdateStatus.checking.summary(current: current), "Checking for updates…")
        XCTAssertFalse(UpdateStatus.checking.needsAttention)
    }

    func testTabLabelCarriesADotOnlyWhenAnUpdateWaits() {
        XCTAssertEqual(UpdateStatus.upToDate.tabLabel, "Updates")
        XCTAssertEqual(UpdateStatus.available(AppVersion("1.0.0")!).tabLabel, "Updates 🔴")
    }

    // MARK: - Install method

    func testUpgradesThroughBrewWhenTheCaskIsInstalled() {
        let existing: Set<String> = ["/opt/homebrew/bin/brew", "/opt/homebrew/Caskroom/island"]

        XCTAssertEqual(
            UpgradeMethod.detect(fileExists: existing.contains),
            .brew(executable: "/opt/homebrew/bin/brew"))
    }

    func testFindsIntelHomebrewToo() {
        let existing: Set<String> = ["/usr/local/bin/brew", "/usr/local/Caskroom/island"]

        XCTAssertEqual(
            UpgradeMethod.detect(fileExists: existing.contains),
            .brew(executable: "/usr/local/bin/brew"))
    }

    /// brew is there, but island came from a dmg: `brew upgrade` would fail.
    func testFallsBackToTheReleasePageWhenNotInstalledByBrew() {
        XCTAssertEqual(
            UpgradeMethod.detect(fileExists: { $0 == "/opt/homebrew/bin/brew" }), .download)
        XCTAssertEqual(UpgradeMethod.detect(fileExists: { _ in false }), .download)
    }

    func testButtonTitlesFollowTheMethod() {
        let version = AppVersion("0.2.0")!
        XCTAssertEqual(
            UpgradeMethod.brew(executable: "/b").buttonTitle(for: version),
            "Upgrade to 0.2.0 & Relaunch")
        XCTAssertEqual(UpgradeMethod.download.buttonTitle(for: version), "Download 0.2.0…")
    }

    func testUpgradeWaitsForThisProcessThenBrewsAndReopens() {
        let command = UpgradeMethod.upgradeCommand(
            pid: 4242, brew: "/opt/homebrew/bin/brew", logPath: "/tmp/u.log")

        XCTAssertEqual(command.executable, "/bin/sh")
        XCTAssertEqual(command.arguments.first, "-c")
        let script = command.arguments[1]
        XCTAssertTrue(script.contains("kill -0 \"$1\""), script)
        XCTAssertTrue(script.contains("\"$2\" update"), script)
        XCTAssertTrue(script.contains("\"$2\" upgrade --cask \"$3\""), script)
        XCTAssertTrue(script.contains(">>\"$4\""), script)
        XCTAssertTrue(script.contains("/usr/bin/open -b \"$5\""), script)
        // The exit status is logged so the next launch can tell a failure apart.
        XCTAssertTrue(script.contains(UpgradeLog.resultPrefix), script)
        XCTAssertEqual(
            Array(command.arguments.suffix(6)),
            [
                "sh", "4242", "/opt/homebrew/bin/brew", "lbyxiafei/tap/island", "/tmp/u.log",
                "com.commallama.island",
            ])
    }

    // MARK: - Upgrade log

    func testReadsTheLastUpgradeResult() {
        let log = """
            ==> Upgrading island
            island-upgrade: exit 1
            ==> Upgrading island
            island-upgrade: exit 0
            """

        XCTAssertEqual(UpgradeLog.lastExitStatus(in: log), 0)
        XCTAssertEqual(UpgradeLog.lastExitStatus(in: "Error: boom\nisland-upgrade: exit 1\n"), 1)
        XCTAssertNil(UpgradeLog.lastExitStatus(in: "==> Upgrading island\n"))
        XCTAssertNil(UpgradeLog.lastExitStatus(in: "island-upgrade: exit x"))
    }

    // MARK: - Settings

    func testAutomaticChecksAreOnUntilSwitchedOff() throws {
        let suite = "AppUpdateTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsUpdateStore(defaults: defaults)

        XCTAssertTrue(store.loadAutoCheck())
        store.saveAutoCheck(false)
        XCTAssertFalse(store.loadAutoCheck())
    }
}
