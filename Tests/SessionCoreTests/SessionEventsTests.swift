import SessionCore
import XCTest

final class SessionEventsTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testFirstUpdateIsSilent() {
        var tracker = SessionEventTracker()
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 0, why: "Allow Bash")], now: t0), [])
    }

    func testNeedsYouOnTransitionAndOnNewQuestion() {
        var tracker = SessionEventTracker()
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1)], now: t0)
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 0, why: "Allow Bash: go test")], now: at(2)),
                       [SessionEvent(.needsYou, "a", detail: "Allow Bash: go test")])
        // the same prompt in the next refresh: nothing new
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 0, why: "Allow Bash: go test")], now: at(4)), [])
        // another prompt right after: a new event
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 0, why: "Allow Edit")], now: at(6)),
                       [SessionEvent(.needsYou, "a", detail: "Allow Edit")])
    }

    func testFinishedOnlyAfterRealWork() {
        var tracker = SessionEventTracker(minimumWork: 20)
        _ = tracker.update([SessionSnapshot(name: "a", rank: 2)], now: t0)
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1)], now: at(2))
        // a quick answer, 10 s of work: not worth a notification
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2)], now: at(12)), [])
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1)], now: at(14))
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1)], now: at(30))
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2)], now: at(40)), [SessionEvent(.finished, "a")])
    }

    func testWorkingToNeedsYouIsNotFinished() {
        var tracker = SessionEventTracker()
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1)], now: t0)
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 0, why: "Question")], now: at(60)),
                       [SessionEvent(.needsYou, "a", detail: "Question")])
    }

    func testUsageLimitOncePerHit() {
        var tracker = SessionEventTracker()
        _ = tracker.update([SessionSnapshot(name: "a", rank: 2)], now: t0)
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2, limitHit: "10:00")], now: at(2)),
                       [SessionEvent(.usageLimit, "a")])
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2, limitHit: "10:00")], now: at(4)), [])
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2, limitHit: "15:00")], now: at(6)),
                       [SessionEvent(.usageLimit, "a")])
    }

    func testEndedWhenOfflineOrGone() {
        var tracker = SessionEventTracker()
        _ = tracker.update([SessionSnapshot(name: "a", rank: 1), SessionSnapshot(name: "b", rank: 2),
                            SessionSnapshot(name: "c", rank: 3)], now: t0)
        // a goes offline, b disappears, c was offline already
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 3)], now: at(2)),
                       [SessionEvent(.ended, "a"), SessionEvent(.ended, "b")])
        // nothing more the next time
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 3)], now: at(4)), [])
    }

    func testNewSessionDoesNotFire() {
        var tracker = SessionEventTracker()
        _ = tracker.update([SessionSnapshot(name: "a", rank: 2)], now: t0)
        XCTAssertEqual(tracker.update([SessionSnapshot(name: "a", rank: 2), SessionSnapshot(name: "new", rank: 0, why: "Trust?")],
                                      now: at(2)), [])
    }
}
