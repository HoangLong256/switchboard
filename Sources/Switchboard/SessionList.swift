import AppKit
import SessionCore
import SwiftUI

/// First column: every session, favorites on top, workers indented under their PM,
/// sorted by what needs you first.
struct SessionList: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var teams = TeamStore.shared
    @State private var search = ""
    @State private var confirmClose: Row?

    var body: some View {
        let (fav, rest) = sections
        List(selection: $store.selected) {
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.secondary).font(.caption)
            }
            if !fav.isEmpty {
                Section("Favorites") { rows(fav) }
            }
            Section(fav.isEmpty ? "Sessions" : "Other") { rows(rest) }
        }
        .listStyle(.sidebar)
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
                Button { store.newSessionOpen = true } label: { Label("New Session", systemImage: "plus") }
                    .help("New Session (⌘N)")
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

struct SessionRowView: View {
    @ObservedObject private var resume = AutoContinue.shared
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

struct StatusDot: View {
    let status: Status

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: 7, height: 7)
            .help(status.why ?? status.label)
    }
}
