import Foundation
@testable import SessionCore
import XCTest

final class UsageScannerTests: XCTestCase {
    var projects = ""
    let now = Date()
    var calendar = Calendar.current

    override func setUp() {
        projects = NSTemporaryDirectory() + "usage-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: "\(projects)/-Users-me-app", withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: projects) }

    func response(_ id: String, session: String, output: Int, at: Date? = nil) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = f.string(from: at ?? now)
        return #"{"type":"assistant","sessionId":"\#(session)","timestamp":"\#(stamp)","requestId":"req_\#(id)","cwd":"/Users/me/app","message":{"id":"msg_\#(id)","model":"claude-opus-5-5","usage":{"input_tokens":10,"output_tokens":\#(output),"cache_creation_input_tokens":0,"cache_read_input_tokens":100}}}"#
    }

    func append(_ session: String, _ lines: [String]) throws {
        let path = "\(projects)/-Users-me-app/\(session).jsonl"
        let h = FileHandle(forWritingAtPath: path) ?? {
            FileManager.default.createFile(atPath: path, contents: nil)
            return FileHandle(forWritingAtPath: path)!
        }()
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    func testCountsEachResponseOncePerSessionAndDay() throws {
        try append("s1", [response("a", session: "s1", output: 5), response("b", session: "s1", output: 7)])
        try append("s2", [response("c", session: "s2", output: 1)])
        let scanner = UsageScanner(projectsDir: projects, devRoot: "/Users/me", calendar: calendar)
        let stats = scanner.scan(now: now)
        XCTAssertEqual(stats.today.output, 13)
        XCTAssertEqual(stats.bySessionId["s1"]?.output, 12)
        XCTAssertEqual(stats.bySessionId["s2"]?.output, 1)
        XCTAssertEqual(stats.projects(.today).first?.name, "app")
        XCTAssertEqual(scanner.trackedFiles, 2)
    }

    func testRescanOnlyReadsWhatWasAppendedAndKeepsTheSameNumbers() throws {
        try append("s1", [response("a", session: "s1", output: 5)])
        let scanner = UsageScanner(projectsDir: projects, devRoot: "/Users/me", calendar: calendar)
        let first = scanner.scan(now: now)
        XCTAssertEqual(first.today.output, 5)
        // a second scan with nothing new gives the same stats (the interned strings compare equal)
        XCTAssertEqual(scanner.scan(now: now), first)
        // the same response streamed again with more output, then a new one
        try append("s1", [response("a", session: "s1", output: 9), response("b", session: "s1", output: 2)])
        let second = scanner.scan(now: now.addingTimeInterval(1))
        XCTAssertEqual(second.today.output, 11)
        XCTAssertEqual(second.bySessionId["s1"]?.cacheRead, 200)
    }

    func testOldRecordsFallOutOfTheWindow() throws {
        let old = calendar.date(byAdding: .day, value: -40, to: now)!
        try append("s1", [response("a", session: "s1", output: 5, at: old), response("b", session: "s1", output: 3)])
        let scanner = UsageScanner(projectsDir: projects, devRoot: "/Users/me", calendar: calendar)
        let stats = scanner.scan(now: now)
        XCTAssertEqual(stats.last30Days.output, 3)
        XCTAssertEqual(stats.bySessionId["s1"]?.output, 3)
    }
}
