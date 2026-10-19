import AppKit
import SessionCore
import SwiftUI

/// First column: every session, favorites on top, workers indented under their PM,
/// sorted by what needs you first.
struct SessionList: View {
    @Environment(Store.self) private var store
    private var teams: TeamStore { .shared }
    private var subagents: SubagentStore { .shared }
    @AppStorage("showSubagents") private var showSubagents = true
    @State private var search = ""
    @State private var confirmClose: Row?
    @AppStorage("sessionsGrouping") private var grouping: SessionGrouping = .none
    /// "<grouping>/<group>" of the sections folded away, one per line
    @AppStorage("collapsedGroups") private var collapsedGroups = ""

    var body: some View {
        @Bindable var store = store
        let (fav, rest) = sections
        List(selection: $store.selected) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).font(.caption)
            }
            if !fav.isEmpty {
                Section("Favorites") { rows(fav) }
            }
            if grouping == .none {
                Section(fav.isEmpty ? "Sessions" : "Other") { rows(rest) }
            } else {
                ForEach(SessionGroups.split(rest, key: groupKey), id: \.key) { g in
                    Section(isExpanded: expanded(g.key)) {
                        rows(g.items)
                    } header: {
                        GroupHeader(title: grouping == .folder ? (g.key as NSString).lastPathComponent : g.key,
                                    path: grouping == .folder ? g.key : nil, items: g.items)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .themeBackground(sidebar: true)
        .safeAreaInset(edge: .bottom, spacing: 0) { UsageFooter() }
        .searchable(text: $search, placement: .sidebar, prompt: "Search sessions")
        .overlay {
            if store.rows.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "terminal",
                                       description: Text("Start one with ⌘N, or run `claude -n name` anywhere."))
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Group By", selection: $grouping) {
                        ForEach(SessionGrouping.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Group By", systemImage: "rectangle.3.group")
                }
            }
            ToolbarItem {
                Button { store.newSessionOpen = true } label: { Label("New Session", systemImage: "plus") }
            }
        }
        .confirmationDialog("Close \(confirmClose?.name ?? "")?", isPresented: Binding(
            get: { confirmClose != nil }, set: { if !$0 { confirmClose = nil } })) {
            Button("Close Session", role: .destructive) { if let r = confirmClose { store.close(r) } }
        } message: {
            Text(closeMessage(confirmClose))
        }
    }

    private var filtered: [Row] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return store.rows }
        return store.rows.filter { r in
            [r.name, r.session.project, r.session.task?.text ?? "", r.session.cwd ?? ""]
                .contains { $0.lowercased().contains(q) }
        }
    }

    private var sections: (favorites: [Row], rest: [Row]) {
        let split = Favorites.split(filtered, favorites: store.favorites, name: \.name)
        return Favorites.withWorkers(favorites: split.favorites, rest: split.rest, session: \.session,
                                     active: { $0.status.rank < 3 })
    }

    /// The section a session belongs to: the folder its working folder sits in ("~/Workplace/Personal Projects"),
    /// or its status.
    private func groupKey(_ r: Row) -> String {
        switch grouping {
        case .status: return r.status.label.prefix(1).uppercased() + r.status.label.dropFirst()
        case .folder, .none:
            guard let f = store.folder(of: r) else { return "No folder" }
            return abbreviated((f as NSString).deletingLastPathComponent)
        }
    }

    private func expanded(_ group: String) -> Binding<Bool> {
        let id = "\(grouping.rawValue)/\(group)"
        return Binding(
            get: { !collapsedGroups.split(separator: "\n").contains { $0 == id } },
            set: { open in
                var ids = collapsedGroups.split(separator: "\n").map(String.init).filter { $0 != id }
                if !open { ids.append(id) }
                collapsedGroups = ids.joined(separator: "\n")
            })
    }

    @ViewBuilder
    private func rows(_ items: [Row]) -> some View {
        ForEach(SessionTree.grouped(items, session: \.session), id: \.item.id) { r in
            SessionRowView(row: r.item, depth: r.depth, favorite: store.isFavorite(r.item.name), now: store.now)
                .tag(r.item.name)
                .contextMenu { menu(r.item) }
            // teammates of an agent team under their lead; a click opens the lead's Team tab
            if let team = teams.team(ledBy: r.item.session) {
                ForEach(team.teammates) { m in
                    TeammateRow(team: team, member: m)
                        .selectionDisabled()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selected = r.item.name
                            store.tab = .team
                        }
                }
            }
            // running subagents under their session; a click shows what the subagent does
            if showSubagents {
                ForEach(subagents.running(of: r.item.session)) { a in
                    SubagentRow(agent: a)
                        .selectionDisabled()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.selected = r.item.name
                            subagents.viewing = (a, r.item.session)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func menu(_ r: Row) -> some View {
        Button(store.isFavorite(r.name) ? "Remove from Favorites" : "Add to Favorites") { store.toggleFavorite(r.name) }
        if let cwd = store.folder(of: r) {
            Button("Reveal Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) }
        }
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(r.name, forType: .string)
        }
        Toggle("Continue After Usage Limits", isOn: Binding(
            get: { AppSettings.shared.continues(r.name) },
            set: { on in
                if on && !AppSettings.shared.autoContinue { AppSettings.shared.autoContinue = true }
                AppSettings.shared.setContinues(r.name, on)
            }))
        if store.canMoveIn(r) {
            Divider()
            Button(r.session.alive ? "Move into Switchboard…" : "Resume in Switchboard") { store.requestMoveIn(r) }
                .disabled(store.moving.contains(r.name))
        }
        if let t = r.tmux {
            Button("Copy Attach Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("tmux -L \(Tmux.socket) attach -t '=\(t):'", forType: .string)
            }
            Divider()
            Button("Close…", role: .destructive) { confirmClose = r }
        }
    }

    private func closeMessage(_ r: Row?) -> String {
        guard let r else { return "" }
        let w = SessionControl.closeWarnings(r.session)
        return (["Ends the tmux session and everything running in it."] + w.map { "\($0)." }).joined(separator: " ")
    }
}

/// How the sessions column is sectioned below the favorites.
enum SessionGrouping: String, CaseIterable, Identifiable {
    case none, folder, status
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .folder: "Parent Folder"
        case .status: "Status"
        }
    }
}

