import SessionCore
import XCTest

final class SessionSelectionTests: XCTestCase {
    private typealias Item = SessionSelection.Item

    // MARK: follow

    func testStaysWhileNameAndTerminalAreTheSame() {
        let rows = [Item(name: "a", tmux: "a"), Item(name: "b", tmux: nil)]
        XCTAssertEqual(SessionSelection.follow("a", before: rows, after: rows), "a")
        XCTAssertEqual(SessionSelection.follow("b", before: rows, after: rows), "b")
    }

    func testExitToShellUnderTheSameName() {
        // /exit: the registry entry is gone, the tmux session "foo" now shows a shell under its own name
        let before = [Item(name: "foo", tmux: "foo")]
        let after = [Item(name: "foo", tmux: "foo")]
        XCTAssertEqual(SessionSelection.follow("foo", before: before, after: after), "foo")
    }

    func testExitToShellAfterRenameFollowsTheTerminal() {
        // /rename made the session "work" while its tmux session stayed "foo"; after /exit the shell row is "foo"
        let before = [Item(name: "work", tmux: "foo"), Item(name: "other", tmux: "other")]
        let after = [Item(name: "other", tmux: "other"), Item(name: "foo", tmux: "foo")]
        XCTAssertEqual(SessionSelection.follow("work", before: before, after: after), "foo")
    }

    func testExitWithHandoverAfterRenameFollowsTheTerminalNotTheOfflineRow() {
        // "work" stays in the list offline (it has a handover), but the terminal the user looks at is "foo"
        let before = [Item(name: "work", tmux: "foo")]
        let after = [Item(name: "work", tmux: nil), Item(name: "foo", tmux: "foo")]
        XCTAssertEqual(SessionSelection.follow("work", before: before, after: after), "foo")
    }

    func testClaudeStartedAgainInTheShellLandsOnItsRow() {
        // `claude -n work` in the shell row "foo": Claude registers with pane of "foo"
        let before = [Item(name: "foo", tmux: "foo")]
        let after = [Item(name: "work", tmux: "foo")]
        XCTAssertEqual(SessionSelection.follow("foo", before: before, after: after), "work")
    }

    func testTerminalGoneKeepsTheOfflineRow() {
        // `exit` in the shell of a session that has a handover: it stays in the list offline
        let before = [Item(name: "foo", tmux: "foo"), Item(name: "b", tmux: "b")]
        let after = [Item(name: "b", tmux: "b"), Item(name: "foo", tmux: nil)]
        XCTAssertEqual(SessionSelection.follow("foo", before: before, after: after), "foo")
    }

    func testTerminalGonePicksTheNextRowElseThePrevious() {
        let before = [Item(name: "a", tmux: "a"), Item(name: "b", tmux: "b"), Item(name: "c", tmux: "c")]
        XCTAssertEqual(SessionSelection.follow("b", before: before, after: [before[0], before[2]]), "c")
        XCTAssertEqual(SessionSelection.follow("b", before: before, after: [before[0]]), "a")
        XCTAssertEqual(SessionSelection.follow("c", before: before, after: [before[0], before[1]]), "b")
        XCTAssertNil(SessionSelection.follow("b", before: before, after: []))
    }

    func testSameTerminalBeatsTheNearestRow() {
        let before = [Item(name: "a", tmux: "a"), Item(name: "b", tmux: "b")]
        let after = [Item(name: "a", tmux: "a"), Item(name: "b2", tmux: "b")]
        XCTAssertEqual(SessionSelection.follow("b", before: before, after: after), "b2")
    }

    func testUnknownSelectionIsLeftAlone() {
        // `--select name` at launch, before the rows are in
        XCTAssertEqual(SessionSelection.follow("later", before: [], after: [Item(name: "a", tmux: nil)]), "later")
        XCTAssertNil(SessionSelection.follow(nil, before: [Item(name: "a", tmux: nil)], after: []))
    }

    // MARK: rowIDs

    func testRowGoesByItsTmuxSessionElseBySession() {
        let ids = SessionSelection.rowIDs([("work|123", "foo"), ("off|7", nil), ("only", nil)])
        XCTAssertEqual(ids, ["tmux:foo", "off|7", "only"])
    }

    func testRowKeepsItsIDAcrossExitAndRestart() {
        // running → shell after /exit → running again with a new pid
        XCTAssertEqual(SessionSelection.rowIDs([("foo|123", "foo")]), SessionSelection.rowIDs([("foo", "foo")]))
        XCTAssertEqual(SessionSelection.rowIDs([("foo|123", "foo")]), SessionSelection.rowIDs([("foo|456", "foo")]))
    }

    func testSharedTmuxSessionStaysUniqueInTheList() {
        let ids = SessionSelection.rowIDs([("outer|1", "foo"), ("inner|2", "foo")])
        XCTAssertEqual(ids, ["tmux:foo", "inner|2"])
        XCTAssertEqual(Set(ids).count, 2)
    }
}
