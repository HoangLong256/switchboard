import Foundation

/// Claude Code's agent teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`), read from disk:
/// - `~/.claude/teams/<team>/config.json`: the team, its lead session and its members
/// - `~/.claude/teams/<team>/inboxes/<member>.json`: messages to that member (idle notices, task hand-offs, …)
/// - `~/.claude/tasks/<team>/*.json`: the shared task list
/// Shapes as documented (code.claude.com/docs/en/agent-teams) and seen in Claude Code 2.1.302. Every field is read
/// leniently: the feature is experimental, so a missing or renamed field leaves that detail out instead of
/// dropping the team.
public struct Team: Equatable, Sendable, Identifiable {
    public struct Member: Equatable, Sendable, Identifiable {
        public let name: String
        public let agentId: String?
        public let agentType: String?
        /// Claude Code's color name for the member ("blue", "green", …)
        public let color: String?
        /// "in-process", "leader" or a tmux pane id ("%7")
        public let tmuxPaneId: String?
        public let cwd: String?
        public let joinedAt: Date?
        public var id: String { name }

        public var isLead: Bool { agentType == "team-lead" || tmuxPaneId == "leader" }
        /// runs in its own tmux pane (split-pane mode), so its terminal can be shown
        public var paneId: String? { tmuxPaneId?.hasPrefix("%") == true ? tmuxPaneId : nil }
    }

    public struct Task: Equatable, Sendable, Identifiable {
        public enum Status: String, Sendable { case pending, inProgress = "in_progress", completed }
        public let id: String
        public let subject: String
        public let description: String?
        /// "Running tests" while in progress
        public let activeForm: String?
        public let status: Status
        public let owner: String?
        public let blockedBy: [String]
    }

    public struct Message: Equatable, Sendable, Identifiable {
        public let id: String
        public let from: String
        /// whose inbox it is in
        public let to: String
        /// `type` of a structured message (`idle_notification`, `task_assignment`, `shutdown_request`, …), nil for plain text
        public let kind: String?
        /// short text to show: the message's summary, or the start of its text
        public let summary: String
        public let at: Date?
        public let read: Bool
    }

    public let name: String
    public let leadSessionId: String?
    public let createdAt: Date?
    public let members: [Member]
    public var tasks: [Task] = []
    /// all inboxes, newest first
    public var messages: [Message] = []
    public var id: String { name }

    /// Members without the lead.
    public var teammates: [Member] { members.filter { !$0.isLead } }

    // MARK: Derived state

    public enum MemberState: Equatable, Sendable {
        case working
        case idle(reason: String?)
        case stopped
    }

    /// From the messages: shut down (approved or terminated) wins, then the newest idle notice versus newer work
    /// (a task assigned to it, or a task it owns in progress).
    public func state(of member: Member) -> MemberState {
        let mine = messages.filter { $0.from == member.name || $0.to == member.name }
        let shutDown = mine.contains { $0.from == member.name && $0.kind == "shutdown_approved" }
        let terminated = messages.contains { $0.kind == "teammate_terminated" && $0.summary.contains(member.name) }
        if shutDown || terminated { return .stopped }
        let idle = mine.first { $0.kind == "idle_notification" && $0.from == member.name }
        let work = mine.first { $0.kind == "task_assignment" && $0.to == member.name }
        if let idle, (work == nil || (idle.at ?? .distantPast) >= (work?.at ?? .distantPast)),
           currentTask(of: member) == nil {
            return .idle(reason: idle.summary.isEmpty ? nil : idle.summary)
        }
        return .working
    }

    public func currentTask(of member: Member) -> Task? {
        tasks.first { $0.owner == member.name && $0.status == .inProgress }
    }

    public func tasks(_ status: Task.Status) -> [Task] { tasks.filter { $0.status == status } }

