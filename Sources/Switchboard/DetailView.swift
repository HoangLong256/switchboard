import AppKit
import FolderKit
import SessionCore
import StatusLineKit
import MarkdownUI
import SwiftUI

/// Third column: header with name, status and task line, then the tabs of the selected session.
struct DetailView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var editors = EditorStore.shared
    @ObservedObject private var teams = TeamStore.shared
    @AppStorage("showModelInTabs") private var showModel = true

    var body: some View {
        if let row = store.selectedRow {
            VStack(spacing: 0) {
                DetailHeader(row: row)
                HStack {
                    Picker("", selection: $store.tab) {
                        ForEach(tabs(row)) { t in Text(title(t, row)).tag(t) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer()
                    if showModel { ModelChip(row: row) }
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
                Divider()
                content(row)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
            .themeBackground()
        } else {
            WelcomeView()
        }
    }

    /// "Editor (2)" with unsaved files, "Team (3)" with teammates
    private func title(_ t: DetailTab, _ row: Row) -> String {
        switch t {
        case .editor: let n = editors.dirtyCount(in: row.name); return n > 0 ? "Editor (\(n))" : "Editor"
        case .team: return teams.team(ledBy: row.session).map { "Team (\($0.teammates.count))" } ?? "Team"
        default: return t.rawValue
        }
    }

    /// "Editor •2" while two open files have unsaved changes (VS Code's dirty count)
    private func label(_ t: DetailTab, _ row: Row) -> String {
        let dirty = t == .editor ? editors.dirtyCount(in: row.name) : 0
        return dirty > 0 ? "\(t.rawValue) •\(dirty)" : t.rawValue
    }

    private func tabs(_ row: Row) -> [DetailTab] {
        DetailTab.allCases.filter { t in
            switch t {
            case .editor: !editors.tabs(of: row.name).paths.isEmpty
            case .team: teams.team(ledBy: row.session) != nil || store.tab == .team
            default: true
            }
        }
    }

    @ViewBuilder
    private func content(_ row: Row) -> some View {
        switch store.tab {
        case .terminal: TerminalTab(row: row)
        case .editor: EditorArea(session: row.name)
        case .team: TeamTab(row: row)
        case .handover: HandoverTab(name: row.name).id(row.name)
        case .notes: NotesTab(name: row.name).id(row.name)
        case .info: InfoTab(row: row)
        }
    }
}

/// "Opus 5.5 · high" next to the tabs: the model and effort the session runs with, details on click.
struct ModelChip: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: Store
    let row: Row
    @State private var open = false

    var body: some View {
        let line = usage.line(row.session)
        let model = line?.model ?? row.session.model.map(ModelName.short)
        let effort = line?.effort
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "cpu").foregroundStyle(.secondary)
                Text(model ?? "Model unknown").foregroundStyle(model == nil ? .secondary : .primary)
                if let effort {
                    Text("·").foregroundStyle(.tertiary)
                    Text(effort.capitalized).foregroundStyle(effortColor(effort))
                }
            }
            .font(.callout)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .opacity(row.session.alive ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .help(effort.map { "Model and effort: \(model ?? "unknown") · \($0)" } ?? "Model: \(model ?? "unknown")")
        .popover(isPresented: $open, arrowEdge: .bottom) { details(line: line, model: model, effort: effort) }
    }

    private func details(line: SessionLine?, model: String?, effort: String?) -> some View {
        Form {
            LabeledContent("Model", value: model ?? "–")
            if let id = row.session.model, id != model { LabeledContent("Model ID", value: id) }
            LabeledContent("Effort", value: effort?.capitalized ?? "–")
            if let t = line?.contextTokens, let w = line?.contextWindow {
                LabeledContent("Context", value: "\(UsageFormat.tokens(t)) of \(UsageFormat.tokens(w))")
            }
            if let c = line?.costUSD { LabeledContent("Cost", value: UsageFormat.usd(c)) }
            if let line {
                Text("From the status line, \(ago(line.writtenAt, now: store.now)).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(model == nil
                     ? "No response from this session yet. Model and effort come from Claude Code's status line: set it up from the usage bars at the bottom of the sessions column."
                     : "Model of the last response in the transcript. Effort comes from Claude Code's status line: set it up from the usage bars at the bottom of the sessions column.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Change them in the terminal with /model and /effort.").font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// low → max from calm to strong
    private func effortColor(_ e: String) -> Color {
        switch e.lowercased() {
        case "low": .secondary
        case "medium": .primary
        case "high": Palette.shell
        case "xhigh": Palette.wait
        case "max": Palette.need
        default: .primary
        }
    }
}

struct DetailHeader: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var usage: UsageStore
    let row: Row

    var body: some View {
        let s = row.session
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.name).font(.title2.weight(.semibold))
                StatusDot(status: row.status).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                Text(row.status.rank == 0 ? (row.status.why ?? row.status.label) : row.status.label)
                    .foregroundStyle(row.status.rank == 0 ? row.status.color : .secondary)
                    .lineLimit(1)
                Spacer()
                Button { store.toggleFavorite(row.name) } label: {
                    Image(systemName: store.isFavorite(row.name) ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(store.isFavorite(row.name) ? Color.accentColor : .secondary)
                .help("Favorite (⌘D)")
            }
            Text(details(s)).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }

    /// "~/Projects/app · main · 52 % context · 64.1M tokens · Fix the build"
    private func details(_ s: Session) -> String {
        var parts: [String] = []
        if let f = store.folder(of: row) { parts.append(abbreviated(f)) }
        if let b = s.branch, b != "HEAD" { parts.append(b) }
        if let c = s.contextPercent { parts.append("\(Int(c.rounded())) % context") }
        if let t = usage.tokens(s), t.total > 0 { parts.append("\(UsageFormat.tokens(t.total)) tokens") }
        if let task = s.task?.text, !task.isEmpty { parts.append(task) }
        return parts.joined(separator: "  ·  ")
    }
}

/// Shown when no session is selected.
struct WelcomeView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        VStack(spacing: 14) {
            AppMark(size: 64)
            Text("Switchboard").font(.title.weight(.semibold))
            Text("All your Claude Code sessions, their files and their usage in one place.")
                .foregroundStyle(.secondary)
            Button("New Session…") { store.newSessionOpen = true }
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TerminalTab: View {
    @EnvironmentObject private var store: Store
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @Environment(\.colorScheme) private var scheme
    let row: Row

    var body: some View {
        if Tmux.path == nil {
            ContentUnavailableView("tmux missing", systemImage: "exclamationmark.triangle", description: Text("brew install tmux"))
        } else if let t = row.tmux {
            TmuxTerminal(name: t, focusRequest: store.focusRequest)
                .id("\(t)#\(store.terminalEpoch)")
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(hex: theme.palette(dark: scheme == .dark).background))
        } else if row.session.alive {
            let app = row.session.pid.flatMap(MoveIn.hostApp(of:))
            ContentUnavailableView {
                Label(app.map { "Runs in \($0)" } ?? "Runs outside Switchboard", systemImage: "macwindow")
            } description: {
                Text("Its terminal belongs to \(app ?? "another app"), so it can't be shown here. Move it in to continue the same conversation in Switchboard's terminal; it ends there.")
            } actions: {
                moveButton("Move into Switchboard…", "arrow.down.right.and.arrow.up.left")
            }
        } else if row.session.hasHandover {
            VStack(spacing: 0) {
                HStack {
                    Label("Offline", systemImage: "moon.zzz").foregroundStyle(.secondary)
                    Spacer()
                    moveButton("Resume in Switchboard", "play.fill")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                Divider()
                HandoverTab(name: row.name)
            }
        } else {
            ContentUnavailableView {
                Label("Offline", systemImage: "moon.zzz")
            } description: {
                Text("No terminal and no handover.")
            } actions: {
                moveButton("Resume in Switchboard", "play.fill")
            }
        }
    }

    @ViewBuilder
    private func moveButton(_ title: String, _ symbol: String) -> some View {
        if store.canMoveIn(row) {
            let busy = store.moving.contains(row.name)
            Button { store.requestMoveIn(row) } label: {
                Label(busy ? "Moving…" : title, systemImage: symbol)
            }
            .disabled(busy)
            .help("Continues the conversation here with claude --resume")
        }
    }
}

struct HandoverTab: View {
    let name: String
    @State private var text: String?
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView {
                    Markdown(text).markdownTheme(.gitHub).textSelection(.enabled)
                        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView {
                    Label("No handover yet", systemImage: "arrow.triangle.swap")
                } description: {
                    Text(HandoverInstall.isInstalled
                         ? "Claude writes one here when it starts a task, needs a decision, or finishes. It lives in ~/.claude/handover/\(name).md."
                         : "A handover is a short status note: the current task, whether it is blocked, and what is left. Set it up and Claude keeps one for each session.")
                } actions: {
                    HandoverSetupButton()
                }
            }
        }
        .onAppear(perform: load)
        .onReceive(tick) { _ in load() }
    }

    private func load() {
        let t = Handover.body(name, dir: "\(StateBuilder.defaultClaudeHome)/handover")
        if t != text { text = t }
    }
}

/// "Set Up Handover…" with what it changes, or "Turn Off Handover" once it is set up.
struct HandoverSetupButton: View {
    @State private var installed = HandoverInstall.isInstalled
    @State private var confirm = false
    @State private var error: String?

    var body: some View {
        Group {
            if installed {
                Button("Turn Off Handover", role: .destructive) { confirm = true }
                    .help("Remove the Switchboard section from ~/.claude/CLAUDE.md and the permission rule")
            } else {
                Button { confirm = true } label: { Label("Set Up Handover…", systemImage: "arrow.triangle.swap") }
                    .help("Let Claude keep a handover for each session")
            }
        }
        .onAppear { installed = HandoverInstall.isInstalled }
        .alert("Handover", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
        .confirmationDialog(installed ? "Turn off the handover?" : "Set up the handover?", isPresented: $confirm) {
            Button(installed ? "Turn Off" : "Set Up") { run() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installed
                 ? "Switchboard removes its section from ~/.claude/CLAUDE.md and its permission rule from ~/.claude/settings.json. Existing handovers stay."
                 : "Switchboard copies switchboard-task to ~/.switchboard/bin. Then it adds a short section to ~/.claude/CLAUDE.md that tells Claude to keep its handover, and a rule to ~/.claude/settings.json so the command runs without asking. Both files are backed up first. New sessions use it; running sessions after /clear or a restart.")
        }
    }

    private func run() {
        error = installed ? HandoverInstall.uninstall() : HandoverInstall.install()
        installed = HandoverInstall.isInstalled
    }
}

/// Notepad per session, stored in `~/.switchboard/notes/<name>.md`.
struct NotesTab: View {
    let name: String
    @State private var text = ""
    @State private var saved = ""
    @State private var preview = false
    @FocusState private var editing: Bool
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var root: String { Notes.root() }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notes for \(name)").font(.headline)
                Spacer()
                Picker("", selection: $preview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 150)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            Divider()
            if preview {
                ScrollView {
                    Markdown(text).markdownTheme(.gitHub).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .focused($editing)
            }
        }
        .onAppear {
            text = Notes.read(root: root, session: name)
            saved = text
        }
        .onChange(of: text) { _, new in
            guard new != saved else { return }
            Notes.write(root: root, session: name, text: new)
            saved = new
        }
        // `cc-note` may append while the tab is open; take it over unless you're typing
        .onReceive(tick) { _ in
            guard !editing else { return }
            let disk = Notes.read(root: root, session: name)
            if disk != saved { text = disk; saved = disk }
        }
        .onDisappear { Notes.write(root: root, session: name, text: text) }
    }
}

/// Info tab: the session stopped at a usage limit. When it resets and whether it will be continued.
struct LimitSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var resume = AutoContinue.shared
    @EnvironmentObject private var store: Store
    let row: Row
    let hit: LimitHit

    var body: some View {
        let p = resume.pending[row.name]
        Section("Usage limit") {
            Text(hit.text)
            if let r = p?.resetAt {
                LabeledContent("Resets", value: r.formatted(date: .abbreviated, time: .shortened))
            }
            Toggle("Continue this session when the limit resets", isOn: Binding(
                get: { settings.continues(row.name) },
                set: { on in
                    if on && !settings.autoContinue { settings.autoContinue = true }
                    settings.setContinues(row.name, on)
                }))
            if let why = p?.reasonNot, settings.continues(row.name) { Text("Won't continue: \(why).").foregroundStyle(.secondary) }
            Button("Continue Now") { resume.continueNow(row, message: settings.continueMessage) }
                .disabled(row.tmux == nil)
                .help("Types “\(settings.continueMessage)” into the session now")
        }
    }
}
