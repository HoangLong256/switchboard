import FolderKit
import Foundation
import SessionCore
import SwiftUI

/// A session with what the UI needs next to it: its status and its tmux session (if it runs in Switchboard's server).
struct Row: Identifiable, Equatable {
    let session: Session
    let status: Status
    let tmux: String?
    /// current folder of the tmux pane, if it runs in tmux
    var tmuxPath: String? = nil
    /// the row's identity in the list (see `SessionSelection.rowIDs`); set once all rows are built
    var id: String = ""
    var name: String { session.name }
}

/// Detail tabs of the selected session.
enum DetailTab: String, CaseIterable, Identifiable {
    case terminal = "Terminal", editor = "Editor", team = "Team", handover = "Handover", notes = "Notes", info = "Info"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .terminal: "terminal"
        case .editor: "doc.text"
        case .team: "person.3"
        case .handover: "arrow.triangle.swap"
        case .notes: "note.text"
        case .info: "info.circle"
        }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var rows: [Row] = []
    @Published private(set) var error: String?
    @Published private(set) var now = Date()
    /// `--select <name>` preselects a session at launch, for trying things out
    @Published var selected: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--select"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }() {
        didSet {
            // open files belong to their session; another session may have none
            guard selected != oldValue, oldValue != nil else { return }
            if tab == .editor, EditorStore.shared.tabs(of: selected).paths.isEmpty { tab = .terminal }
        }
    }
    /// `--tab <name>` starts on that tab (for trying things out)
    @Published var tab: DetailTab = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--tab"), i + 1 < args.count,
           let t = DetailTab.allCases.first(where: { $0.rawValue.lowercased() == args[i + 1].lowercased() }) { return t }
        return args.contains("--open") ? .editor : .terminal
    }()
    /// `--open <path>` opens a file in the selected session at launch (for trying things out)
    private var openAtLaunch: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--open"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()
    @Published private(set) var favorites: [String] = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
    @Published var newSessionOpen = false
    /// a session asked to move into Switchboard (confirmed in a dialog)
    @Published var moveRequest: Row?
    /// names of sessions being moved in right now
    @Published private(set) var moving: Set<String> = []
    @Published var notice: String?
    /// Increment to make the terminal grab keyboard focus
    @Published private(set) var focusRequest = 0
    /// Increment to re-attach the terminal (after the tmux session came back)
    @Published private(set) var terminalEpoch = 0

    private let transcripts = TranscriptCache()
    private var watcher: Watcher?
    private var timer: Timer?
    private var refreshing = false
    private var again = false
    private var pickedInitial = false
    /// start folders of offline sessions found in their transcripts (expensive, so once per name)
    private var foundFolders: [String: String?] = [:]

    init() {
        // a clicked notification shows its session (the terminal when it needs you)
        Notifier.shared.open = { [weak self] name, tab in
            self?.selected = name
            if tab == .terminal { self?.focusTerminal() } else { self?.tab = tab }
        }
        Task { await refresh() }
        let home = StateBuilder.defaultClaudeHome
        watcher = Watcher(paths: ["sessions", "handover", "projects"].map { "\(home)/\($0)" }, delay: 1) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        // catches ended processes and tmux changes, which FSEvents doesn't report
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    var selectedRow: Row? { rows.first { $0.name == selected } }

    func refresh() async {
        if refreshing { again = true; return }
        refreshing = true
        repeat {
            again = false
            let cache = transcripts
            // plan limits only matter for a session standing at a limit; ~/.claude.json is read off the main thread
            let (state, panes, planLimits) = await Task.detached { () -> (SessionsState, Tmux.Panes, PlanLimits?) in
                let state = StateBuilder.build(cache: cache)
                let limits = state.sessions.contains { $0.limitHit != nil } ? PlanLimits.load() : nil
                return (state, Tmux.panes(), limits)
            }.value
            let match = TmuxMatch.resolve(state.sessions, tmuxSessions: Set(panes.commands.keys),
                                          sessionOfPane: panes.sessionOfPane)
            var built = state.sessions.map { s -> Row in
                let t = match[s.id]
                return Row(session: s, status: Status(s, tmuxCommand: t.flatMap { panes.commands[$0] }), tmux: t,
                           tmuxPath: t.flatMap { panes.paths[$0] })
            }
            // tmux sessions without a Claude registry entry or handover (a shell, another agent)
            let known = Set(match.values)
            for (name, cmd) in panes.commands where !known.contains(name) {
                let s = Session(name: name, group: name, status: "shell")
                built.append(Row(session: s, status: Status(s, tmuxCommand: cmd), tmux: name, tmuxPath: panes.paths[name]))
            }
            built = SessionOrder.sorted(built, session: \.session, status: \.status.core, labels: [:])
            // a row keeps its identity while Claude exits to the shell and starts again in the same tmux session
            for (i, id) in SessionSelection.rowIDs(built.map { ($0.session.id, $0.tmux) }).enumerated() { built[i].id = id }
            if built != rows {
                // the selection follows its terminal (after /exit the shell row, after /rename the new name), and
                // moves to the nearest row when the tmux session is gone, instead of falling back to the empty screen
                let items = { (rows: [Row]) in rows.map { SessionSelection.Item(name: $0.name, tmux: $0.tmux) } }
                let next = SessionSelection.follow(selected, before: items(rows), after: items(built))
                rows = built
                if next != selected { selected = next }
            }
            SubagentStore.shared.update(sessions: rows.map(\.session))
            let err = state.sessions.isEmpty && !state.errors.isEmpty ? state.errors.joined(separator: "\n") : nil
            if err != error { error = err }
            if !pickedInitial, !rows.isEmpty {
                pickedInitial = true
                if selected == nil {
                    selected = SessionOrder.initial(rows.map { ($0.name, $0.status.rank, favorites.contains($0.name)) })
                }
                if let f = openAtLaunch { openFile(f, pinned: true); openAtLaunch = nil }
            }
            let t = Date()
            if t.timeIntervalSince(now) >= 10 { now = t }
            let settings = AppSettings.shared
            let limits = planLimits?.droppingExpired(now: t)
            AutoContinue.shared.update(rows: rows, limits: limits, settings: settings, now: t)
            Notifier.shared.update(rows: rows, selected: selected, now: t)
            KeepAwake.shared.update(working: rows.filter { $0.status.rank == 1 }.count,
                                    waitingForReset: AutoContinue.shared.pending.values.filter(\.willContinue).count,
                                    settings: settings)
        } while again
        refreshing = false
    }

    // MARK: Folder of a session

    /// The folder the sidebar shows: the session's cwd, else its tmux pane's folder, else (offline) the one
    /// found in its transcripts.
    func folder(of row: Row) -> String? {
        if let cwd = row.session.cwd, !cwd.isEmpty { return cwd }
        if let p = row.tmuxPath, !p.isEmpty { return p }
        if let known = foundFolders[row.name] { return known }
        return nil
    }

    /// Looks up the start folder of an offline session in the background (reads transcript heads and tails).
    func findFolder(of row: Row) async -> String? {
        if let f = folder(of: row) { return f }
        let name = row.name
        let found = await Task.detached { SessionFolder.find(name) }.value
        foundFolders[name] = found
        objectWillChange.send()
        return found
    }

    // MARK: Actions

    /// VS Code's Explorer: a single click previews (focus stays in the tree), a double click or Enter keeps the
    /// file open and moves focus into the editor.
    func openFile(_ path: String, pinned: Bool) {
        guard let s = selected else { return }
        EditorStore.shared.open(path, in: s, pinned: pinned, focus: pinned)
        tab = .editor
    }

    /// Source Control: a file's changes in a diff tab.
    func openDiff(_ entry: GitChanges.Entry, repo: String, staged: Bool, pinned: Bool) {
        guard let s = selected else { return }
        EditorStore.shared.openDiff(entry, repo: repo, staged: staged, in: s, pinned: pinned)
        tab = .editor
    }

    func isFavorite(_ name: String) -> Bool { favorites.contains(name) }

    func toggleFavorite(_ name: String) {
        favorites = Favorites.toggling(name, in: favorites)
        UserDefaults.standard.set(favorites, forKey: "favorites")
    }

    func focusTerminal() {
        tab = .terminal
        focusRequest += 1
    }

    /// Next session that needs you (longest waiting first).
    func jumpToWaiting() {
        let waiting = rows.filter { $0.status.rank == 0 }.map(\.name)
        guard let first = waiting.first else { return }
        if let sel = selected, let i = waiting.firstIndex(of: sel) {
            selected = waiting[(i + 1) % waiting.count]
        } else {
            selected = first
        }
        focusTerminal()
    }

    func startSession(name: String, folder: String, agentTeam: Bool = false, start: Bool = true,
                      command: String? = nil) async {
        let env = AppSettings.shared.newSessionEnvironment
        let err = await Task.detached {
            Tmux.newSession(name: name, dir: folder, agentTeam: agentTeam, environment: env, start: start, command: command)
        }.value
        if let err { notice = err; return }
        await refresh()
        selected = name
        terminalEpoch += 1
        focusTerminal()
    }

    // MARK: Moving a session in

    /// A session Switchboard can bring into its tmux: one running elsewhere (another terminal app), or an offline one.
    func canMoveIn(_ row: Row) -> Bool {
        row.tmux == nil && row.session.status != "shell" && row.session.kind != "bg"
    }

    /// A running session asks first (it ends where it runs); an offline one resumes right away.
    func requestMoveIn(_ row: Row) {
        guard canMoveIn(row) else { return }
        if row.session.alive { moveRequest = row } else { Task { await moveIn(row) } }
    }

    /// Ends the session where it runs (as closing its terminal window would) and continues the same conversation
    /// in a new tmux session here with `claude --resume`. An offline session just resumes.
    func moveIn(_ row: Row) async {
        let name = row.name
        guard canMoveIn(row), !moving.contains(name) else { return }
        moving.insert(name)
        defer { moving.remove(name) }

        var sessionId = row.session.sessionId
        var folder = row.session.cwd.flatMap { $0.isEmpty ? nil : $0 }
        if sessionId == nil || folder == nil {
            // offline with only a handover: find its newest transcript
            guard let t = await Task.detached(operation: { SessionFolder.transcript(name) }).value else {
                notice = "Couldn't find the conversation of “\(name)” in ~/.claude/projects, so it can't be resumed."
                return
            }
            sessionId = sessionId ?? t.sessionId
            folder = folder ?? t.cwd
        }
        guard let sessionId, let folder else { return }

        if row.session.alive, let pid = row.session.pid {
            let ended = await Task.detached { await Self.end(pid) }.value
            guard ended else {
                notice = "“\(name)” is still running (pid \(pid)). Quit it in its window with /exit, then try again."
                return
            }
        }
        let tmuxNames = Set(rows.compactMap(\.tmux))
        let display = MoveIn.displayName(name, folder: folder, taken: Set(rows.map(\.name)))
        let tmux = MoveIn.tmuxName(display, taken: tmuxNames)
        await startSession(name: tmux, folder: folder, command: MoveIn.resumeCommand(name: display, sessionId: sessionId))
        // once Claude registers, the row goes by the session's name rather than the tmux session's
        _ = await SessionControl.waitUntil(timeout: 15, interval: 0.5) { [weak self] in
            guard let self else { return true }
            await self.refresh()
            guard let r = self.rows.first(where: { $0.tmux == tmux && $0.session.alive }) else { return false }
            if self.selected == tmux { self.selected = r.name }
            return true
        }
    }

    /// SIGHUP (the terminal went away), then SIGTERM; true once the process is gone.
    nonisolated private static func end(_ pid: Int) async -> Bool {
        let p = pid_t(truncatingIfNeeded: pid)
        for signal in [SIGHUP, SIGTERM] {
            kill(p, signal)
            let gone = await SessionControl.waitUntil(timeout: 5, interval: 0.2) { !Registry.isAlive(pid) }
            if gone { return true }
        }
        return false
    }

    /// Types `text` into the selected session's terminal, without Enter.
    func insertIntoTerminal(_ text: String) {
        guard let t = selectedRow?.tmux else { notice = "This session has no terminal in Switchboard's tmux server."; return }
        Task.detached {
            if let err = Tmux.insert(text, into: t) { await MainActor.run { self.notice = err } }
        }
        focusTerminal()
    }

    func close(_ row: Row) {
        guard let t = row.tmux else { return }
        Task {
            if let err = await Task.detached(operation: { Tmux.kill(t) }).value { notice = err }
            await refresh()
        }
    }
}
