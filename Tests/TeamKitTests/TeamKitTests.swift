import TeamKit
import XCTest

final class TeamReaderTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("teams-\(UUID().uuidString)").path
        let team = "session-c3fa133f"
        try write("teams/\(team)/config.json", """
        {"name":"\(team)","createdAt":1792340000000,"leadAgentId":"team-lead@\(team)","leadSessionId":"c3fa133f-aaaa",
         "members":[
          {"agentId":"team-lead@\(team)","name":"team-lead","agentType":"team-lead","color":"blue","tmuxPaneId":"leader","cwd":"/r"},
          {"agentId":"researcher@\(team)","name":"researcher","agentType":"general-purpose","color":"green","tmuxPaneId":"in-process","cwd":"/r"},
          {"agentId":"tester@\(team)","name":"tester","color":"yellow","tmuxPaneId":"%7","cwd":"/r"},
          {"name":"","color":"red"}
         ]}
        """)
        try write("tasks/\(team)/1.json", #"{"id":"1","subject":"Read the docs","status":"completed","owner":"researcher","blocks":["2"],"blockedBy":[]}"#)
        try write("tasks/\(team)/2.json", #"{"id":"2","subject":"Write tests","activeForm":"Writing tests","status":"in_progress","owner":"tester","blockedBy":["1"]}"#)
        try write("tasks/\(team)/10.json", #"{"id":"10","subject":"Ship","status":"pending"}"#)
        try write("tasks/\(team)/.highwatermark", "10")
        let idle = #"{\"type\":\"idle_notification\",\"idleReason\":\"available\",\"summary\":\"Docs summarized\"}"#
        try write("teams/\(team)/inboxes/team-lead.json", """
        [{"from":"researcher","text":"\(idle)","timestamp":"2026-10-18T10:05:00.000Z","read":false},
         {"from":"tester","text":"Started on the tests","summary":"started","timestamp":"2026-10-18T10:06:00Z","read":true}]
        """)
        try write("teams/\(team)/inboxes/researcher.json", """
        [{"from":"team-lead","text":"{\\"type\\":\\"task_assignment\\",\\"taskId\\":\\"1\\",\\"summary\\":\\"Read the docs\\"}","timestamp":"2026-10-18T10:00:00Z"}]
        """)
        try write("teams/broken/config.json", "{not json")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: home) }

    private func write(_ rel: String, _ text: String) throws {
        let url = URL(fileURLWithPath: "\(home!)/\(rel)")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func load() -> [Team] { TeamReader.load(teamsDir: "\(home!)/teams", tasksDir: "\(home!)/tasks") }

    func testReadsConfigSkippingBrokenTeamsAndNamelessMembers() throws {
        let teams = load()
        XCTAssertEqual(teams.map(\.name), ["session-c3fa133f"])
        let t = try XCTUnwrap(teams.first)
        XCTAssertEqual(t.leadSessionId, "c3fa133f-aaaa")
        XCTAssertEqual(t.createdAt, Date(timeIntervalSince1970: 1_792_340_000))
        XCTAssertEqual(t.members.map(\.name), ["team-lead", "researcher", "tester"])
        XCTAssertEqual(t.teammates.map(\.name), ["researcher", "tester"])
        XCTAssertEqual(t.members[2].paneId, "%7")
        XCTAssertNil(t.members[1].paneId, "in-process teammates have no pane")
    }

    func testTasksInNumericOrder() throws {
        let t = try XCTUnwrap(load().first)
        XCTAssertEqual(t.tasks.map(\.id), ["1", "2", "10"])
        XCTAssertEqual(t.tasks[1].status, .inProgress)
        XCTAssertEqual(t.tasks[1].blockedBy, ["1"])
        XCTAssertEqual(t.tasks(.pending).map(\.subject), ["Ship"])
        XCTAssertEqual(t.openBlockers(of: t.tasks[1]), [], "task 1 is done, so task 2 waits for nothing")
    }

    func testMessagesParseStructuredText() throws {
        let t = try XCTUnwrap(load().first)
        XCTAssertEqual(t.messages.map(\.from), ["tester", "researcher", "team-lead"], "newest first")
        let idle = try XCTUnwrap(t.messages.first { $0.kind == "idle_notification" })
        XCTAssertEqual(idle.summary, "Docs summarized")
        XCTAssertEqual(idle.to, "team-lead")
        XCTAssertEqual(t.messages.first { $0.to == "researcher" }?.kind, "task_assignment")
    }

    func testMemberState() throws {
        let t = try XCTUnwrap(load().first)
        let researcher = try XCTUnwrap(t.members.first { $0.name == "researcher" })
        let tester = try XCTUnwrap(t.members.first { $0.name == "tester" })
        // idle notice (10:05) is newer than its assignment (10:00), and it owns no task in progress
        XCTAssertEqual(t.state(of: researcher), .idle(reason: "Docs summarized"))
        XCTAssertEqual(t.state(of: tester), .working)
        XCTAssertEqual(t.currentTask(of: tester)?.activeForm, "Writing tests")
    }

    func testMissingFoldersMeanNoTeams() {
        XCTAssertEqual(TeamReader.load(teamsDir: "/nonexistent/teams", tasksDir: "/nonexistent/tasks"), [])
    }
}