    /// Ids of the tasks `task` still waits for (its blockers that aren't completed).
    public func openBlockers(of task: Task) -> [String] {
        task.blockedBy.filter { id in tasks.first { $0.id == id }?.status != .completed }
    }
}

public enum TeamReader {
    public static func defaultTeamsDir(home: String = NSHomeDirectory()) -> String { "\(home)/.claude/teams" }
    public static func defaultTasksDir(home: String = NSHomeDirectory()) -> String { "\(home)/.claude/tasks" }

    /// Every team with a readable config, with its tasks and messages.
    public static func load(teamsDir: String, tasksDir: String) -> [Team] {
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: teamsDir)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        return names.compactMap { dir in
            guard var team = config("\(teamsDir)/\(dir)/config.json", fallbackName: dir) else { return nil }
            team.tasks = tasks("\(tasksDir)/\(team.name)")
            if team.tasks.isEmpty, dir != team.name { team.tasks = tasks("\(tasksDir)/\(dir)") }
            team.messages = messages("\(teamsDir)/\(dir)/inboxes")
            return team
        }
    }

    static func config(_ path: String, fallbackName: String) -> Team? {
        guard let j = json(path) as? [String: Any] else { return nil }
        let members: [Team.Member] = (j["members"] as? [[String: Any]] ?? []).compactMap { m in
            guard let name = m["name"] as? String, !name.isEmpty else { return nil }
            return Team.Member(name: name, agentId: m["agentId"] as? String, agentType: m["agentType"] as? String,
                               color: m["color"] as? String, tmuxPaneId: m["tmuxPaneId"] as? String,
                               cwd: m["cwd"] as? String, joinedAt: date(m["joinedAt"]))
        }
        return Team(name: (j["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName,
                    leadSessionId: j["leadSessionId"] as? String, createdAt: date(j["createdAt"]), members: members)
    }

    static func tasks(_ dir: String) -> [Team.Task] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        let list: [Team.Task] = files.compactMap { f in
            guard let j = json("\(dir)/\(f)") as? [String: Any],
                  let subject = j["subject"] as? String else { return nil }
            let id = (j["id"] as? String) ?? (j["id"] as? NSNumber)?.stringValue ?? String(f.dropLast(5))
            return Team.Task(id: id, subject: subject, description: j["description"] as? String,
                             activeForm: j["activeForm"] as? String,
                             status: Team.Task.Status(rawValue: j["status"] as? String ?? "") ?? .pending,
                             owner: (j["owner"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                             blockedBy: (j["blockedBy"] as? [Any] ?? []).map { "\($0)" })
        }
        // numeric ids in order ("2" before "10")
        return list.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func messages(_ dir: String) -> [Team.Message] {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }
        var out: [Team.Message] = []
        for f in files {
            let to = String(f.dropLast(5))
            for (i, m) in (json("\(dir)/\(f)") as? [[String: Any]] ?? []).enumerated() {
                guard let from = m["from"] as? String else { continue }
                let text = m["text"] as? String ?? ""
                // structured messages carry JSON in `text`
                let inner = text.hasPrefix("{") ? (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] : nil
                let kind = (m["type"] as? String) ?? (inner?["type"] as? String)
                let summary = (m["summary"] as? String) ?? (inner?["summary"] as? String) ?? (inner?["reason"] as? String)
                    ?? (inner == nil ? text : (inner?["result"] as? String ?? ""))
                out.append(Team.Message(id: "\(to)#\(i)", from: from, to: to, kind: kind,
                                        summary: String(summary.prefix(300)), at: date(m["timestamp"]),
                                        read: m["read"] as? Bool ?? false))
            }
        }
        return out.sorted { ($0.at ?? .distantPast) > ($1.at ?? .distantPast) }
    }

    static func json(_ path: String) -> Any? {
        FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) }
    }

    /// ISO string or epoch (seconds or milliseconds).
    static func date(_ v: Any?) -> Date? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() {
            let d = n.doubleValue
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        }
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
