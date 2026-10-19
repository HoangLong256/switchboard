import Foundation
import Observation
import SessionCore
import StatusLineKit

/// Plan limits (5 hours / week), token usage from the transcripts, and per-session cost from the status line.
/// Reading happens on its own serial queue; the first transcript scan
/// takes a few seconds, later ones only read what was appended.
@MainActor
@Observable
final class UsageStore {
    private(set) var limits: PlanLimits?
    private(set) var stats: UsageStats?
    /// session id → what the status line reported last
    private(set) var lines: [String: SessionLine] = [:]
    private(set) var setup = StatusLineSetup.State.unknown

    nonisolated static let dataDir = AppData.dir

    @ObservationIgnored private let scanner = UsageScanner()
    @ObservationIgnored private let queue = DispatchQueue(label: "switchboard.usage", qos: .utility)
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var dataWatcher: Watcher?
    @ObservationIgnored private var transcriptWatcher: Watcher?

    init() {
        reloadFiles()
        rescan()
        // the status line writes into ~/.switchboard on every update of any session
        dataWatcher = Watcher(paths: [Self.dataDir], delay: 1) { [weak self] in
            Task { @MainActor in self?.reloadFiles() }
        }
        // transcripts change all the time: at most one scan per 10 s from events
        transcriptWatcher = Watcher(paths: ["\(StateBuilder.defaultClaudeHome)/projects"], delay: 10) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        // ~/.claude.json and settings.json live outside the watched folders
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.reloadFiles()
                self?.rescan()
            }
        }
    }

    /// Limits without windows whose reset has passed.
    func current(now: Date) -> PlanLimits? { limits?.droppingExpired(now: now) }

    /// Tokens of a session over the kept 31 days (main transcript and subagents).
    func tokens(_ s: Session) -> TokenCounts? { s.sessionId.flatMap { stats?.bySessionId[$0] } }
    func tokensToday(_ s: Session) -> TokenCounts? { s.sessionId.flatMap { stats?.bySessionIdToday[$0] } }
    func line(_ s: Session) -> SessionLine? { s.sessionId.flatMap { lines[$0] } }

    func reloadFiles() {
        queue.async { [weak self] in
            let l = PlanLimits.load()
            let sessionsDir = "\(Self.dataDir)/sessions"
            var m: [String: SessionLine] = [:]
            for f in (try? FileManager.default.contentsOfDirectory(atPath: sessionsDir)) ?? [] where f.hasSuffix(".json") {
                let id = String(f.dropLast(5))
                if let line = SessionLine.load(dataDir: Self.dataDir, sessionId: id) { m[id] = line }
            }
            let state = StatusLineSetup.state()
            Task { @MainActor in
                guard let self else { return }
                if self.limits != l { self.limits = l }
                if self.lines != m { self.lines = m }
                if self.setup != state { self.setup = state }
            }
        }
    }

    func rescan() {
        guard !scanning else { return }
        scanning = true
        let scanner = scanner
        queue.async { [weak self] in
            let s = scanner.scan()
            Task { @MainActor in
                guard let self else { return }
                self.scanning = false
                if self.stats != s { self.stats = s }
            }
        }
    }

    /// Installs the status line (after the user confirmed). Returns an error message or nil.
    func installStatusLine() -> String? {
        let err = StatusLineSetup.install()
        reloadFiles()
        return err
    }
}

/// Points Claude Code's `statusLine` at `switchboard-statusline`, the only source of live plan limits and of
/// per-session cost. Only on request: it changes `~/.claude/settings.json` (backed up first).
enum StatusLineSetup {
    enum State: Equatable {
        case unknown
        case notConfigured
        /// ours is set up
        case installed
        /// another status line command is configured; ours would replace it
        case other(String)
    }

    static let settingsPath = "\(StateBuilder.defaultClaudeHome)/settings.json"
    static let installedHelper = "\(UsageStore.dataDir)/bin/switchboard-statusline"

    /// The helper built next to the app's executable (`.build/<config>/` or `Switchboard.app/Contents/MacOS/`).
    static var bundledHelper: String? {
        let p = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("switchboard-statusline").path
        return p.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    static func state() -> State {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sl = j["statusLine"] as? [String: Any], let cmd = sl["command"] as? String, !cmd.isEmpty
        else { return .notConfigured }
        return cmd.contains("switchboard-statusline") ? .installed : .other(cmd)
    }

    /// Copies the helper to `~/.switchboard/bin`, backs up settings.json, then sets `statusLine`.
    static func install() -> String? {
        guard let helper = bundledHelper else { return "switchboard-statusline wasn't found next to the app. Build it with `swift build` or scripts/bundle.sh." }
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: (installedHelper as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installedHelper) { try fm.removeItem(atPath: installedHelper) }
            try fm.copyItem(atPath: helper, toPath: installedHelper)

            var settings: [String: Any] = [:]
            if let data = fm.contents(atPath: settingsPath) {
                guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    return "~/.claude/settings.json isn't valid JSON; nothing was changed."
                }
                settings = j
                let f = DateFormatter()
                f.dateFormat = "yyyyMMdd-HHmmss"
                try data.write(to: URL(fileURLWithPath: "\(settingsPath).switchboard-backup-\(f.string(from: Date()))"))
            }
            settings["statusLine"] = ["type": "command", "command": installedHelper, "padding": 0]
            let out = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
