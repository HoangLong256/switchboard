import Foundation
@testable import SessionCore
import XCTest

final class HandoverFileTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNewTaskStartsWorkingAndClearsTheRest() {
        let old = "---\ntask: Old\ndetail: why\nstate: blocked\nproject: shop\n---\n\nOld notes\n"
        let text = HandoverFile.updated(old, with: .init(task: "Fix the login bug"), now: now)
        let p = Handover.parseFrontmatter(text)
        XCTAssertEqual(p.fields["task"], "Fix the login bug")
        XCTAssertEqual(p.fields["state"], "working")
        XCTAssertNil(p.fields["detail"])
        XCTAssertEqual(p.fields["project"], "shop")
        XCTAssertEqual(p.fields["updated"], "2027-01-15T08:00:00.000Z")
        XCTAssertEqual(p.body.trimmingCharacters(in: .whitespacesAndNewlines), "")
    }

    func testStateAndDetailKeepTheTaskAndBody() {
        let old = HandoverFile.updated(nil, with: .init(task: "Retry webhooks", body: "Started"), now: now)
        let text = HandoverFile.updated(old, with: .init(detail: "Retry forever?", state: "blocked"), now: now)
        let p = Handover.parseFrontmatter(text)
        XCTAssertEqual(p.fields["task"], "Retry webhooks")
        XCTAssertEqual(p.fields["state"], "blocked")
        XCTAssertEqual(p.fields["detail"], "Retry forever?")
        XCTAssertEqual(p.body.trimmingCharacters(in: .whitespacesAndNewlines), "Started")
    }

    func testValuesStayOnOneLine() {
        let text = HandoverFile.updated(nil, with: .init(task: "a\nb", detail: "c\r\nd"), now: now)
        XCTAssertTrue(text.contains("task: a b\n"))
        XCTAssertTrue(text.contains("detail: c  d\n"))
    }

    func testWriteIsReadBackByTheApp() throws {
        let dir = NSTemporaryDirectory() + "handover-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try HandoverFile.write("api", .init(task: "Retry webhooks"), dir: dir, now: now)
        try HandoverFile.write("api", .init(detail: "Retry forever?", state: "blocked"), dir: dir, now: now)
        let e = Handover.readDir(dir)["api"]
        XCTAssertEqual(e?.task, "Retry webhooks")
        XCTAssertEqual(e?.state, "blocked")
        XCTAssertEqual(e?.detail, "Retry forever?")
        XCTAssertNotNil(e?.updatedAt)
        XCTAssertThrowsError(try HandoverFile.write("../x", .init(task: "t"), dir: dir))
    }

    func testSessionNameFromTheNearestRegistryEntry() throws {
        let dir = NSTemporaryDirectory() + "sessions-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertNil(HandoverFile.sessionName(sessionsDir: dir))
        // this process's parent stands in for the Claude process
        try #"{"pid":1,"name":"blog.01"}"#.write(toFile: "\(dir)/\(getppid()).json", atomically: true, encoding: .utf8)
        XCTAssertEqual(HandoverFile.sessionName(sessionsDir: dir), "blog.01")
    }
}

final class HandoverSetupTests: XCTestCase {
    let helper = "/Users/me/.switchboard/bin/switchboard-task"

    func testInstructionsAreAddedOnceAndRemovedCleanly() {
        let mine = "# My rules\n\nBe brief.\n"
        let added = HandoverSetup.addingInstructions(to: mine, helper: helper)
        XCTAssertTrue(added.hasPrefix(mine.trimmingCharacters(in: .newlines)))
        XCTAssertTrue(HandoverSetup.hasInstructions(added))
        XCTAssertTrue(added.contains("`\(helper) --state blocked"))
        // again: replaced, not doubled
        let twice = HandoverSetup.addingInstructions(to: added, helper: helper)
        XCTAssertEqual(twice.components(separatedBy: "switchboard:handover:start").count, 2)
        XCTAssertEqual(HandoverSetup.removingInstructions(from: twice), mine)
        XCTAssertEqual(HandoverSetup.removingInstructions(from: HandoverSetup.addingInstructions(to: "", helper: helper)), "")
    }

    func testAllowRuleIsAddedOnceAndRemoved() {
        let rule = HandoverSetup.allowRule(helper: helper)
        XCTAssertEqual(rule, "Bash(\(helper):*)")
        let start: [String: Any] = ["model": "opus", "permissions": ["allow": ["Bash(git status)"], "deny": ["Read(.env)"]]]
        let added = HandoverSetup.addingAllow(HandoverSetup.addingAllow(start, rule: rule), rule: rule)
        let perms = added["permissions"] as? [String: Any]
        XCTAssertEqual(perms?["allow"] as? [String], ["Bash(git status)", rule])
        XCTAssertEqual(perms?["deny"] as? [String], ["Read(.env)"])
        XCTAssertEqual(added["model"] as? String, "opus")
        let removed = HandoverSetup.removingAllow(added, rule: rule)
        XCTAssertEqual((removed["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(git status)"])
    }
}
