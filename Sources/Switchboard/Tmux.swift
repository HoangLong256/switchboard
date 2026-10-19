import Foundation
import SessionCore

/// tmux calls. Sessions started from the app run on their own server (`tmux -L switchboard`), so its settings
/// never collide with a tmux you run yourself.
enum Tmux {
    static let path: String? = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static func target(_ name: String) -> String { SessionControl.target(name) }

    /// `SWITCHBOARD_TMUX` names another server (for trying things out).
    static let socket = ProcessInfo.processInfo.environment["SWITCHBOARD_TMUX"] ?? "switchboard"

    /// `-f` only applies when the server starts.
    static let config = """
    # written by Switchboard, overwritten on every start
    set -g status off
    set -g mouse on
    set -sg escape-time 0
    set -g history-limit 50000
    set -g default-terminal "tmux-256color"
    set -as terminal-features ",xterm-256color:RGB"
    set -s extended-keys on
    set -g focus-events on
    set -s set-clipboard on
    set -g aggressive-resize on
    """

    static let configPath: String = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Switchboard")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: "tmux.conf")
        try? config.write(to: file, atomically: true, encoding: .utf8)
        return file.path
    }()

    static var serverArgs: [String] { ["-L", socket, "-f", configPath] }

    static func attachArgs(_ name: String) -> [String] { serverArgs + ["attach-session", "-t", target(name)] }

    struct Panes: Equatable {
        /// tmux session → command running in front ("claude", "zsh", …)
        var commands: [String: String] = [:]
        /// pane ID ("%13") → tmux session
        var sessionOfPane: [String: String] = [:]
        /// tmux session → current folder of its first pane (folder of sessions without a Claude cwd)
        var paths: [String: String] = [:]
    }

    static func panes() -> Panes {
        let r = run(["list-panes", "-a", "-F", "#{session_name}\t#{pane_id}\t#{pane_current_command}\t#{pane_current_path}"])
        guard r.status == 0 else { return Panes() }   // no tmux server = no sessions
        var p = Panes()
        for line in r.output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { continue }
            if p.commands[parts[0]] == nil { p.commands[parts[0]] = parts[2]; p.paths[parts[0]] = parts[3] }
            p.sessionOfPane[parts[1]] = parts[0]
        }
        return p
    }

    /// Opens a shell in a new tmux session in the folder and pre-types `claude -n <name>` (without Enter: you can
    /// still change the line). Returns an error message or nil.
    /// `agentTeam` turns on Claude Code's experimental agent teams for this session only (env var); teammates in
    /// split-pane mode then open as panes of this tmux session.
    /// `environment`: more variables for the session (e.g. Claude Code's unattended retry mode).
    /// `start`: press Enter after typing `claude -n <name>`, so Claude Code starts right away.
    static func newSession(name: String, dir: String, agentTeam: Bool = false, environment: [String: String] = [:],
                           start: Bool = true) -> String? {
        scrubServer()
        var args = ["new-session", "-d", "-s", name, "-c", dir, "-e", "SWITCHBOARD_SESSION=\(name)"]
        if agentTeam { args += ["-e", "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1"] }
        for (k, v) in environment.sorted(by: { $0.key < $1.key }) { args += ["-e", "\(k)=\(v)"] }
        let r = run(args)
        guard r.status == 0 else { return r.output.isEmpty ? "tmux error \(r.status)" : r.output }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            let cmds = SessionControl.typeArgs(SessionControl.claudeCommand(name), into: name)
            for c in start ? cmds : [cmds[0]] { _ = run(c) }
        }
        return nil
    }

    /// Types the text and submits it with Enter (a short pause first, so Claude Code doesn't take the Enter as
    /// part of pasted text). Blocks briefly; don't call on the main thread. Returns an error message or nil.
    static func type(_ text: String, into name: String) -> String? {
        let cmds = SessionControl.typeArgs(text, into: name)
        let r = run(cmds[0])
        guard r.status == 0 else { return failure(r) }
        Thread.sleep(forTimeInterval: 0.15)
        let e = run(cmds[1])
        return e.status == 0 ? nil : failure(e)
    }

    /// Types text into the session without Enter (e.g. a file path from the folder sidebar).
    static func insert(_ text: String, into name: String) -> String? {
        let r = run(SessionControl.typeArgs(text, into: name)[0])
        return r.status == 0 ? nil : failure(r)
    }

    static func kill(_ name: String) -> String? {
        let r = run(SessionControl.killArgs(name))
        return r.status == 0 ? nil : failure(r)
    }

    private static func failure(_ r: (status: Int32, output: String)) -> String {
        r.output.isEmpty ? "tmux error \(r.status)" : r.output
    }

    /// Variables of a Claude session that must never leak into new sessions.
    static func isInherited(_ key: String) -> Bool {
        key.hasPrefix("CLAUDE") || key == "AI_AGENT" || key == "TMUX" || key == "TMUX_PANE"
    }

    /// The tmux server passes its global environment on to every new session, so clear the Claude variables first.
    static func scrubServer() {
        let r = run(["show-environment", "-g"])
        guard r.status == 0 else { return }
        for line in r.output.split(separator: "\n") {
            let key = String(line.split(separator: "=", maxSplits: 1).first ?? "")
            if isInherited(key) { _ = run(["set-environment", "-g", "-u", key]) }
        }
    }

    static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment.filter { !isInherited($0.key) }
        env["TERM"] = "xterm-256color"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        if let loginPath = LoginShell.path { env["PATH"] = loginPath }
        return env
    }

    static func environmentList() -> [String] { environment().map { "\($0.key)=\($0.value)" } }

    private static func run(_ args: [String]) -> (status: Int32, output: String) {
        guard let path else { return (-1, "tmux not installed") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = serverArgs + args
        p.environment = environment()
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self)
        return (p.terminationStatus, s.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
