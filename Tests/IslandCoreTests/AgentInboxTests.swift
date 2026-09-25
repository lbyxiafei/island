import XCTest

@testable import IslandCore

final class TaskLimitTests: XCTestCase {
    func testFallsBackWhenUnsetOrUnusable() {
        XCTAssertEqual(TaskLimit.resolve(nil), 10)
        XCTAssertEqual(TaskLimit.resolve("  "), 10)
        XCTAssertEqual(TaskLimit.resolve("zero"), 10)
        XCTAssertEqual(TaskLimit.resolve("0"), 10)
        XCTAssertEqual(TaskLimit.resolve("-3"), 10)
    }

    func testUsesAPositiveValue() {
        XCTAssertEqual(TaskLimit.resolve(" 25 "), 25)
        XCTAssertEqual(TaskLimit.resolve("1"), 1)
    }
}

final class AgentInboxTests: XCTestCase {
    func testNewRunsArriveUnreadAndNewestFirst() {
        let inbox = AgentInbox(limit: 10)

        let added = inbox.ingest([
            task("old", at: 1),
            task("new", at: 9),
        ])

        XCTAssertTrue(added)
        XCTAssertEqual(inbox.unreadCount, 2)
        XCTAssertEqual(
            inbox.visibleEntries.map(\.id), [task("new", at: 9).id, task("old", at: 1).id])
    }

    func testReingestingKnownRunsChangesNothing() {
        let inbox = AgentInbox()
        inbox.ingest([task("a", at: 1)])

        XCTAssertFalse(inbox.ingest([task("a", at: 1)]))
        XCTAssertEqual(inbox.allEntries.count, 1)
    }

    /// PLAN § Design: unread first, then most recently updated. A read entry
    /// stays in the list, it just moves below the unread ones.
    func testReadEntriesStayButSortBelowUnreadOnes() {
        let inbox = AgentInbox()
        inbox.ingest([task("a", at: 1), task("b", at: 2)])

        inbox.markRead(id: task("b", at: 2).id)

        XCTAssertEqual(inbox.unreadCount, 1)
        XCTAssertEqual(inbox.visibleEntries.map(\.id), [task("a", at: 1).id, task("b", at: 2).id])
        XCTAssertTrue(inbox.visibleEntries.last?.isRead == true)
    }

    func testMarkingAnUnknownOrAlreadyReadRunIsANoOp() {
        let inbox = AgentInbox()
        inbox.ingest([task("a", at: 1)])

        inbox.markRead(id: "nothing")
        inbox.markRead(id: task("a", at: 1).id)
        inbox.markRead(id: task("a", at: 1).id)

        XCTAssertEqual(inbox.unreadCount, 0)
    }

    func testVisibleEntriesAreCappedAtTheLimit() {
        let inbox = AgentInbox(limit: 2)
        inbox.ingest((1...5).map { task("t\($0)", at: TimeInterval($0)) })

        XCTAssertEqual(inbox.allEntries.count, 5)
        XCTAssertEqual(inbox.visibleEntries.count, 2)
        XCTAssertEqual(
            inbox.visibleEntries.map(\.id), [task("t5", at: 5).id, task("t4", at: 4).id])
    }

    func testLimitAndCapacityAreClampedToAtLeastOne() {
        let inbox = AgentInbox(limit: 0, capacity: 0)

        XCTAssertEqual(inbox.limit, 1)
        inbox.ingest((1...3).map { task("t\($0)", at: TimeInterval($0)) })

        XCTAssertEqual(inbox.visibleEntries.count, 1)
    }

    func testOldReadRunsAreDroppedOnceOverCapacity() {
        let inbox = AgentInbox(limit: 1, capacity: 3)
        let runs = (1...4).map { task("t\($0)", at: TimeInterval($0)) }
        inbox.ingest(runs)
        XCTAssertEqual(inbox.allEntries.count, 4)

        let oldest = runs[0]
        inbox.markRead(id: oldest.id)
        inbox.ingest([task("t5", at: 5)])

        XCTAssertEqual(inbox.allEntries.count, 4)
        XCTAssertFalse(inbox.allEntries.contains { $0.id == oldest.id })
        // Dropped, and not resurrected by the next scan of the same run.
        XCTAssertFalse(inbox.ingest([oldest]))
    }

    /// Issue dropdown-title-ux #2: one row per session. A newer run of the same
    /// session replaces the old row and makes it unread again.
    func testANewerRunOfTheSameSessionReplacesItsRow() {
        let inbox = AgentInbox()
        inbox.ingest([task("a", at: 1), task("b", at: 2)])
        inbox.markRead(id: task("a", at: 1).id)

        XCTAssertTrue(inbox.ingest([task("a", at: 5)]))

        XCTAssertEqual(inbox.allEntries.count, 2)
        XCTAssertEqual(inbox.unreadCount, 2)
        XCTAssertEqual(inbox.allEntries.map(\.id), [task("a", at: 5).id, task("b", at: 2).id])
    }

    func testAnOlderOrRepeatedRunOfAKnownSessionChangesNothing() {
        let inbox = AgentInbox()
        inbox.ingest([task("a", at: 5)])
        inbox.markRead(id: task("a", at: 5).id)

        XCTAssertFalse(inbox.ingest([task("a", at: 3), task("a", at: 5)]))
        XCTAssertEqual(inbox.allEntries.map(\.id), [task("a", at: 5).id])
        XCTAssertEqual(inbox.unreadCount, 0)
    }

    func testRunsOfOneSessionInTheSameBatchCollapseToTheNewest() {
        let inbox = AgentInbox()

        inbox.ingest([task("a", at: 1), task("a", at: 3), task("a", at: 2)])

        XCTAssertEqual(inbox.allEntries.map(\.id), [task("a", at: 3).id])
    }

    func testSameSessionIDFromDifferentAgentsStaysSeparate() {
        let inbox = AgentInbox()
        let codex = AgentTask(
            agent: .codex, sessionID: "a", title: "a", cwd: nil,
            completedAt: Date(timeIntervalSince1970: 2), host: .unknown, resumeCommand: nil)

        inbox.ingest([task("a", at: 1), codex])

        XCTAssertEqual(inbox.allEntries.count, 2)
    }

    func testADroppedSessionComesBackWithANewerRun() {
        let inbox = AgentInbox(limit: 1, capacity: 1)
        inbox.ingest([task("a", at: 1)])
        inbox.markRead(id: task("a", at: 1).id)
        inbox.ingest([task("b", at: 2)])
        XCTAssertEqual(inbox.allEntries.map(\.id), [task("b", at: 2).id])

        XCTAssertTrue(inbox.ingest([task("a", at: 3)]))
        XCTAssertTrue(inbox.allEntries.contains { $0.id == task("a", at: 3).id })
    }

    private func task(_ sessionID: String, at seconds: TimeInterval) -> AgentTask {
        AgentTask(
            agent: .pi,
            sessionID: sessionID,
            title: sessionID,
            cwd: nil,
            completedAt: Date(timeIntervalSince1970: seconds),
            host: .unknown,
            resumeCommand: nil
        )
    }
}
