import Darwin
import Foundation

/// Writing `~/.claude/handover/<session>.md`, the file the Handover tab and the task line of a session show:
/// frontmatter (`task`, `detail`, `state`, `updated`) and Markdown below it. `switchboard-task` uses this from
/// inside a session.
public enum HandoverFile {
    /// What Switchboard does with a state: `blocked` puts the session under "needs you", `waiting` shows
    /// "awaiting feedback"; `working` and `done` are shown as they are.
    public static let states = ["working", "blocked", "waiting", "done"]

    /// Changes to apply; nil leaves a field as it is. `task` starts a new task: detail, state and body reset
    /// unless given too.
    public struct Change: Equatable, Sendable {
        public var task: String?
        public var detail: String?
        public var state: String?
        public var body: String?

        public init(task: String? = nil, detail: String? = nil, state: String? = nil, body: String? = nil) {
            self.task = task
            self.detail = detail
            self.state = state
            self.body = body
        }
    }

    /// The new file text from the old one (nil = none yet).
    public static func updated(_ old: String?, with change: Change, now: Date = Date()) -> String {
        let parsed = old.map(Handover.parseFrontmatter) ?? (fields: [:], body: "")
        var fields = parsed.fields
        var body = parsed.body
        if let task = change.task {
            fields["task"] = task
            fields["detail"] = nil
            fields["state"] = "working"
            body = ""
        }
        if let d = change.detail { fields["detail"] = d.isEmpty ? nil : d }
        if let s = change.state { fields["state"] = s }
        if let b = change.body { body = b }
        fields["updated"] = isoString(ms: now.timeIntervalSince1970 * 1000)
        return render(fields, body: body)
    }

    /// Known fields first, in a fixed order; values are kept on one line.
    static func render(_ fields: [String: String], body: String) -> String {
        let order = ["task", "detail", "state", "updated", "project"]
        let keys = order.filter { fields[$0] != nil } + fields.keys.filter { !order.contains($0) }.sorted()
        var out = "---\n"
        for k in keys {
            let v = fields[k]!.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            out += "\(k): \(v)\n"
        }
        out += "---\n"
        let b = body.trimmingCharacters(in: .newlines)
        return b.isEmpty ? out : out + "\n" + b + "\n"
    }

    public static func path(_ name: String, dir: String = Handover.defaultDir) -> String? {
        Handover.isSafeName(name) ? "\(dir)/\(name).md" : nil
    }

    /// Applies the change to the session's file (created if missing). Returns the path.
    @discardableResult
    public static func write(_ name: String, _ change: Change, dir: String = Handover.defaultDir, now: Date = Date()) throws -> String {
        guard let path = path(name, dir: dir) else {
            throw NSError(domain: "switchboard-task", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "“\(name)” can't be a handover name (letters, digits, . _ - only)"])
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let old = try? String(contentsOfFile: path, encoding: .utf8)
        try updated(old, with: change, now: now).write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    // MARK: Which session

    /// The Claude Code session a command runs in: the nearest parent process with a registry entry
    /// (`~/.claude/sessions/<pid>.json`), by its name. Claude runs commands as its child processes.
    public static func sessionName(from pid: Int32 = getpid(), sessionsDir: String = "\(StateBuilder.defaultClaudeHome)/sessions") -> String? {
        var p = pid
        for _ in 0..<16 {
            if let data = FileManager.default.contents(atPath: "\(sessionsDir)/\(p).json"),
               let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let name = j["name"] as? String, !name.isEmpty {
                return name
            }
            guard p > 1, let parent = MoveIn.parentPid(p), parent != p else { return nil }
            p = parent
        }
        return nil
    }
}

/// Setting up `switchboard-task` for Claude Code: a marked section in `~/.claude/CLAUDE.md` that tells Claude to
/// keep its handover, and a permission rule so the command runs without asking. Pure text and JSON changes;
/// the app does the file work (with backups).
public enum HandoverSetup {
    static let start = "<!-- switchboard:handover:start -->"
    static let end = "<!-- switchboard:handover:end -->"

    /// The CLAUDE.md section, with the helper's full path.
    public static func instructions(helper: String) -> String {
        """
        \(start)
        ## Handover (Switchboard)

        Keep a short handover for this session with `\(helper)`. Switchboard shows it next to the session.

        - When you start a task, run `\(helper) "<the task in a few words>"`.
        - When you need a decision from the user, run `\(helper) --state blocked --detail "<the question>"`.
        - When you finish, run `\(helper) --state done --body "<what changed, what is left, where to look>"`.

        Keep the task under 80 characters. Update the body when the work changes direction. You don't need to
        tell the user about these updates.
        \(end)
        """
    }

    /// The permission rule that lets Claude run the helper without asking.
    public static func allowRule(helper: String) -> String { "Bash(\(helper):*)" }

    public static func hasInstructions(_ claudeMd: String) -> Bool { claudeMd.contains(start) }

    /// Puts the section into CLAUDE.md, replacing an older one.
    public static func addingInstructions(to claudeMd: String, helper: String) -> String {
        let section = instructions(helper: helper)
        let rest = removingInstructions(from: claudeMd).trimmingCharacters(in: .newlines)
        return rest.isEmpty ? section + "\n" : rest + "\n\n" + section + "\n"
    }

    public static func removingInstructions(from claudeMd: String) -> String {
        guard let s = claudeMd.range(of: start), let e = claudeMd.range(of: end, range: s.upperBound..<claudeMd.endIndex)
        else { return claudeMd }
        var out = claudeMd
        out.removeSubrange(s.lowerBound..<e.upperBound)
        // no gap left behind
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        let trimmed = out.trimmingCharacters(in: .newlines)
        return trimmed.isEmpty ? "" : trimmed + "\n"
    }

    /// settings.json with the rule in `permissions.allow` (once).
    public static func addingAllow(_ settings: [String: Any], rule: String) -> [String: Any] {
        var s = settings
        var perms = s["permissions"] as? [String: Any] ?? [:]
        var allow = perms["allow"] as? [String] ?? []
        if !allow.contains(rule) { allow.append(rule) }
        perms["allow"] = allow
        s["permissions"] = perms
        return s
    }

    public static func removingAllow(_ settings: [String: Any], rule: String) -> [String: Any] {
        var s = settings
        guard var perms = s["permissions"] as? [String: Any], var allow = perms["allow"] as? [String] else { return s }
        allow.removeAll { $0 == rule }
        perms["allow"] = allow
        s["permissions"] = perms
        return s
    }
}
