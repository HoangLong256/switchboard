import SessionCore
import SwiftUI
import TeamKit

/// Agent teams on disk (`~/.claude/teams`, `~/.claude/tasks`), reloaded every 2 s: the folders often don't exist
/// until the first team starts, so a file watcher would have nothing to watch.
@MainActor
final class TeamStore: ObservableObject {
    static let shared = TeamStore()
    @Published private(set) var teams: [Team] = []
    private var timer: Timer?
    private var loading = false

    nonisolated static let teamsDir = "\(StateBuilder.defaultClaudeHome)/teams"
    nonisolated static let tasksDir = "\(StateBuilder.defaultClaudeHome)/tasks"

    private init() {
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        guard !loading else { return }
        loading = true
        Task {
            let t = await Task.detached { TeamReader.load(teamsDir: Self.teamsDir, tasksDir: Self.tasksDir) }.value
            loading = false
            if t != teams { teams = t }
        }
    }

    /// The team a session leads (by its Claude session id).
    func team(ledBy s: Session) -> Team? {
        guard let id = s.sessionId else { return nil }
        return teams.first { $0.leadSessionId == id }
    }
}

extension Team.Member {
    /// Claude Code's color names for teammates
    var swatch: Color {
        switch color?.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "cyan": .cyan
        default: .gray
        }
    }
}

extension Team.MemberState {
    var label: String {
        switch self {
        case .working: "working"
        case .idle: "idle"
        case .stopped: "stopped"
        }
    }

    var color: Color {
        switch self {
        case .working: Palette.busy
        case .idle: Palette.idle
        case .stopped: Palette.off
        }
    }
}

/// A teammate under its lead in the sessions list. Clicking it opens the lead's Team tab.
struct TeammateRow: View {
    let team: Team
    let member: Team.Member

    var body: some View {
        let state = team.state(of: member)
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(member.swatch).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(member.name).font(.callout).lineLimit(1)
                    Text(state.label).font(.caption).foregroundStyle(.secondary)
                }
                if let t = team.currentTask(of: member) {
                    Text(t.activeForm ?? t.subject).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.leading, 18)
        .padding(.vertical, 1)
        .help("Teammate of \(team.name)" + (member.agentType.map { " · \($0)" } ?? ""))
    }
}

/// Team tab of a lead session: who is on the team and what they do, the shared task list, and the messages.
struct TeamTab: View {
    @ObservedObject private var teams = TeamStore.shared
    @EnvironmentObject private var store: Store
    let row: Row

    var body: some View {
        if let team = teams.team(ledBy: row.session) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(team)
                    roster(team)
                    board(team)
                    messages(team)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView {
                Label("No agent team", systemImage: "person.3")
            } description: {
                Text("Claude Code's agent teams are experimental. Start a session with “Agent team” turned on in New Session (⌘N), then ask Claude to split the work across teammates. Its team, tasks and messages show up here.")
            }
        }
    }

    private func header(_ team: Team) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(team.name).font(.title3.weight(.semibold))
            Text("\(team.teammates.count) teammates · \(team.tasks(.completed).count)/\(team.tasks.count) tasks done")
                .foregroundStyle(.secondary)
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: "\(TeamStore.teamsDir)/\(team.name)")]) } label: {
                Label("Team Folder", systemImage: "folder")
            }
            .buttonStyle(.borderless)
        }
    }

    private func roster(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Members").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(team.members) { m in memberCard(team, m) }
            }
        }
    }

    private func memberCard(_ team: Team, _ m: Team.Member) -> some View {
        let state = team.state(of: m)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(m.swatch).frame(width: 9, height: 9)
                Text(m.name).fontWeight(.semibold)
                if m.isLead { Text("lead").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1).background(.quaternary, in: Capsule()) }
                Spacer()
                Text(m.isLead ? row.status.label : state.label).font(.caption).foregroundStyle(m.isLead ? row.status.color : state.color)
            }
            if let type = m.agentType, !m.isLead { Text(type).font(.caption).foregroundStyle(.secondary) }
            if let t = team.currentTask(of: m) {
                Label(t.activeForm ?? t.subject, systemImage: "hammer").font(.caption).lineLimit(2)
            } else if case .idle(let reason?) = state {
                Label(reason, systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Text(m.paneId.map { "tmux pane \($0) – shown in the lead's terminal" } ?? (m.isLead ? "this session" : "runs inside the lead's process"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(m.swatch.opacity(0.35)))
    }

    private func board(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tasks").font(.headline)
            if team.tasks.isEmpty {
                Text("No tasks yet.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    column("Pending", team.tasks(.pending), team)
                    column("In progress", team.tasks(.inProgress), team)
                    column("Done", team.tasks(.completed), team)
                }
            }
        }
    }

    private func column(_ title: String, _ tasks: [Team.Task], _ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(tasks.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(tasks) { t in
                VStack(alignment: .leading, spacing: 3) {
                    Text(t.subject).font(.callout).lineLimit(3)
                    HStack(spacing: 4) {
                        if let owner = t.owner, let m = team.members.first(where: { $0.name == owner }) {
                            Circle().fill(m.swatch).frame(width: 6, height: 6)
                            Text(owner)
                        }
                        let waits = team.openBlockers(of: t)
                        if !waits.isEmpty, t.status != .completed { Text("· waits for #\(waits.joined(separator: ", #"))") }
                        Spacer()
                        Text("#\(t.id)").foregroundStyle(.tertiary)
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(.background.secondary))
                .help(t.description ?? t.subject)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func messages(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Messages").font(.headline)
            if team.messages.isEmpty { Text("No messages yet.").foregroundStyle(.secondary) }
            ForEach(team.messages.prefix(40)) { m in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: icon(m.kind)).foregroundStyle(.secondary).frame(width: 16)
                    Text("\(m.from) → \(m.to)").fontWeight(.medium)
                    Text(m.summary.isEmpty ? (m.kind ?? "") : m.summary).foregroundStyle(.secondary).lineLimit(2)
                    Spacer()
                    if let at = m.at { Text(ago(at, now: store.now)).font(.caption).foregroundStyle(.tertiary) }
                }
                .font(.callout)
            }
        }
    }

    private func icon(_ kind: String?) -> String {
        switch kind {
        case "idle_notification": "moon.zzz"
        case "task_assignment": "tray.and.arrow.down"
        case "task_completed": "checkmark.circle"
        case "shutdown_request", "shutdown_approved", "teammate_terminated": "power"
        case "shutdown_rejected": "xmark.circle"
        case "plan_approval_response": "checkmark.seal"
        default: "bubble.left"
        }
    }
}
