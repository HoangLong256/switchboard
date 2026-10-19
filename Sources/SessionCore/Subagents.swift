import Foundation

/// A subagent a session started (the Agent/Task tool), from
/// `<projects>/<slug>/<sessionId>/subagents/agent-<id>.jsonl` and its `.meta.json`.
public struct Subagent: Equatable, Sendable, Identifiable {
    public let id: String
    /// "general-purpose", "Explore", "Plan" …
    public let type: String
    public let description: String
    public let model: String?
    /// started with run_in_background (the session carries on meanwhile)
    public let background: Bool
    /// branch of the git worktree it works in, if it got one
    public let worktreeBranch: String?
    public let startedAt: Date?
    /// last line written to its transcript
    public let lastActivity: Date?
    public let running: Bool
    /// what it does now (or did last)
    public let action: WorkAction?
    /// its transcript, for the activity view (`SubagentLog`)
    public var path: String = ""

    public init(id: String, type: String, description: String, model: String? = nil, background: Bool = false,
                worktreeBranch: String? = nil, startedAt: Date? = nil, lastActivity: Date? = nil, running: Bool,
                action: WorkAction? = nil) {
        self.id = id
        self.type = type
        self.description = description
        self.model = model
        self.background = background
        self.worktreeBranch = worktreeBranch
        self.startedAt = startedAt
        self.lastActivity = lastActivity
        self.running = running
        self.action = action
    }
}

public enum Subagents {
    /// A subagent quiet longer than this counts as finished even without a result in the transcript tail
    /// (its start or end may lie before the tail; a crashed session never reports one).
    public static let quietAfter: TimeInterval = 15 * 60
    /// Finished subagents are listed this long after their last activity.
    public static let keepFinished: TimeInterval = 2 * 60 * 60
    /// The parent transcript tail searched for results and task notifications.
    static let parentTailBytes = 512 * 1024

    public static func dir(projectDir: String, sessionId: String) -> String { "\(projectDir)/\(sessionId)/subagents" }

    /// The session's subagents, running first, then the most recent; finished ones only within `keepFinished`.
    /// `parentText`: the tail of the session's own transcript; `alive`: whether the session still runs.
    public static func load(projectDir: String, sessionId: String, parentText: String? = nil, alive: Bool,
                            now: Date = Date()) -> [Subagent] {
        let dir = dir(projectDir: projectDir, sessionId: sessionId)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let transcripts = files.filter { $0.hasPrefix("agent-") && $0.hasSuffix(".jsonl") }
        guard !transcripts.isEmpty else { return [] }

        // only read the parent when a subagent file is recent enough to matter
        let modified = Dictionary(uniqueKeysWithValues: transcripts.map { f in
            (f, (try? fm.attributesOfItem(atPath: "\(dir)/\(f)"))?[.modificationDate] as? Date ?? .distantPast)
        })
        guard modified.values.contains(where: { now.timeIntervalSince($0) <= keepFinished }) else { return [] }
        let parent = parentText ?? Transcript.readTailFollowingContinuation(dir: projectDir, sessionId: sessionId, bytes: parentTailBytes)
        let tasks = Transcript.taskStates(parent)
        let results = Transcript.toolResultIds(parent)

        var out: [Subagent] = []
        for f in transcripts {
            let id = String(f.dropFirst("agent-".count).dropLast(".jsonl".count))
            let mtime = modified[f] ?? .distantPast
            guard now.timeIntervalSince(mtime) <= keepFinished else { continue }
            let meta = (fm.contents(atPath: "\(dir)/agent-\(id).meta.json"))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let background = meta["requestShape"] as? String == "background" || tasks.running[id] != nil || tasks.finished.contains(id)
            let toolUseId = meta["toolUseId"] as? String
            let quiet = now.timeIntervalSince(mtime) > quietAfter
            let running: Bool
            if !alive {
                running = false
            } else if background {
                // a task notification ends it; a launch seen in the tail without one means it still runs
                running = !tasks.finished.contains(id) && (tasks.running[id] != nil || !quiet)
            } else {
                // a foreground agent ends when its tool call gets a result
                running = !(toolUseId.map(results.contains) ?? false) && !quiet
            }
            // attachments (file contents, tool output) can fill the last 64 KB, so look further back
            let tail = Transcript.parseTail(Transcript.readTail("\(dir)/\(f)", bytes: 256 * 1024))
            var agent = Subagent(
                id: id,
                type: (meta["agentType"] as? String).nonEmpty ?? "agent",
                description: (meta["description"] as? String).nonEmpty ?? firstPrompt("\(dir)/\(f)") ?? "Subagent",
                model: (meta["model"] as? String).nonEmpty,
                background: background,
                worktreeBranch: (meta["worktreeBranch"] as? String).nonEmpty,
                startedAt: firstTimestamp("\(dir)/\(f)"),
                lastActivity: mtime == .distantPast ? nil : mtime,
                running: running,
                action: tail.lastAction)
            agent.path = "\(dir)/\(f)"
            out.append(agent)
        }
        return out.sorted { a, b in
            if a.running != b.running { return a.running }
            return (a.lastActivity ?? .distantPast) > (b.lastActivity ?? .distantPast)
        }
    }

    // MARK: Head of a subagent transcript

    private static func head(_ path: String) -> [[String: Any]] {
        guard let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 16 * 1024)) ?? Data()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").prefix(4).compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    static func firstTimestamp(_ path: String) -> Date? {
        head(path).lazy.compactMap { ($0["timestamp"] as? String).flatMap(parseISO) }.first
    }

    /// The task it was given, for subagents without a meta file (older Claude Code): first line, shortened.
    static func firstPrompt(_ path: String) -> String? {
        for obj in head(path) where obj["type"] as? String == "user" {
            let text = Transcript.textOf((obj["message"] as? [String: Any])?["content"])
            if let line = text.split(separator: "\n").first.map(String.init).nonEmpty {
                return line.count > 80 ? String(line.prefix(79)) + "…" : line
            }
        }
        return nil
    }
}
