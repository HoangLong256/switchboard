import Foundation

/// What a subagent did, step by step, from its transcript: the task it got, its messages, its tool calls and
/// their results. For the activity view in the app.
public enum SubagentLog {
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Kind: Equatable, Sendable {
            /// the task it was given (the first user message)
            case prompt
            /// what it said
            case text
            /// a tool call; `result` holds what came back
            case tool
        }

        public let id: String
        public let kind: Kind
        public let at: Date?
        /// prompt or message text; for a tool: "Running tests", "Editing Store.swift"
        public let text: String
        /// tool name
        public let tool: String?
        /// command or path of a tool call
        public let detail: String?
        /// the tool's result, shortened; nil while it runs
        public var result: String?
        public var failed = false
    }

    /// Transcripts can be long; the newest part holds what matters.
    public static let maxBytes = 2 * 1024 * 1024
    /// Results are cut to this many characters (the view shows them on request).
    static let maxResult = 1500

    public static func load(_ path: String) -> [Entry] {
        parse(Transcript.readTail(path, bytes: maxBytes))
    }

    public static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        var toolIndex: [String: Int] = [:]
        var n = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any],
                  let message = obj["message"] as? [String: Any] else { continue }
            let type = obj["type"] as? String
            let at = (obj["timestamp"] as? String).flatMap(parseISO)
            let content = message["content"]
            n += 1
            if type == "user" {
                if let s = content as? String {
                    // the first plain user message is the task; later ones are notes injected by Claude Code
                    let kind: Entry.Kind = entries.contains { $0.kind == .prompt } ? .text : .prompt
                    if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, kind == .prompt {
                        entries.append(Entry(id: "u\(n)", kind: .prompt, at: at, text: s, tool: nil, detail: nil))
                    }
                    continue
                }
                for case let b as [String: Any] in content as? [Any] ?? [] {
                    switch b["type"] as? String {
                    case "tool_result":
                        guard let id = b["tool_use_id"] as? String, let i = toolIndex[id] else { continue }
                        let out = Transcript.textOf(b["content"])
                        entries[i].result = out.count > maxResult ? String(out.prefix(maxResult)) + "\n…" : out
                        entries[i].failed = b["is_error"] as? Bool == true
                    case "text" where !entries.contains { $0.kind == .prompt }:
                        if let s = (b["text"] as? String).nonEmpty {
                            entries.append(Entry(id: "u\(n)", kind: .prompt, at: at, text: s, tool: nil, detail: nil))
                        }
                    default: break
                    }
                }
            } else if type == "assistant" {
                for (k, item) in (content as? [Any] ?? []).enumerated() {
                    guard let b = item as? [String: Any] else { continue }
                    switch b["type"] as? String {
                    case "text":
                        if let s = (b["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                            entries.append(Entry(id: "a\(n).\(k)", kind: .text, at: at, text: s, tool: nil, detail: nil))
                        }
                    case "tool_use":
                        let action = Transcript.describe(b, at: nil, pending: true)
                        let id = b["id"] as? String ?? "a\(n).\(k)"
                        toolIndex[id] = entries.count
                        entries.append(Entry(id: id, kind: .tool, at: at, text: action.text, tool: action.tool, detail: action.detail))
                    default: break
                    }
                }
            }
        }
        return entries
    }
}
