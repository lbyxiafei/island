import XCTest

@testable import IslandCore

final class PetTests: XCTestCase {
    // MARK: - Avatar

    func testAvatarSpecsRoundTrip() {
        for character in PetCharacter.allCases {
            XCTAssertEqual(PetAvatar(spec: PetAvatar.builtIn(character).spec), .builtIn(character))
            XCTAssertFalse(character.emoji.isEmpty)
            XCTAssertFalse(character.displayName.isEmpty)
        }
        let image = PetAvatar.image(path: "/Users/me/pet.png")
        XCTAssertEqual(image.spec, "image:/Users/me/pet.png")
        XCTAssertEqual(PetAvatar(spec: image.spec), image)
    }

    func testUnknownOrEmptyAvatarSpecsAreRejected() {
        XCTAssertNil(PetAvatar(spec: "dragon"))
        XCTAssertNil(PetAvatar(spec: "image:"))
        XCTAssertNil(PetAvatar(spec: ""))
    }

    // MARK: - Settings

    /// Pet mode is opt-in; the pet starts half see-through and moving.
    func testDefaults() {
        let settings = PetSettings()
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.avatar, .builtIn(.cat))
        XCTAssertEqual(settings.idleOpacity, 0.4)
        XCTAssertTrue(settings.animates)
    }

    func testIdleOpacityIsClampedToZeroThroughOne() {
        XCTAssertEqual(PetSettings(idleOpacity: -1).idleOpacity, 0)
        XCTAssertEqual(PetSettings(idleOpacity: 3).idleOpacity, 1)
        XCTAssertEqual(PetSettings(idleOpacity: .nan).idleOpacity, PetSettings().idleOpacity)
        var settings = PetSettings()
        settings.idleOpacity = 7
        XCTAssertEqual(settings.idleOpacity, 1)
    }

    /// Idle, the pet fades to the chosen opacity (even fully transparent);
    /// unread runs or the pointer over it bring it back to full.
    func testOpacityRisesWhenARunIsWaitingOrThePointerIsOver() {
        let settings = PetSettings(idleOpacity: 0)
        XCTAssertEqual(settings.opacity(hasUnread: false, hovering: false), 0)
        XCTAssertEqual(settings.opacity(hasUnread: true, hovering: false), 1)
        XCTAssertEqual(settings.opacity(hasUnread: false, hovering: true), 1)
    }

    func testStoreRoundTripsSettingsAndPosition() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "island-pet-\(UUID().uuidString)"))
        let store = UserDefaultsPetStore(defaults: defaults)
        XCTAssertEqual(store.load(), PetSettings())
        XCTAssertNil(store.loadOrigin())

        let settings = PetSettings(
            isEnabled: true, avatar: .image(path: "/tmp/a.png"), idleOpacity: 0.25,
            animates: false)
        store.save(settings)
        store.saveOrigin(CGPoint(x: 120.5, y: 40))

        XCTAssertEqual(store.load(), settings)
        XCTAssertEqual(store.loadOrigin(), CGPoint(x: 120.5, y: 40))
    }

    func testStoreIgnoresGarbage() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "island-pet-\(UUID().uuidString)"))
        defaults.set("dragon", forKey: UserDefaultsPetStore.avatarKey)
        defaults.set("not a point", forKey: UserDefaultsPetStore.originKey)
        let store = UserDefaultsPetStore(defaults: defaults)
        XCTAssertEqual(store.load().avatar, .builtIn(.cat))
        XCTAssertNil(store.loadOrigin())
    }

    // MARK: - Bubbles

    /// Every unread run gets a bubble, newest first, up to the cap; the rest
    /// fold into a "+N more" count.
    func testBubblesShowTheNewestUnreadRunsAndCountTheRest() {
        let entries = (1...5).map { entry("s\($0)", at: Double($0)) }

        let bubbles = PetLayout.bubbles(for: entries, limit: 3)

        XCTAssertEqual(bubbles.shown.map(\.task.sessionID), ["s5", "s4", "s3"])
        XCTAssertEqual(bubbles.overflow, 2)
        XCTAssertEqual(
            PetLayout.bubbles(for: [], limit: 3), PetLayout.Bubbles(shown: [], overflow: 0))
        XCTAssertEqual(PetLayout.bubbles(for: Array(entries.prefix(2)), limit: 3).overflow, 0)
    }

    // MARK: - Placement

    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    /// Bubbles open toward the roomier side of the screen: left of a pet on
    /// the right half, right of one on the left half; upward from a pet in
    /// the lower half, downward from one in the upper half.
    func testBubblesOpenTowardTheMiddleOfTheScreen() {
        let size = CGSize(width: 200, height: 100)

        let bottomRight = CGRect(x: 900, y: 20, width: 64, height: 64)
        XCTAssertEqual(
            PetLayout.bubbleFrame(size: size, pet: bottomRight, screen: screen),
            CGRect(x: 692, y: 20, width: 200, height: 100))

        let topLeft = CGRect(x: 20, y: 700, width: 64, height: 64)
        XCTAssertEqual(
            PetLayout.bubbleFrame(size: size, pet: topLeft, screen: screen),
            CGRect(x: 92, y: 664, width: 200, height: 100))

        XCTAssertEqual(PetLayout.growth(of: bottomRight, in: screen), .up)
        XCTAssertEqual(PetLayout.growth(of: topLeft, in: screen), .down)
    }

    /// A tall stack never runs off the screen.
    func testBubbleFrameStaysOnScreen() {
        let frame = PetLayout.bubbleFrame(
            size: CGSize(width: 200, height: 900),
            pet: CGRect(x: 900, y: 20, width: 64, height: 64), screen: screen)
        XCTAssertEqual(frame.minY, 0)
        XCTAssertEqual(frame.maxY, 900)
        let narrow = PetLayout.bubbleFrame(
            size: CGSize(width: 200, height: 100),
            pet: CGRect(x: 100, y: 20, width: 64, height: 64),
            screen: CGRect(x: 0, y: 0, width: 300, height: 800))
        XCTAssertEqual(narrow.maxX, 300)
    }

    /// Top to bottom, the newest bubble sits next to the pet: at the bottom of
    /// a stack growing upward, at the top of one growing downward.
    func testNewestBubbleSitsNextToThePet() {
        let newestFirst = ["new", "mid", "old"]
        XCTAssertEqual(PetLayout.topToBottom(newestFirst, growth: .up), ["old", "mid", "new"])
        XCTAssertEqual(PetLayout.topToBottom(newestFirst, growth: .down), newestFirst)
    }

    func testDefaultOriginIsTheBottomRightCorner() {
        XCTAssertEqual(
            PetLayout.defaultOrigin(size: CGSize(width: 64, height: 64), screen: screen),
            CGPoint(x: 912, y: 24))
    }

    /// A remembered spot is kept when it is still on a screen (nudged fully
    /// inside), and replaced by the default when that screen is gone.
    func testRememberedOriginIsKeptOnScreen() {
        let size = CGSize(width: 64, height: 64)
        let second = CGRect(x: 1000, y: 0, width: 800, height: 600)
        XCTAssertEqual(
            PetLayout.origin(
                remembered: CGPoint(x: 1200, y: 300), size: size, screens: [screen, second]),
            CGPoint(x: 1200, y: 300))
        XCTAssertEqual(
            PetLayout.origin(
                remembered: CGPoint(x: 1770, y: 300), size: size, screens: [screen, second]),
            CGPoint(x: 1736, y: 300))
        XCTAssertEqual(
            PetLayout.origin(remembered: CGPoint(x: 5000, y: 300), size: size, screens: [screen]),
            CGPoint(x: 912, y: 24))
        XCTAssertEqual(
            PetLayout.origin(remembered: nil, size: size, screens: [screen]), CGPoint(x: 912, y: 24)
        )
        XCTAssertEqual(PetLayout.origin(remembered: nil, size: size, screens: []), .zero)
    }

    /// A press that barely moves is a click, not a drag.
    func testSmallMovesAreClicks() {
        XCTAssertFalse(PetLayout.isDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        XCTAssertTrue(PetLayout.isDrag(from: .zero, to: CGPoint(x: 5, y: 0)))
    }

    private func entry(_ session: String, at seconds: Double) -> AgentInbox.Entry {
        let inbox = AgentInbox()
        inbox.ingest([
            AgentTask(
                agent: .claudeCode, sessionID: session, title: session, cwd: nil,
                completedAt: Date(timeIntervalSince1970: seconds), host: .unknown,
                resumeCommand: nil)
        ])
        return inbox.allEntries[0]
    }
}
