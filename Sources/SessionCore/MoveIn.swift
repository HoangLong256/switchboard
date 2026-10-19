import Darwin
import Foundation

/// Bringing a session that runs elsewhere (another terminal app, VS Code) into Switchboard: its terminal can't be
/// taken over, so the process there ends and the same conversation continues in Switchboard's tmux
/// (`claude --resume <id>`). Offline sessions resume the same way.
public enum MoveIn {
    /// `claude --resume <id> -n <name>`
    public static func resumeCommand(name: String, sessionId: String) -> String {
        "claude --resume \(SessionControl.shellQuote(sessionId)) -n \(SessionControl.shellQuote(name))"
    }

    /// The name to give the session: its own, without the "#pid" the registry adds to duplicates; a folder name
    /// for an unnamed one ("pid-123").
    public static func displayName(_ name: String, folder: String, taken: Set<String>) -> String {
        var n = name
        if let hash = n.lastIndex(of: "#"), n[n.index(after: hash)...].allSatisfy(\.isNumber), hash != n.startIndex {
            n = String(n[..<hash])
        }
        if n.hasPrefix("pid-"), n.dropFirst(4).allSatisfy(\.isNumber) {
            let s = Notes.suggestedName(folder: folder, taken: taken)
            return s.isEmpty ? "session" : s
        }
        return n
    }

    /// A tmux session name for it: no ":" (tmux's separator), and not one of the running tmux sessions.
    public static func tmuxName(_ name: String, taken: Set<String>) -> String {
        let base = name.replacingOccurrences(of: ":", with: "-")
        var n = base, i = 2
        while taken.contains(n) { n = "\(base)-\(i)"; i += 1 }
        return n
    }

    /// The app a process runs in ("Visual Studio Code", "iTerm", "Terminal"), from the first `.app` among its
    /// parent processes. Nil when none is found (ssh, launchd).
    public static func hostApp(of pid: Int) -> String? {
        var p = pid_t(truncatingIfNeeded: pid)
        for _ in 0..<12 {
            guard p > 1, let path = executablePath(p) else { return nil }
            if let app = appName(fromPath: path) { return app }
            guard let parent = parentPid(p), parent != p else { return nil }
            p = parent
        }
        return nil
    }

    /// "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper.app/…" → "Visual Studio Code"
    public static func appName(fromPath path: String) -> String? {
        guard let r = path.range(of: ".app/") ?? (path.hasSuffix(".app") ? path.range(of: ".app", options: .backwards) : nil)
        else { return nil }
        let name = (String(path[..<r.lowerBound]) as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    static func parentPid(_ pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
