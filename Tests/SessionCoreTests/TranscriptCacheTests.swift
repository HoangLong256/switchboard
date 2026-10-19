import Foundation
@testable import SessionCore
import XCTest

final class TranscriptCacheTests: XCTestCase {
    var dir = ""

    override func setUp() {
        dir = NSTemporaryDirectory() + "transcripts-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: dir) }

    func write(_ sid: String, _ text: String) throws {
        try text.write(toFile: "\(dir)/\(sid).jsonl", atomically: true, encoding: .utf8)
    }

    static let line = #"{"type":"assistant","timestamp":"2026-10-19T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hello"}]}}"#

    func testParsesOncePerSizeAndForgetsSessionsNotReadBetweenSweeps() throws {
        try write("a", Self.line)
        try write("b", Self.line)
        let cache = TranscriptCache()
        XCTAssertEqual(cache.read(dir: dir, sessionId: "a").tail.lastAssistant?.text, "Hello")
        _ = cache.read(dir: dir, sessionId: "b")
        _ = cache.read(dir: dir, sessionId: "a")
        XCTAssertEqual(cache.parses, 2)
        XCTAssertEqual(cache.count, 2)
        cache.sweep()
        // both were read since the cache was made: both stay
        XCTAssertEqual(cache.count, 2)
        _ = cache.read(dir: dir, sessionId: "a")
        cache.sweep()
        // "b" (a session that ended) was not read in the last round
        XCTAssertEqual(cache.count, 1)
        _ = cache.read(dir: dir, sessionId: "a")
        XCTAssertEqual(cache.parses, 2, "a stays cached across sweeps")
        _ = cache.read(dir: dir, sessionId: "b")
        XCTAssertEqual(cache.parses, 3, "b is parsed again when it comes back")
    }

    func testRereadsWhenTheTranscriptGrows() throws {
        try write("a", Self.line)
        let cache = TranscriptCache()
        _ = cache.read(dir: dir, sessionId: "a")
        try write("a", Self.line + "\n" + Self.line.replacingOccurrences(of: "Hello", with: "Again"))
        XCTAssertEqual(cache.read(dir: dir, sessionId: "a").tail.lastAssistant?.text, "Again")
        XCTAssertEqual(cache.parses, 2)
    }
}
