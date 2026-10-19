import SessionCore
import XCTest

final class ModelNameTests: XCTestCase {
    func testShortNames() {
        XCTAssertEqual(ModelName.short("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelName.short("claude-haiku-4-5-20251001"), "Haiku 4.5")
        XCTAssertEqual(ModelName.short("claude-fable-5-1"), "Fable 5.1")
        XCTAssertEqual(ModelName.short("claude-sonnet-5-5[1m]"), "Sonnet 5.5 (1M)")
        XCTAssertEqual(ModelName.short("Opus 5.5"), "Opus 5.5")
    }

    func testTranscriptTailKeepsTheNewestRealModel() {
        let lines = [
            #"{"type":"assistant","message":{"model":"claude-opus-5-5","content":[{"type":"text","text":"a"}]}}"#,
            #"{"type":"assistant","message":{"model":"claude-sonnet-5-5","content":[{"type":"text","text":"b"}]}}"#,
            #"{"type":"assistant","message":{"model":"<synthetic>","content":[{"type":"text","text":"limit"}]}}"#,
        ]
        XCTAssertEqual(Transcript.parseTail(lines.joined(separator: "\n")).model, "claude-sonnet-5-5")
    }
}

final class SessionGroupsTests: XCTestCase {
    func testGroupsKeepTheOrderOfTheirFirstItem() {
        let g = SessionGroups.split(["b1", "a1", "b2", "c1", "a2"]) { String($0.prefix(1)) }
        XCTAssertEqual(g.map(\.key), ["b", "a", "c"])
        XCTAssertEqual(g.map(\.items), [["b1", "b2"], ["a1", "a2"], ["c1"]])
    }
}

final class SuggestedNameTests: XCTestCase {
    func testFolderNameBecomesAValidUnusedName() {
        XCTAssertEqual(Notes.suggestedName(folder: "/x/switchboard", taken: []), "switchboard")
        XCTAssertEqual(Notes.suggestedName(folder: "/x/Personal Projects", taken: []), "personal-projects")
        XCTAssertEqual(Notes.suggestedName(folder: "/x/Café (old)", taken: []), "cafe-old")
        XCTAssertEqual(Notes.suggestedName(folder: "/x/app", taken: ["app", "app-2"]), "app-3")
        XCTAssertEqual(Notes.suggestedName(folder: "/x/日本", taken: []), "")
    }
}
