import AppKit
import FolderKit
import SessionCore
import MarkdownUI
import SwiftUI

/// Third column: header with name, status and task line, then the tabs of the selected session.
struct DetailView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var editors = EditorStore.shared
    @ObservedObject private var teams = TeamStore.shared

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
                }
                .padding(.horizontal, 16).padding(.bottom, 10)
                Divider()
                content(row)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
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
    let row: Row

    var body: some View {
        if Tmux.path == nil {
            ContentUnavailableView("tmux missing", systemImage: "exclamationmark.triangle", description: Text("brew install tmux"))
        } else if let t = row.tmux {
            TmuxTerminal(name: t, focusRequest: store.focusRequest)
                .id("\(t)#\(store.terminalEpoch)")
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor))
        } else if row.session.alive {
            ContentUnavailableView("Runs outside Switchboard", systemImage: "macwindow",
                                   description: Text("This session has no tmux session on `-L \(Tmux.socket)`, so its terminal can't be shown here. Its files, handover and notes still work."))
        } else if row.session.hasHandover {
            HandoverTab(name: row.name)
        } else {
            ContentUnavailableView("Offline", systemImage: "moon.zzz", description: Text("No terminal and no handover."))
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
                ContentUnavailableView("No handover", systemImage: "arrow.triangle.swap",
                                       description: Text("A session writes one with `/handover`; it lives in ~/.claude/handover/\(name).md."))
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

struct InfoTab: View {
    @EnvironmentObject private var store: Store
    let row: Row

    var body: some View {
        let s = row.session
        Form {
            Section("Session") {
                LabeledContent("Name", value: s.name)
                LabeledContent("Status", value: row.status.label)
                if let w = s.waitingFor { LabeledContent("Waiting for", value: w) }
                LabeledContent("Project", value: s.project.isEmpty ? "–" : s.project)
                if let b = s.branch { LabeledContent("Branch", value: b) }
                if let cwd = store.folder(of: row) {
                    LabeledContent("Folder") {
                        HStack {
                            Text(abbreviated(cwd)).textSelection(.enabled)
                            Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) }
                        }
                    }
                }
                if let pid = s.pid { LabeledContent("PID", value: String(pid)) }
                if let t = row.tmux { LabeledContent("tmux", value: "-L \(Tmux.socket) =\(t):") }
                if let p = s.contextPercent { LabeledContent("Context used", value: "\(Int(p.rounded())) %") }
                if s.backgroundTasks > 0 { LabeledContent("Background tasks", value: String(s.backgroundTasks)) }
                if s.remoteControl { LabeledContent("Remote Control", value: "connected") }
            }
            if let hit = s.limitHit { LimitSection(row: row, hit: hit) }
            SessionUsageSection(session: s)
            if let now = NowLine(s, rank: row.status.rank) {
                Section("Now") {
                    Text(now.text).textSelection(.enabled)
                    if let d = now.detail { Text(d).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    if !now.options.isEmpty {
                        ForEach(now.options, id: \.self) { Text("• \($0)").foregroundStyle(.secondary) }
                    }
                }
            }
            if let u = s.lastUser {
                Section("Last message from you · \(ago(u.at, now: store.now))") { Text(u.text).textSelection(.enabled) }
            }
            if let a = s.lastAssistant {
                Section("Last reply · \(ago(a.at, now: store.now))") { Text(a.text).textSelection(.enabled) }
            }
            if !s.errors.isEmpty {
                Section("Problems") { ForEach(s.errors, id: \.self) { Text($0).foregroundStyle(Palette.need) } }
            }
        }
        .formStyle(.grouped)
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
