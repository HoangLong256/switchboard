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

final class MoveInTests: XCTestCase {
    func testResumeCommandQuotes() {
        XCTAssertEqual(MoveIn.resumeCommand(name: "blog.01", sessionId: "6ac10705-aa"), "claude --resume 6ac10705-aa -n blog.01")
        XCTAssertEqual(MoveIn.resumeCommand(name: "my app", sessionId: "x"), "claude --resume x -n 'my app'")
    }

    func testDisplayNameDropsRegistrySuffixes() {
        XCTAssertEqual(MoveIn.displayName("api#4242", folder: "/x/api", taken: []), "api")
        XCTAssertEqual(MoveIn.displayName("pid-77042", folder: "/x/Front End", taken: []), "front-end")
        XCTAssertEqual(MoveIn.displayName("c#sharp", folder: "/x", taken: []), "c#sharp")
        XCTAssertEqual(MoveIn.displayName("frontend-monorepo-07", folder: "/x", taken: []), "frontend-monorepo-07")
    }

    func testTmuxNameIsFreeAndHasNoColon() {
        XCTAssertEqual(MoveIn.tmuxName("a:b", taken: []), "a-b")
        XCTAssertEqual(MoveIn.tmuxName("api", taken: ["api", "api-2"]), "api-3")
    }

    func testAppNameFromExecutablePath() {
        XCTAssertEqual(MoveIn.appName(fromPath: "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/Contents/MacOS/Code Helper"), "Visual Studio Code")
        XCTAssertEqual(MoveIn.appName(fromPath: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"), "Terminal")
        XCTAssertNil(MoveIn.appName(fromPath: "/bin/zsh"))
    }

    func testHostAppOfThisProcessDoesNotCrash() {
        _ = MoveIn.hostApp(of: Int(getpid()))
        XCTAssertNil(MoveIn.hostApp(of: 1))
    }
}