/// "Personal Projects  ● 1  3": a group's name, how many of its sessions need you, and its size.
private struct GroupHeader: View {
    let title: String
    /// the full folder, when grouped by parent folder
    let path: String?
    let items: [Row]

    var body: some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            let need = items.filter { $0.status.rank == 0 }.count
            if need > 0 {
                Label("\(need)", systemImage: "circle.fill").foregroundStyle(Palette.need).labelStyle(DotCount())
            }
            Text("\(items.count)").foregroundStyle(.tertiary).monospacedDigit()
        }
        .help((path.map { "\($0)\n" } ?? "") + summary(items))
    }

    private func summary(_ items: [Row]) -> String {
        let n = items.filter { $0.status.rank == 0 }.count
        return "\(items.count) session\(items.count == 1 ? "" : "s")" + (n > 0 ? ", \(n) need\(n == 1 ? "s" : "") you" : "")
    }
}

/// A small dot before the number.
private struct DotCount: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.font(.system(size: 6)); configuration.title.monospacedDigit() }
    }
}

struct SessionRowView: View {
    private var resume: AutoContinue { .shared }
    let row: Row
    let depth: Int
    let favorite: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StatusDot(status: row.status)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(row.name).lineLimit(1)
                    if favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.secondary) }
                    Spacer(minLength: 4)
                    Text(dur(row.session.statusUpdatedAt ?? row.session.task?.updatedAt, now: now))
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
                subtitle.font(.caption).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, CGFloat(depth) * 14)
    }

    /// One line: what needs you (in the status color), else the task, else the status.
    @ViewBuilder private var subtitle: some View {
        if let p = resume.pending[row.name] {
            Text(limitLabel(p)).foregroundStyle(Palette.block)
        } else if row.status.rank == 0 {
            Text(row.status.why ?? row.status.label).foregroundStyle(row.status.color)
        } else if let task = row.session.task?.text, !task.isEmpty {
            Text(task).foregroundStyle(.secondary)
        } else {
            Text(row.status.label + (row.session.backgroundTasks > 0 ? " · \(row.session.backgroundTasks) in background" : ""))
                .foregroundStyle(.secondary)
        }
    }

    /// "limit · continues 3:10pm" or "limit · resets 3:10pm"
    private func limitLabel(_ p: AutoContinue.Pending) -> String {
        let time = p.resetAt.map { $0.formatted(date: .omitted, time: .shortened) }
        guard let time else { return "usage limit" }
        return p.willContinue ? "limit · continues \(time)" : "limit · resets \(time)"
    }
}

/// Filled in the status color; a ring when offline; breathing while the session works.
struct StatusDot: View {
    /// the colors follow the theme
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    let status: Status

    var body: some View {
        Group {
            if status.core.cls == "off" {
                Circle().strokeBorder(status.color, lineWidth: 1.2)
            } else {
                PulsingDot(color: NSColor(status.color), pulsing: status.active)
            }
        }
        .frame(width: 7, height: 7)
        .help(status.why ?? status.label)
    }
}

/// A dot that pulses while its session works. The pulse is a Core Animation animation, so it runs in the render
/// server: a SwiftUI animation would update the whole window on every frame, for every working session, forever.
/// It pauses while Switchboard is in the background.
private struct PulsingDot: NSViewRepresentable {
    let color: NSColor
    let pulsing: Bool

    func makeNSView(context: Context) -> DotView { DotView() }

    func updateNSView(_ v: DotView, context: Context) {
        v.color = color
        v.pulsing = pulsing
    }

    final class DotView: NSView {
        var color: NSColor = .systemGreen { didSet { if color != oldValue { updateLayer() } } }
        var pulsing = false { didSet { if pulsing != oldValue { updatePulse() } } }
        private var observers: [NSObjectProtocol] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            let center = NotificationCenter.default
            for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updatePulse() }
                })
            }
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.backgroundColor = color.cgColor
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        override func layout() {
            super.layout()
            layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updatePulse()
        }

        private func updatePulse() {
            guard let layer else { return }
            let on = pulsing && window != nil && NSApp.isActive
            if on, layer.animation(forKey: "pulse") == nil {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1
                a.toValue = 0.35
                a.duration = 0.9
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(a, forKey: "pulse")
            } else if !on {
                layer.removeAnimation(forKey: "pulse")
            }
        }
    }
}
