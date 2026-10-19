import SessionCore
import SwiftUI

/// The subagents of the live sessions, read in the background a few seconds apart (Store calls `update` on
/// every refresh). Sessions without recent subagent files cost one directory listing.
@MainActor
final class SubagentStore: ObservableObject {
    static let shared = SubagentStore()

    /// session id → its subagents (running first)
    @Published private(set) var bySession: [String: [Subagent]] = [:]
    /// the subagent whose activity is open, with its session
    @Published var viewing: (agent: Subagent, session: Session)?

    private var loading = false
    private var last = Date.distantPast
    private let queue = DispatchQueue(label: "switchboard.subagents", qos: .utility)
    static let interval: TimeInterval = 3

    func subagents(of s: Session) -> [Subagent] { bySession[s.id] ?? [] }
    func running(of s: Session) -> [Subagent] { subagents(of: s).filter(\.running) }

    func update(sessions: [Session], now: Date = Date()) {
        guard !loading, now.timeIntervalSince(last) >= Self.interval else { return }
        loading = true
        last = now
        let home = StateBuilder.defaultClaudeHome
        let names = Dictionary(sessions.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let targets = sessions.compactMap { s -> (String, String, String, Bool)? in
            guard let sid = s.sessionId, let cwd = s.cwd, !cwd.isEmpty, s.alive else { return nil }
            return (s.id, "\(home)/projects/\(Project.slug(cwd))", sid, s.alive)
        }
        queue.async { [weak self] in
            var found: [String: [Subagent]] = [:]
            for (id, dir, sid, alive) in targets {
                let list = Subagents.load(projectDir: dir, sessionId: sid, alive: alive)
                if !list.isEmpty { found[id] = list }
            }
            Task { @MainActor in
                guard let self else { return }
                self.loading = false
                guard found != self.bySession else { return }
                // a subagent that ran before and doesn't now has finished (not when its whole session ended)
                let live = Set(targets.map(\.0))
                for (id, before) in self.bySession where live.contains(id) {
                    let still = Set((found[id] ?? []).filter(\.running).map(\.id))
                    for a in before where a.running && !still.contains(a.id) {
                        Notifier.shared.subagentFinished(session: names[id] ?? id, subagent: a.description)
                    }
                }
                self.bySession = found
            }
        }
    }
}

/// Icon per subagent type, like Claude Code's built-in agents.
func subagentSymbol(_ type: String) -> String {
    switch type.lowercased() {
    case "explore": "magnifyingglass"
    case "plan": "list.bullet.clipboard"
    case "general-purpose": "sparkles"
    case "statusline-setup": "gauge.with.dots.needle.33percent"
    case let t where t.contains("review"): "checkmark.seal"
    case let t where t.contains("test"): "testtube.2"
    default: "person.crop.circle.badge.checkmark"
    }
}

/// A running subagent under its session in the session list; a click opens the session's Info tab.
struct SubagentRow: View {
    let agent: Subagent

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: subagentSymbol(agent.type))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Palette.busy)
                .frame(width: 12).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.description).font(.callout).lineLimit(1)
                Text(agent.action?.text ?? agent.type).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, 1)
        .help("\(agent.type)\(agent.model.map { " · \($0)" } ?? "")\(agent.background ? " · background" : "") — \(agent.description)")
    }
}

/// Info tab: the session's subagents, running ones with what they do now, then those that finished recently.
struct SubagentsSection: View {
    @ObservedObject private var store = SubagentStore.shared
    @EnvironmentObject private var sessions: Store
    let session: Session

