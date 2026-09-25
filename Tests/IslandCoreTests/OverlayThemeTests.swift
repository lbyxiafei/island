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

    /// Themes saved before the island look (the Alfred-style names) map to
    /// their closest island theme instead of silently resetting.
    func testMigratesThemesStoredBeforeTheIslandLook() {
        XCTAssertEqual(OverlayTheme.resolve(stored: "light"), .sand)
        XCTAssertEqual(OverlayTheme.resolve(stored: "dark"), .midnight)
        XCTAssertEqual(OverlayTheme.resolve(stored: "modern-dark"), .midnight)
        XCTAssertEqual(OverlayTheme.resolve(stored: "frosty"), .lagoon)
    }

    func testThemeNamesAndOrder() {
        XCTAssertEqual(
            OverlayTheme.allCases.map(\.displayName),
            ["System", "Lagoon", "Coral", "Sand", "Midnight"])
    }

    func testSystemFollowsTheAppearance() {
        XCTAssertEqual(
            OverlayTheme.system.palette(systemIsDark: false),
            OverlayTheme.sand.palette(systemIsDark: false))
        XCTAssertEqual(
            OverlayTheme.system.palette(systemIsDark: true),
            OverlayTheme.lagoon.palette(systemIsDark: true))
    }

    func testFixedThemesIgnoreTheAppearance() {
        for theme in OverlayTheme.allCases where theme != .system {
            XCTAssertEqual(theme.palette(systemIsDark: true), theme.palette(systemIsDark: false))
        }
    }

    /// Sand is the only light theme; each theme has its own accent, and the
    /// selection is a translucent tint of it rather than a solid bar.
    func testPalettesHaveTheirOwnIdentity() {
        let fixed = OverlayTheme.allCases.filter { $0 != .system }
        let palettes = fixed.map { $0.palette(systemIsDark: false) }

        XCTAssertEqual(fixed.filter { !$0.palette(systemIsDark: false).isDark }, [.sand])
        XCTAssertEqual(Set(palettes.map(\.accent.hexValue)).count, palettes.count)
        for palette in palettes {
            XCTAssertLessThan(palette.selectionBackground.alpha, 0.5)
            XCTAssertEqual(palette.selectionBackground.hexValue, palette.accent.hexValue)
        }
    }

    func testThemeColorFromHex() {
        let color = ThemeColor(hex: 0xFF8000, alpha: 0.5)

        XCTAssertEqual(color.red, 1, accuracy: 0.0001)
        XCTAssertEqual(color.green, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blue, 0, accuracy: 0.0001)
        XCTAssertEqual(color.alpha, 0.5)
        XCTAssertEqual(color.hexValue, 0xFF8000)
    }
}

final class UserDefaultsOverlayStoreTests: XCTestCase {
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
        XCTAssertEqual(UserDefaultsOverlayStore(defaults: defaults).load(), .system)
    }

    func testSavedThemeSurvivesANewStoreInstance() {
        UserDefaultsOverlayStore(defaults: defaults).save(.coral)

        XCTAssertEqual(UserDefaultsOverlayStore(defaults: defaults).load(), .coral)
        XCTAssertEqual(defaults.string(forKey: UserDefaultsOverlayStore.key), "coral")
    }

    func testKeyboardHintsAreShownUntilSwitchedOff() {
        let store = UserDefaultsOverlayStore(defaults: defaults)
        XCTAssertTrue(store.loadShowsHints())

        store.saveShowsHints(false)

        XCTAssertFalse(UserDefaultsOverlayStore(defaults: defaults).loadShowsHints())
        XCTAssertEqual(defaults.object(forKey: UserDefaultsOverlayStore.hintsKey) as? Bool, false)
    }
}

final class OverlayStatusTests: XCTestCase {
    func testCountsUnreadRuns() {
        XCTAssertEqual(OverlayStatus.text(unread: 1), "1 new")
        XCTAssertEqual(OverlayStatus.text(unread: 12), "12 new")
    }

    func testNothingUnreadIsAllCaughtUp() {
        XCTAssertEqual(OverlayStatus.text(unread: 0), "All caught up")
        XCTAssertEqual(OverlayStatus.text(unread: -1), "All caught up")
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
