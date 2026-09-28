import XCTest

@testable import IslandCore

final class AgentHomeTests: XCTestCase {
    private let user = URL(fileURLWithPath: "/Users/someone")

    func testUsesTheUserHomeByDefault() {
        XCTAssertEqual(AgentHome.resolve(nil, userHome: user), user)
    }

    func testIgnoresABlankOverride() {
        XCTAssertEqual(AgentHome.resolve("  ", userHome: user), user)
    }

    func testReadsAgentsFromTheOverrideDirectory() {
        XCTAssertEqual(
            AgentHome.resolve("/tmp/island-demo", userHome: user),
            URL(fileURLWithPath: "/tmp/island-demo", isDirectory: true))
    }

    func testExpandsATildeInTheOverride() {
        XCTAssertEqual(
            AgentHome.resolve("~/demo", userHome: user),
            URL(fileURLWithPath: "/Users/someone/demo", isDirectory: true))
    }
}
