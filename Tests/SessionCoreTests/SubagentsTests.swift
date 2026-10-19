import Foundation
@testable import SessionCore
import XCTest

final class SubagentsTests: XCTestCase {
    var project = ""
    let sid = "sess-1"
    let now = Date()

    override func setUp() {
        project = NSTemporaryDirectory() + "subagents-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: Subagents.dir(projectDir: project, sessionId: sid), withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(atPath: project) }

    /// A subagent with a meta file and a transcript last written `age` seconds ago.
    func agent(_ id: String, meta: String?, age: TimeInterval = 10, lines: [String]? = nil) throws {
        let dir = Subagents.dir(projectDir: project, sessionId: sid)
        let body = lines ?? [
            #"{"type":"user","timestamp":"2026-10-19T10:00:00.000Z","message":{"role":"user","content":"Find the retry code"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-19T10:00:05.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"retry"}}]}}"#,
        ]
        let path = "\(dir)/agent-\(id).jsonl"
        try body.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: path)
        if let meta { try meta.write(toFile: "\(dir)/agent-\(id).meta.json", atomically: true, encoding: .utf8) }
    }

    func load(parent: String, alive: Bool = true) -> [String: Subagent] {
        Dictionary(uniqueKeysWithValues: Subagents.load(projectDir: project, sessionId: sid, parentText: parent, alive: alive, now: now).map { ($0.id, $0) })
    }

    func testForegroundAgentRunsUntilItsToolCallHasAResult() throws {
        try agent("fg", meta: #"{"agentType":"Explore","description":"Find the retry code","toolUseId":"toolu_A","model":"haiku"}"#)
        var a = load(parent: "")["fg"]
        XCTAssertEqual(a?.running, true)
        XCTAssertEqual(a?.type, "Explore")
        XCTAssertEqual(a?.model, "haiku")
        XCTAssertEqual(a?.background, false)
        XCTAssertEqual(a?.action?.text, "Searching retry")
        let result = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_A","content":"done"}]}}"#
        a = load(parent: result)["fg"]
        XCTAssertEqual(a?.running, false)
    }

    func testBackgroundAgentRunsUntilItsNotification() throws {
        try agent("bg1", meta: #"{"agentType":"general-purpose","description":"Fix the bug","toolUseId":"toolu_B","requestShape":"background","worktreeBranch":"worktree-agent-bg1"}"#)
        let launched = #"{"type":"user","timestamp":"2026-10-19T10:00:00.000Z","toolUseResult":{"status":"async_launched","agentId":"bg1"},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_B","content":"Async agent launched"}]}}"#
        var a = load(parent: launched)["bg1"]
        // its tool call has a result at once, but it still runs
        XCTAssertEqual(a?.running, true)
        XCTAssertEqual(a?.background, true)
        XCTAssertEqual(a?.worktreeBranch, "worktree-agent-bg1")
        let done = #"{"type":"user","message":{"role":"user","content":"<task-notification><task-id>bg1</task-id><status>completed</status></task-notification>"}}"#
        a = load(parent: launched + "\n" + done)["bg1"]
        XCTAssertEqual(a?.running, false)
    }

    func testQuietOldOrDeadSessionsAreNotRunning() throws {
        try agent("quiet", meta: #"{"description":"Quiet","toolUseId":"toolu_Q"}"#, age: Subagents.quietAfter + 60)
        try agent("old", meta: #"{"description":"Old","toolUseId":"toolu_O"}"#, age: Subagents.keepFinished + 60)
        try agent("live", meta: #"{"description":"Live","toolUseId":"toolu_L"}"#)
        let found = load(parent: "")
        XCTAssertEqual(found["quiet"]?.running, false)
        XCTAssertNil(found["old"])
        XCTAssertEqual(found["live"]?.running, true)
        XCTAssertEqual(load(parent: "", alive: false)["live"]?.running, false)
    }

    func testRunningFirstAndDescriptionWithoutMeta() throws {
        try agent("a", meta: #"{"description":"Finished","toolUseId":"toolu_1"}"#, age: 120)
        try agent("b", meta: nil, age: 5)
        let result = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_1","content":"ok"}]}}"#
        let list = Subagents.load(projectDir: project, sessionId: sid, parentText: result, alive: true, now: now)
        XCTAssertEqual(list.map(\.id), ["b", "a"])
        XCTAssertEqual(list.first?.description, "Find the retry code")
        XCTAssertEqual(list.first?.type, "agent")
    }

    func testNoSubagentFolder() {
        XCTAssertTrue(Subagents.load(projectDir: project, sessionId: "none", parentText: "", alive: true, now: now).isEmpty)
    }
}

final class SubagentLogTests: XCTestCase {
    func testTaskMessagesToolsAndResults() {
        let lines = [
            #"{"type":"user","timestamp":"2026-10-19T10:00:00.000Z","message":{"role":"user","content":"Find the retry code"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-19T10:00:02.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Searching."},{"type":"tool_use","id":"t1","name":"Grep","input":{"pattern":"retry"}}]}}"#,
            #"{"type":"user","timestamp":"2026-10-19T10:00:03.000Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"sender.go:12"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-10-19T10:00:04.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"go test ./...","description":"Run tests"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":[{"type":"text","text":"FAIL"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Edit","input":{"file_path":"/x/sender.go"}}]}}"#,
            #"{"type":"attachment","attachment":{}}"#,
        ]
        let e = SubagentLog.parse(lines.joined(separator: "\n"))
        XCTAssertEqual(e.map(\.kind), [.prompt, .text, .tool, .tool, .tool])
        XCTAssertEqual(e[0].text, "Find the retry code")
        XCTAssertEqual(e[2].text, "Searching retry")
        XCTAssertEqual(e[2].result, "sender.go:12")
        XCTAssertEqual(e[3].text, "Run tests")
        XCTAssertEqual(e[3].detail, "go test ./...")
        XCTAssertEqual(e[3].result, "FAIL")
        XCTAssertTrue(e[3].failed)
        // still running: no result yet
        XCTAssertEqual(e[4].tool, "Edit")
        XCTAssertNil(e[4].result)
    }

    func testLongResultsAreShortened() {
        let long = String(repeating: "x", count: 5000)
        let lines = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"\#(long)"}]}}"#,
        ]
        let r = SubagentLog.parse(lines.joined(separator: "\n")).first?.result ?? ""
        XCTAssertTrue(r.count < 1600)
        XCTAssertTrue(r.hasSuffix("…"))
    }
}
