@testable import SessionCore
import XCTest

final class UsageLimitTests: XCTestCase {
    private let saigon = TimeZone(identifier: "Asia/Saigon")!

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ tz: TimeZone) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testRealMessagesFromTranscripts() {
        // hit at 05:51 UTC = 12:51 in Saigon → resets 15:10 the same day
        let hit = ISO8601DateFormatter().date(from: "2026-10-15T05:51:47Z")!
        XCTAssertEqual(UsageLimit.resetTime(in: "You've hit your session limit · resets 3:10pm (Asia/Saigon)", after: hit),
                       date(2026, 10, 15, 15, 10, saigon))
        // hit at 21:27 UTC = 04:27 next day in Saigon → resets 05:10 that morning
        let night = ISO8601DateFormatter().date(from: "2026-10-14T21:27:33Z")!
        XCTAssertEqual(UsageLimit.resetTime(in: "You've hit your session limit · resets 5:10am (Asia/Saigon)", after: night),
                       date(2026, 10, 15, 5, 10, saigon))
    }

    func testWholeHoursDatesAndNoTimeZone() {
        let after = date(2026, 10, 18, 22, 0, saigon)
        XCTAssertEqual(UsageLimit.resetTime(in: "resets 1am (Asia/Saigon)", after: after), date(2026, 10, 19, 1, 0, saigon))
        XCTAssertEqual(UsageLimit.resetTime(in: "You've hit your weekly limit · resets Oct 20, 3pm (Asia/Saigon)", after: after),
                       date(2026, 10, 20, 15, 0, saigon))
        XCTAssertEqual(UsageLimit.resetTime(in: "resets Jan 2 at 9am (Asia/Saigon)", after: date(2026, 12, 30, 10, 0, saigon)),
                       date(2027, 1, 2, 9, 0, saigon))
        XCTAssertNotNil(UsageLimit.resetTime(in: "resets 3pm", after: after), "local time zone when none is given")
        XCTAssertNil(UsageLimit.resetTime(in: "Login expired · Please run /login", after: after))
        XCTAssertNil(UsageLimit.resetTime(in: "resets 13pm", after: after))
    }

    func testFallsBackToThePlanWindow() {
        let at = Date(timeIntervalSince1970: 1_792_300_000)
        let limits = PlanLimits(fiveHour: .init(percent: 100, resetsAt: at.addingTimeInterval(3600)),
                                sevenDay: .init(percent: 60, resetsAt: at.addingTimeInterval(86_400)),
                                source: .statusLine, fetchedAt: at)
        let iso = ISO8601DateFormatter().string(from: at)
        XCTAssertEqual(UsageLimit.reset(of: LimitHit(text: "You've hit your session limit", at: iso), limits: limits),
                       at.addingTimeInterval(3600))
        XCTAssertEqual(UsageLimit.reset(of: LimitHit(text: "You've hit your weekly limit", at: iso), limits: limits),
                       at.addingTimeInterval(86_400))
        XCTAssertNil(UsageLimit.reset(of: LimitHit(text: "limit", at: iso), limits: nil))
    }
}

final class LimitHitTests: XCTestCase {
    private let limitLine = #"{"type":"assistant","isApiErrorMessage":true,"apiErrorStatus":429,"apiError":"usage_limit_reached","error":"rate_limit","timestamp":"2026-10-15T05:51:47.455Z","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You've hit your session limit · resets 3:10pm (Asia/Saigon)"}]}}"#
    private let user = #"{"type":"user","timestamp":"2026-10-15T05:50:00Z","message":{"role":"user","content":"fix the build"}}"#
    private let laterUser = #"{"type":"user","timestamp":"2026-10-15T08:20:00Z","message":{"role":"user","content":"continue"}}"#
    private let meta = #"{"type":"user","isMeta":true,"timestamp":"2026-10-15T05:52:00Z","message":{"role":"user","content":"<local-command-caveat>"}}"#
    private let system = #"{"type":"system","subtype":"turn_duration","timestamp":"2026-10-15T05:52:00Z"}"#

    func testLimitAsNewestMessage() {
        let hit = Transcript.parseTail([user, limitLine, system, meta].joined(separator: "\n")).limitHit
        XCTAssertEqual(hit?.text, "You've hit your session limit · resets 3:10pm (Asia/Saigon)")
        XCTAssertEqual(hit?.at, "2026-10-15T05:51:47.455Z")
        XCTAssertEqual(hit?.weekly, false)
    }

    func testAMessageAfterTheLimitMeansItWasAnswered() {
        XCTAssertNil(Transcript.parseTail([user, limitLine, laterUser].joined(separator: "\n")).limitHit)
    }

    func testOlderFormatWithoutApiErrorKind() {
        let old = limitLine.replacingOccurrences(of: #""apiError":"usage_limit_reached","#, with: "")
        XCTAssertNotNil(Transcript.parseTail([user, old].joined(separator: "\n")).limitHit)
        let login = #"{"type":"assistant","isApiErrorMessage":true,"error":"authentication_failed","message":{"content":[{"type":"text","text":"Login expired · Please run /login"}]}}"#
        XCTAssertNil(Transcript.parseTail([user, login].joined(separator: "\n")).limitHit)
    }
}
