import XCTest

@testable import IslandCore

final class OverlayThemeTests: XCTestCase {
    func testDefaultsToFollowingTheSystem() {
        XCTAssertEqual(OverlayTheme.resolve(stored: nil), .system)
        XCTAssertEqual(OverlayTheme.resolve(stored: "no-such-theme"), .system)
    }

    func testRestoresAStoredTheme() {
        for theme in OverlayTheme.allCases {
            XCTAssertEqual(OverlayTheme.resolve(stored: theme.rawValue), theme)
        }
    }

    func testEveryThemeHasADistinctDisplayName() {
        let names = OverlayTheme.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(OverlayTheme.system.displayName, "System")
        XCTAssertEqual(OverlayTheme.modernDark.displayName, "Modern Dark")
    }

    func testSystemFollowsTheAppearance() {
        XCTAssertEqual(
            OverlayTheme.system.palette(systemIsDark: false),
            OverlayTheme.light.palette(systemIsDark: false))
        XCTAssertEqual(
            OverlayTheme.system.palette(systemIsDark: true),
            OverlayTheme.dark.palette(systemIsDark: true))
    }

    func testFixedThemesIgnoreTheAppearance() {
        for theme in OverlayTheme.allCases where theme != .system {
            XCTAssertEqual(theme.palette(systemIsDark: true), theme.palette(systemIsDark: false))
        }
    }

    /// The looks from the Alfred references: purple highlight on light, teal on
    /// dark, and a visible border only on Modern Dark.
    func testPalettesMatchTheirReferenceLooks() {
        let light = OverlayTheme.light.palette(systemIsDark: false)
        let dark = OverlayTheme.dark.palette(systemIsDark: false)
        let modern = OverlayTheme.modernDark.palette(systemIsDark: false)
        let frosty = OverlayTheme.frosty.palette(systemIsDark: false)

        XCTAssertFalse(light.isDark)
        XCTAssertEqual(light.selectionBackground, ThemeColor(hex: 0x5E1D73))
        XCTAssertTrue(dark.isDark)
        XCTAssertEqual(dark.selectionBackground, ThemeColor(hex: 0x367F87))
        XCTAssertGreaterThan(modern.borderWidth, 0)
        XCTAssertEqual(light.borderWidth, 0)
        XCTAssertGreaterThan(modern.cornerRadius, dark.cornerRadius)
        XCTAssertTrue(frosty.isDark)
        XCTAssertLessThan(frosty.background.alpha, dark.background.alpha)
    }

    func testThemeColorFromHex() {
        let color = ThemeColor(hex: 0xFF8000, alpha: 0.5)

        XCTAssertEqual(color.red, 1, accuracy: 0.0001)
        XCTAssertEqual(color.green, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 0.5)
    }
}

final class UserDefaultsThemeStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "island.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLoadsTheDefaultBeforeAnythingIsSaved() {
        XCTAssertEqual(UserDefaultsThemeStore(defaults: defaults).load(), .system)
    }

    func testSavedThemeSurvivesANewStoreInstance() {
        UserDefaultsThemeStore(defaults: defaults).save(.modernDark)

        XCTAssertEqual(UserDefaultsThemeStore(defaults: defaults).load(), .modernDark)
        XCTAssertEqual(defaults.string(forKey: UserDefaultsThemeStore.key), "modern-dark")
    }
}

final class AgentIconTests: XCTestCase {
    func testDesktopAgentsUseTheirOwnApp() {
        XCTAssertEqual(
            AgentIcon.bundleIDs(for: .claudeCode).first, "com.anthropic.claudefordesktop")
        XCTAssertEqual(AgentIcon.bundleIDs(for: .codex).first, "com.openai.codex")
    }

    func testPiHasNoAppAndFallsBackToASymbol() {
        XCTAssertTrue(AgentIcon.bundleIDs(for: .pi).isEmpty)
        XCTAssertEqual(AgentIcon.symbolName(for: .pi), "terminal")
    }

    func testEveryAgentHasAFallbackSymbol() {
        for agent in AgentKind.allCases {
            XCTAssertFalse(AgentIcon.symbolName(for: agent).isEmpty)
        }
    }
}
