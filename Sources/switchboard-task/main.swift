import Foundation
import SessionCore

// Keeps the handover of the Claude Code session it runs in (~/.claude/handover/<session>.md), which Switchboard
// shows in the Handover tab and as the session's task line. Claude runs it; see HandoverSetup.
let usage = """
usage: switchboard-task ["<task>"] [--state working|blocked|waiting|done] [--detail "<text>"]
                        [--body "<markdown>" | --body -] [--name <session>]
       switchboard-task --note "<text>" [--name <session>]
       switchboard-task --show [--name <session>]

  "<task>"     start a new task (state working; detail and body cleared)
  --state      blocked: the session needs you · waiting: awaiting feedback · done: finished
  --detail     one line under the task, e.g. the question when blocked
  --body       Markdown below: what changed, what is left, where to look (- reads it from stdin)
  --note       add an entry to the session's notes in Switchboard instead
  --show       print the current handover
  --name       the session (default: the Claude Code session this runs in)
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("switchboard-task: \(message)\n".utf8))
    exit(1)
}

var args = Array(CommandLine.arguments.dropFirst())
var change = HandoverFile.Change()
var name: String?
var note: String?
var show = false

func value(_ flag: String) -> String {
    guard !args.isEmpty else { fail("\(flag) needs a value") }
    return args.removeFirst()
}

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "-h", "--help": print(usage); exit(0)
    case "--state":
        let s = value(a).lowercased()
        guard HandoverFile.states.contains(s) else { fail("--state is one of \(HandoverFile.states.joined(separator: ", "))") }
        change.state = s
    case "--detail": change.detail = value(a)
    case "--body":
        let b = value(a)
        change.body = b == "-" ? String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) : b
    case "--note": note = value(a)
    case "--name": name = value(a)
    case "--show": show = true
    default:
        guard !a.hasPrefix("-"), change.task == nil else { fail("unknown option \(a)\n\n\(usage)") }
        let t = a.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { fail("the task is empty") }
        change.task = t
    }
}

let env = ProcessInfo.processInfo.environment
guard let session = name ?? HandoverFile.sessionName() ?? env["SWITCHBOARD_SESSION"] else {
    fail("not inside a Claude Code session; pass --name <session>")
}

if show {
    guard let p = HandoverFile.path(session), let text = try? String(contentsOfFile: p, encoding: .utf8) else {
        fail("no handover for \(session) yet")
    }
    print(text, terminator: "")
    exit(0)
}

if let note {
    guard Notes.validName(session) else { fail("“\(session)” can't be a notes name") }
    let dir = Notes.root()
    let path = "\(dir)/\(session).md"
    do {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let old = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .newlines) ?? ""
        let text = (old.isEmpty ? "" : old + Notes.separator) + note.trimmingCharacters(in: .newlines) + "\n"
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        print("note added for \(session)")
    } catch {
        fail(error.localizedDescription)
    }
    exit(0)
}

guard change != HandoverFile.Change() else { fail("nothing to change\n\n\(usage)") }
do {
    let path = try HandoverFile.write(session, change)
    print("handover updated: \(path)")
} catch {
    fail(error.localizedDescription)
}
