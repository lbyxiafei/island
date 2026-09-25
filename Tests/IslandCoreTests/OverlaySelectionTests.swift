import XCTest

@testable import IslandCore

final class TaskFilterTests: XCTestCase {
    func testAnEmptyQueryMatchesEverything() {
        XCTAssertTrue(TaskFilter.matches(task("fix login"), query: ""))
        XCTAssertTrue(TaskFilter.matches(task("fix login"), query: "   "))
    }

    func testMatchesTitleCaseInsensitively() {
        XCTAssertTrue(TaskFilter.matches(task("Fix Login Race"), query: "login"))
        XCTAssertFalse(TaskFilter.matches(task("Fix Login Race"), query: "logout"))
    }

    func testMatchesTheDirectoryNameAndTheAgentName() {
        let item = task("refactor", cwd: "/Users/me/Repos/island", agent: .codex)

        XCTAssertTrue(TaskFilter.matches(item, query: "island"))
        XCTAssertTrue(TaskFilter.matches(item, query: "codex"))
        XCTAssertFalse(TaskFilter.matches(item, query: "Repos"))
    }

    /// Alfred-style: every word must hit somewhere, in any field.
    func testEveryWordMustMatchSomewhere() {
        let item = task("fix login race", cwd: "/tmp/island")

        XCTAssertTrue(TaskFilter.matches(item, query: "island race"))
        XCTAssertFalse(TaskFilter.matches(item, query: "island dotfiles"))
    }
}

final class OverlaySelectionTests: XCTestCase {
    func testStartsOnTheFirstRow() {
        let selection = OverlaySelection(entries: entries("a", "b", "c"))

        XCTAssertEqual(selection.selectedIndex, 0)
        XCTAssertEqual(selection.selected?.task.title, "a")
    }

    func testNothingIsSelectedWhenThereAreNoRows() {
        var selection = OverlaySelection(entries: [])

        selection.move(by: 1)

        XCTAssertNil(selection.selectedIndex)
        XCTAssertNil(selection.selected)
    }

    func testMovingStopsAtBothEnds() {
        var selection = OverlaySelection(entries: entries("a", "b", "c"))

        selection.move(by: 1)
        XCTAssertEqual(selection.selectedIndex, 1)
        selection.move(by: 5)
        XCTAssertEqual(selection.selectedIndex, 2)
        selection.move(by: -9)
        XCTAssertEqual(selection.selectedIndex, 0)
    }

    func testTypingFiltersAndSelectsTheFirstMatch() {
        var selection = OverlaySelection(entries: entries("alpha", "beta", "alps"))
        selection.move(by: 2)

        selection.setQuery("al")

        XCTAssertEqual(selection.rows.map(\.task.title), ["alpha", "alps"])
        XCTAssertEqual(selection.selectedIndex, 0)
        XCTAssertEqual(selection.query, "al")
    }

    func testAQueryWithNoMatchesLeavesNothingSelected() {
        var selection = OverlaySelection(entries: entries("alpha"))

        selection.setQuery("zzz")

        XCTAssertTrue(selection.rows.isEmpty)
        XCTAssertNil(selection.selected)
    }

    /// A refresh (a task finishing while the list is open) must not yank the
    /// highlight away from what the user is looking at.
    func testRefreshingKeepsTheSelectedTaskWhenItIsStillListed() {
        var selection = OverlaySelection(entries: entries("a", "b", "c"))
        selection.move(by: 1)

        selection.setEntries(entries("new", "a", "b", "c"))

        XCTAssertEqual(selection.selected?.task.title, "b")
        XCTAssertEqual(selection.selectedIndex, 2)
    }

    func testRefreshingFallsBackToTheFirstRowWhenTheSelectionIsGone() {
        var selection = OverlaySelection(entries: entries("a", "b"))
        selection.move(by: 1)

        selection.setEntries(entries("c", "d"))

        XCTAssertEqual(selection.selectedIndex, 0)
    }

    func testRefreshingKeepsTheQuery() {
        var selection = OverlaySelection(entries: entries("alpha", "beta"))
        selection.setQuery("be")

        selection.setEntries(entries("alpha", "beta", "bear"))

        XCTAssertEqual(selection.rows.map(\.task.title), ["beta", "bear"])
    }

    func testSelectingARowByIndex() {
        var selection = OverlaySelection(entries: entries("a", "b", "c"))

        selection.select(index: 2)
        XCTAssertEqual(selection.selectedIndex, 2)

        selection.select(index: 7)
        XCTAssertEqual(selection.selectedIndex, 2, "out-of-range picks are ignored")
    }

    func testCommandNumberPicksTheNthVisibleRow() {
        var selection = OverlaySelection(entries: entries("a", "b", "c"))
        selection.setQuery("")

        XCTAssertEqual(selection.entry(forShortcut: 1)?.task.title, "a")
        XCTAssertEqual(selection.entry(forShortcut: 3)?.task.title, "c")
        XCTAssertNil(selection.entry(forShortcut: 4))
        XCTAssertNil(selection.entry(forShortcut: 0))
    }

    /// Alfred shows ↩ on the highlighted row and ⌘N on the others (N ≤ 9).
    func testShortcutLabels() {
        XCTAssertEqual(OverlaySelection.shortcutLabel(row: 0, selectedRow: 0), "↩")
        XCTAssertEqual(OverlaySelection.shortcutLabel(row: 1, selectedRow: 0), "⌘2")
        XCTAssertEqual(OverlaySelection.shortcutLabel(row: 0, selectedRow: 3), "⌘1")
        XCTAssertEqual(OverlaySelection.shortcutLabel(row: 8, selectedRow: nil), "⌘9")
        XCTAssertNil(OverlaySelection.shortcutLabel(row: 9, selectedRow: nil))
    }
}

private func entries(_ titles: String...) -> [AgentInbox.Entry] {
    // Same title, same run: a refresh that reorders rows keeps their ids.
    titles.map { title in
        AgentInbox.Entry(task: task(title, id: "s\(title)"), isRead: false)
    }
}

private func task(
    _ title: String,
    id: String = "s1",
    at seconds: Int = 0,
    cwd: String? = nil,
    agent: AgentKind = .claudeCode
) -> AgentTask {
    AgentTask(
        agent: agent,
        sessionID: id,
        title: title,
        cwd: cwd,
        completedAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
        host: .unknown,
        resumeCommand: nil
    )
}
