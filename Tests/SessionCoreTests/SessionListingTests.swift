import SessionCore
import XCTest

final class SessionListingTests: XCTestCase {
    private func ended(_ name: String) -> Session { Session(name: name, group: name, hasHandover: true) }

    func testEndedSessionFromOutsideTheAppIsNotListed() {
        XCTAssertFalse(ended("outside").staysListed(inAppTmux: false, startedInApp: ["other"]))
    }

    func testEndedSessionStartedInTheAppStaysListed() {
        XCTAssertTrue(ended("mine").staysListed(inAppTmux: false, startedInApp: ["mine"]))
    }

    func testRunningSessionFromOutsideTheAppIsListed() {
        let s = Session(name: "outside", group: "outside", pid: 1, alive: true, status: "idle")
        XCTAssertTrue(s.staysListed(inAppTmux: false, startedInApp: []))
    }

    func testSessionInTheAppsTmuxIsListed() {
        XCTAssertTrue(ended("shell").staysListed(inAppTmux: true, startedInApp: []))
    }
}
