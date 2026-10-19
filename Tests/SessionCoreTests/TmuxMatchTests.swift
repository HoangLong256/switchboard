import SessionCore
import XCTest

final class TmuxMatchTests: XCTestCase {
    private func live(_ name: String, pane: String, tmuxSession: String?) -> Session {
        var s = Session(name: name, group: name, pid: 1, tmuxPane: pane, alive: true, status: "idle")
        s.tmuxSession = tmuxSession
        return s
    }

    func testPaneOfAnotherServerDoesNotMatch() {
        // "test" ran in another tmux server as test:@0.%0; this server's %0 belongs to demo.01
        let s = live("test", pane: "%0", tmuxSession: "test")
        let m = TmuxMatch.resolve([s], tmuxSessions: ["demo.01"], sessionOfPane: ["%0": "demo.01"])
        XCTAssertNil(m[s.id])
    }

    func testPaneMatchesWhenTheSessionNameAgrees() {
        let s = live("lu.01", pane: "%3", tmuxSession: "lu.01")
        XCTAssertEqual(TmuxMatch.resolve([s], tmuxSessions: ["lu.01"], sessionOfPane: ["%3": "lu.01"])[s.id], "lu.01")
    }

    func testSessionNameFromRegistryField() {
        XCTAssertEqual(Registry.sessionOf("keeper.01:@13.%13"), "keeper.01")
        XCTAssertNil(Registry.sessionOf(nil))
        XCTAssertNil(Registry.sessionOf("%13"))
    }
}