    var body: some View {
        let list = store.subagents(of: session)
        if !list.isEmpty {
            let running = list.filter(\.running)
            Section {
                ForEach(list) { a in
                    SubagentDetail(agent: a, now: sessions.now)
                        .contentShape(Rectangle())
                        .onTapGesture { store.viewing = (a, session) }
                        .help("Show what this subagent does, step by step")
                }
            } header: {
                HStack {
                    Text("Subagents")
                    Spacer()
                    Text(running.isEmpty ? "none running" : "\(running.count) running").foregroundStyle(.secondary)
                }
            } footer: {
                Text("Agents this session started. Click one to see what it does. Finished ones stay listed for two hours.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SubagentDetail: View {
    let agent: Subagent
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill((agent.running ? Palette.busy : Color.secondary).opacity(0.15))
                Image(systemName: agent.running ? subagentSymbol(agent.type) : "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(agent.running ? Palette.busy : .secondary)
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.description).fontWeight(.medium).foregroundStyle(agent.running ? .primary : .secondary)
                Text(meta).font(.caption).foregroundStyle(.secondary)
                if agent.running, let a = agent.action {
                    Text(a.text).font(.callout).lineLimit(2)
                    if let d = a.detail { Text(d).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(.vertical, 2)
        .opacity(agent.running ? 1 : 0.75)
    }

    /// "Explore · haiku · background · worktree · 4 min" / "… · finished 12 min ago"
    private var meta: String {
        var parts = [agent.type]
        if let m = agent.model { parts.append(m) }
        if agent.background { parts.append("background") }
        if agent.worktreeBranch != nil { parts.append("own worktree") }
        if agent.running, let s = agent.startedAt {
            parts.append("for \(dur(s, now: now))")
        } else if let l = agent.lastActivity {
            parts.append("finished \(ago(l, now: now))")
        }
        return parts.joined(separator: " · ")
    }
}

/// Icon per tool in the activity view.
private func toolSymbol(_ tool: String?) -> String {
    switch tool {
    case "Bash": "terminal"
    case "Read": "doc.text"
    case "Edit", "MultiEdit", "Write", "NotebookEdit": "pencil"
    case "Grep", "Glob": "magnifyingglass"
    case "WebFetch", "WebSearch": "globe"
    case "Task", "Agent": "person.2"
    case "TodoWrite": "checklist"
    default: "wrench.and.screwdriver"
    }
}

/// What a subagent does, step by step: its task, its messages, each tool call with its command or file and
/// what came back. Reloads every two seconds while it runs and follows the newest step.
struct SubagentActivityView: View {
    @ObservedObject private var subagents = SubagentStore.shared
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let initial: Subagent
    let session: Session
    @State private var entries: [SubagentLog.Entry] = []
    @State private var follow = true
    @State private var promptOpen = false
    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    /// the newest state of this subagent (running or not, current step)
    private var agent: Subagent { subagents.subagents(of: session).first { $0.id == initial.id } ?? initial }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(entries) { EntryView(entry: $0, promptOpen: $promptOpen, running: agent.running) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(16)
                }
                .onChange(of: entries.count) { if follow { withAnimation { proxy.scrollTo("end", anchor: .bottom) } } }
                .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            }
            Divider()
            footer
        }
        .frame(minWidth: 640, idealWidth: 780, minHeight: 520, idealHeight: 720)
        .task(id: initial.id) { await load() }
        .onReceive(tick) { _ in if agent.running { Task { await load() } } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill((agent.running ? Palette.busy : Color.secondary).opacity(0.15))
                Image(systemName: agent.running ? subagentSymbol(agent.type) : "checkmark")
                    .foregroundStyle(agent.running ? Palette.busy : .secondary)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.description).font(.headline)
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text("\(entries.filter { $0.kind == .tool }.count) tool calls · in \(session.name)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("Follow", isOn: $follow).toggleStyle(.checkbox).controlSize(.small)
                .help("Scroll to the newest step as it comes in")
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: agent.path)]) } label: {
                Label("Show Transcript", systemImage: "doc.text.magnifyingglass")
            }
            .controlSize(.small)
            .help("Reveal the subagent's transcript (JSONL) in Finder")
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var meta: String {
        var parts = [agent.type]
        if let m = agent.model { parts.append(m) }
        if agent.background { parts.append("background") }
        if let b = agent.worktreeBranch { parts.append("worktree \(b)") }
        if agent.running, let s = agent.startedAt { parts.append("running for \(dur(s, now: store.now))") }
        else if let l = agent.lastActivity { parts.append("finished \(ago(l, now: store.now))") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        let path = agent.path
        let new = await Task.detached { SubagentLog.load(path) }.value
        if new != entries { entries = new }
    }
}

private struct EntryView: View {
    let entry: SubagentLog.Entry
    @Binding var promptOpen: Bool
    let running: Bool
    @State private var resultOpen = false

    var body: some View {
        switch entry.kind {
        case .prompt:
            VStack(alignment: .leading, spacing: 6) {
                Label("Task", systemImage: "text.bubble").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(entry.text).textSelection(.enabled).lineLimit(promptOpen ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                Button(promptOpen ? "Show Less" : "Show All") { promptOpen.toggle() }.buttonStyle(.link).font(.caption)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        case .text:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "sparkle").foregroundStyle(.secondary).frame(width: 18)
                Text(inlineMarkdown(entry.text)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        case .tool:
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: toolSymbol(entry.tool)).foregroundStyle(entry.failed ? Palette.need : Palette.idle).frame(width: 18)
                    Text(entry.text).fontWeight(.medium)
                    if entry.result == nil && running {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer()
                    if entry.result != nil {
                        Button(resultOpen ? "Hide Result" : (entry.failed ? "Show Error" : "Show Result")) { resultOpen.toggle() }
                            .buttonStyle(.link).font(.caption)
                            .foregroundStyle(entry.failed ? Palette.need : Color.accentColor)
                    }
                }
                if let d = entry.detail {
                    Text(d).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        .lineLimit(2).padding(.leading, 26)
                }
                if resultOpen, let r = entry.result {
                    Text(r.isEmpty ? "(no output)" : r)
                        .font(.caption.monospaced()).textSelection(.enabled)
                        .foregroundStyle(entry.failed ? Palette.need : .primary)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.leading, 26)
                }
            }
        }
    }
}

/// `code`, **bold** and links in a message; the line breaks stay as they are.
private func inlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}
