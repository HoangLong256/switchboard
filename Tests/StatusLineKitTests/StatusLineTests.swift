import SessionCore
import StatusLineKit
import XCTest

final class StatusLineTests: XCTestCase {
    /// Shape as Claude Code 2.1.302 sends it (fields not used here left out)
    private let sample = """
    {"session_id":"c3fa133f-aaaa","model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},
     "cost":{"total_cost_usd":3.25,"total_duration_ms":600000,"total_lines_added":120,"total_lines_removed":8},
     "context_window":{"total_input_tokens":74000,"total_output_tokens":9000,"context_window_size":200000,
                       "used_percentage":37.4,"remaining_percentage":62.6},
     "effort":{"level":"high"},
     "rate_limits":{"five_hour":{"used_percentage":12,"resets_at":1792350000},
                    "seven_day":{"used_percentage":40.6,"resets_at":"2026-10-20T15:59:59.514977+00:00"}}}
    """

    func testWritesDataFilesAndLine() throws {
        let now = Date(timeIntervalSince1970: 1_792_340_000)
        let out = StatusLine.process(Data(sample.utf8), now: now)
        XCTAssertEqual(out.line, "Opus 5.5 · ctx 37% · 5h 12% · wk 41%")

        let usage = try XCTUnwrap(out.files["usage.json"])
        XCTAssertEqual(usage["written_at"] as? Double, 1_792_340_000)
        let limits = try XCTUnwrap(usage["rate_limits"] as? [String: [String: Double]])
        XCTAssertEqual(limits["five_hour"], ["used_percentage": 12, "resets_at": 1_792_350_000])
        // ISO with microseconds becomes epoch seconds
        XCTAssertEqual(limits["seven_day"]?["resets_at"], 1_792_511_999)

        XCTAssertEqual(out.files["context/c3fa133f-aaaa.json"]?["used_percentage"] as? Double, 37.4)
        let s = try XCTUnwrap(out.files["sessions/c3fa133f-aaaa.json"])
        XCTAssertEqual(s["cost_usd"] as? Double, 3.25)
        XCTAssertEqual(s["effort"] as? String, "high")
        XCTAssertEqual(s["context_input_tokens"] as? Double, 74000)
    }

    func testRoundTripThroughFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sl-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        StatusLine.write(StatusLine.process(Data(sample.utf8)), dataDir: dir)
        let s = try XCTUnwrap(SessionLine.load(dataDir: dir, sessionId: "c3fa133f-aaaa"))
        XCTAssertEqual(s.costUSD, 3.25)
        XCTAssertEqual(s.model, "Opus 5.5")
        XCTAssertEqual(s.contextTokens, 74000)
        XCTAssertEqual(s.linesAdded, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: "\(dir)/usage.json"))
    }

    func testNoLimitsNoSessionIdAndUnsafeIds() {
        let out = StatusLine.process(Data(#"{"session_id":"../../etc","model":{"display_name":"Sonnet"}}"#.utf8))
        XCTAssertEqual(out.line, "Sonnet")
        XCTAssertTrue(out.files.isEmpty, "no rate limits, and an id with .. is never used as a path")
        XCTAssertEqual(StatusLine.process(Data("not json".utf8)).line, "")
    }

    /// What the helper writes is what SessionCore's readers (`PlanLimits`, `ContextUsage`) understand.
    func testSessionCoreReadsTheFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sl-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let now = Date(timeIntervalSince1970: 1_792_340_000)
        StatusLine.write(StatusLine.process(Data(sample.utf8), now: now), dataDir: dir)
        let data = try XCTUnwrap(FileManager.default.contents(atPath: "\(dir)/usage.json"))
        let limits = try XCTUnwrap(PlanLimits.fromStatusLine(data))
        XCTAssertEqual(limits.source, .statusLine)
        XCTAssertEqual(limits.fiveHour?.percent, 12)
        XCTAssertEqual(limits.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_792_350_000))
        XCTAssertEqual(limits.sevenDay?.percent, 40.6)
        XCTAssertEqual(limits.fetchedAt, now)
        XCTAssertEqual(ContextUsage.percent(dataDir: dir, sessionId: "c3fa133f-aaaa"), 37.4)
    }
}
