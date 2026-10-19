import AppKit
import SessionCore
import StatusLineKit
import SwiftUI

/// The selected session at a glance, most useful first: its state and what it needs, the conversation, context
/// and cost, then tokens and technical details. The header above already shows the name, folder and branch.
struct InfoTab: View {
    @Environment(Store.self) private var store
    @Environment(UsageStore.self) private var usage
    let row: Row

    var body: some View {
        let s = row.session
        Form {
            StatusSection(row: row)
            if let hit = s.limitHit { LimitSection(row: row, hit: hit) }
            SubagentsSection(session: s)
            if s.lastUser != nil || s.lastAssistant != nil { ConversationSection(session: s) }
            ContextCostSection(session: s)
            TokensSection(session: s)
            DetailsSection(row: row)
            if !s.errors.isEmpty {
                Section("Problems") {
                    ForEach(s.errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.need) }
                }
            }
        }
        .formStyle(.grouped)
        .labelStyle(RowLabel())
        .themeBackground()
    }
}

/// Row titles with their icons in one column, whatever the symbol's width.
private struct RowLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(.secondary).frame(width: 18, alignment: .center)
            configuration.title
        }
    }
}

// MARK: Status

/// State, time in it, what the session needs or does now, its task, and the one action that fits.
private struct StatusSection: View {
    @Environment(Store.self) private var store
    let row: Row

    var body: some View {
        let s = row.session, status = row.status
        Section {
            HStack(alignment: .center, spacing: 10) {
                StatusDot(status: status).scaleEffect(1.5).frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label.prefix(1).uppercased() + status.label.dropFirst())
                        .font(.headline).foregroundStyle(status.rank == 0 ? status.color : .primary)
                    if let since = since(s) { Text(since).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                action
            }
            .padding(.vertical, 2)

            if let w = s.waitingFor ?? (status.rank == 0 ? status.why : nil) {
                Callout(text: w, color: status.color, symbol: "hand.raised.fill")
            }
            // "Last words" of a finished session are already in the conversation below
            if let now = NowLine(s, rank: status.rank), now.text != s.waitingFor, !(now.kind == .done && s.lastAssistant != nil) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(now.kind == .working ? "Now" : now.kind == .done ? "Last words" : "Asks")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(now.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let d = now.detail {
                        Text(d).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(3)
                    }
                    ForEach(now.options, id: \.self) { o in
                        Label(o, systemImage: "circle").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if status.rank == 0 {
                if row.tmux != nil {
                    AnswerPanel(row: row)
                } else if s.alive {
                    Text("It runs in another app's terminal: answer it there, or move it into Switchboard.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let task = s.task {
                LabeledContent {
                    // the state only when the status above doesn't already say it
                    Text(task.state.flatMap { $0 == "working" ? nil : "\(task.text) · \($0)" } ?? task.text)
                        .multilineTextAlignment(.trailing).textSelection(.enabled)
                        .foregroundStyle(task.stale ? .secondary : .primary)
                } label: {
                    Label("Task", systemImage: "checklist")
                }
                .help(task.stale ? "Working, but the task line is over an hour old" : (task.detail ?? task.text))
            }
            if s.backgroundTasks > 0 {
                LabeledContent {
                    Text("\(s.backgroundTasks) running")
                } label: {
                    Label("Background tasks", systemImage: "gearshape.2")
                }
            }
            if s.remoteControl {
                LabeledContent { Text("Connected") } label: { Label("Remote Control", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
    }

    /// "for 12 min" in this status, "since 3:10 PM" for long ones
    private func since(_ s: Session) -> String? {
        let d = dur(s.statusUpdatedAt, now: store.now)
        return d.isEmpty ? nil : "for \(d)"
    }

    @ViewBuilder
    private var action: some View {
        if row.tmux != nil {
            Button { store.focusTerminal() } label: { Label("Open Terminal", systemImage: "terminal") }
                .help("Show the terminal and type into it (⌘J)")
        } else if store.canMoveIn(row) {
            Button { store.requestMoveIn(row) } label: {
                Label(row.session.alive ? "Move into Switchboard…" : "Resume in Switchboard",
                      systemImage: row.session.alive ? "arrow.down.right.and.arrow.up.left" : "play.fill")
            }
            .disabled(store.moving.contains(row.name))
            .help("Continue the conversation in Switchboard's terminal with claude --resume")
        }
    }
}

/// A tinted box for what the session needs from you; long requests wrap instead of being cut.
private struct Callout: View {
    let text: String
    let color: Color
    let symbol: String

    var body: some View {
        Label {
            Text(text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: Conversation

private struct ConversationSection: View {
    @Environment(Store.self) private var store
    let session: Session

    var body: some View {
        Section("Conversation") {
            if let u = session.lastUser { Message(who: "You", symbol: "person.fill", said: u, now: store.now) }
            if let a = session.lastAssistant { Message(who: "Claude", symbol: "sparkle", said: a, now: store.now) }
        }
    }
}

/// One message: who and when, then four lines with "Show More" for the rest.
private struct Message: View {
    let who: String
    let symbol: String
    let said: Said
    let now: Date
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Label(who, systemImage: symbol).font(.caption.weight(.semibold))
                Text(ago(said.at, now: now)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { copy(said.text) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).font(.caption).help("Copy the message")
            }
            Text(said.text).textSelection(.enabled)
                .lineLimit(expanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
            if !expanded && (said.text.count > 280 || said.text.filter { $0 == "\n" }.count > 3) {
                Button("Show More") { expanded = true }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Context and cost

private struct ContextCostSection: View {
    @Environment(UsageStore.self) private var usage
    @Environment(Store.self) private var store
    let session: Session

    var body: some View {
        let line = usage.line(session), total = usage.tokens(session)
        let percent = session.contextPercent ?? line?.contextPercent
        Section {
            if let percent {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Context", systemImage: "gauge.with.dots.needle.50percent")
                        Spacer()
                        Text(contextText(percent, line)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    ContextBar(fraction: min(percent, 100) / 100, color: contextColor(percent))
                }
                .help("How full the context window is. Claude Code compacts the conversation when it is full.")
            }
            if let c = line?.costUSD {
                LabeledContent { Text(UsageFormat.usd(c)).monospacedDigit() } label: {
                    Label("Cost", systemImage: "dollarsign.circle")
                }
                .help("What Claude Code reports for this session")
            }
            if let total, total.total > 0 {
                LabeledContent { Text(UsageFormat.usd(total.usd)).monospacedDigit() } label: {
                    Label("Value at API prices", systemImage: "chart.bar")
                }
                .help("This session's tokens over 31 days at API list prices: an estimate, not a bill")
            }
            if let m = line?.model ?? session.model.map(ModelName.short) {
                LabeledContent { Text(line?.effort.map { "\(m) · \($0.capitalized)" } ?? m) } label: {
                    Label("Model", systemImage: "cpu")
                }
            }
            if let a = line?.linesAdded, let r = line?.linesRemoved, a + r > 0 {
                LabeledContent {
                    HStack(spacing: 6) {
                        Text("+\(a)").foregroundStyle(Palette.added)
                        Text("−\(r)").foregroundStyle(Palette.deleted)
                    }
                    .monospacedDigit()
                } label: {
                    Label("Lines changed", systemImage: "plusminus")
                }
            }
            if percent == nil && line == nil && (total?.total ?? 0) == 0 {
                Text("No usage yet.").foregroundStyle(.secondary)
            }
        } header: {
            Text("Context and cost")
        } footer: {
            if let line {
                Text("From Claude Code's status line, updated \(ago(line.writtenAt, now: store.now)).")
                    .font(.caption).foregroundStyle(.secondary)
            } else if session.alive {
                Text("Set up the live status line (click the usage bars) for cost, context and model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// "58 % · 580k of 1.0M"
    private func contextText(_ p: Double, _ line: SessionLine?) -> String {
        var s = "\(Int(p.rounded())) %"
        if let t = line?.contextTokens, let w = line?.contextWindow { s += " · \(UsageFormat.tokens(t)) of \(UsageFormat.tokens(w))" }
        return s
    }

    private func contextColor(_ p: Double) -> Color {
        p >= 85 ? Palette.need : p >= 65 ? Palette.block : Palette.busy
    }
}

/// The context window as a bar in the status colors: green, orange from 65 %, red from 85 %.
private struct ContextBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color).frame(width: max(6, g.size.width * fraction))
            }
        }
        .frame(height: 6)
    }
}

// MARK: Tokens

/// The token breakdown, folded away by default (most people want the totals above).
private struct TokensSection: View {
    @Environment(UsageStore.self) private var usage
    @AppStorage("infoTokensOpen") private var open = false
    let session: Session

    var body: some View {
        let total = usage.tokens(session), today = usage.tokensToday(session)
        Section {
            DisclosureGroup(isExpanded: $open) {
                if let total {
                    Grid(alignment: .trailing, horizontalSpacing: 24, verticalSpacing: 6) {
                        GridRow {
                            Text("").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Today").foregroundStyle(.secondary)
                            Text("31 days").foregroundStyle(.secondary)
                        }
                        row("Input", \.input, today, total)
                        row("Output", \.output, today, total)
                        row("Cache writes", \.cacheCreation, today, total)
                        row("Cache reads", \.cacheRead, today, total)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        row("Total", \.total, today, total, bold: true)
                        GridRow {
                            Text("Value at API prices").frame(maxWidth: .infinity, alignment: .leading)
                            Text(UsageFormat.usd(today?.usd ?? 0))
                            Text(UsageFormat.usd(total.usd)).fontWeight(.medium)
                        }
                    }
                    .monospacedDigit()
                    .padding(.top, 6)
                } else if usage.stats == nil {
                    HStack { ProgressView().controlSize(.small); Text("Reading transcripts…").foregroundStyle(.secondary) }
                } else {
                    Text(session.sessionId == nil ? "Not a Claude session." : "No tokens in the last 31 days.")
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack {
                    Label("Tokens", systemImage: "number")
                    Spacer()
                    if let total, total.total > 0 {
                        Text("\(UsageFormat.tokens(total.total)) in 31 days").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { open.toggle() } }
            }
        } footer: {
            if open {
                Text("Counted from this session's transcript and its subagents.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ name: String, _ key: KeyPath<TokenCounts, Int>, _ today: TokenCounts?, _ total: TokenCounts,
                     bold: Bool = false) -> some View {
        GridRow {
            Text(name).fontWeight(bold ? .medium : .regular).frame(maxWidth: .infinity, alignment: .leading)
            Text(UsageFormat.tokens(today?[keyPath: key] ?? 0))
            Text(UsageFormat.tokens(total[keyPath: key])).fontWeight(bold ? .medium : .regular)
        }
    }
}

// MARK: Details

/// Where the session lives and how to reach it from elsewhere, each with a copy button.
private struct DetailsSection: View {
    @Environment(Store.self) private var store
    let row: Row

    var body: some View {
        let s = row.session
        Section("Details") {
            if let cwd = store.folder(of: row) {
                DetailRow(title: "Folder", symbol: "folder", value: abbreviated(cwd), copyValue: cwd) {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .help("Reveal in Finder")
                }
            }
            if let b = s.branch, b != "HEAD" { DetailRow(title: "Branch", symbol: "arrow.triangle.branch", value: b) }
            if !s.project.isEmpty && s.project != s.name { DetailRow(title: "Project", symbol: "shippingbox", value: s.project) }
            if let id = s.sessionId {
                DetailRow(title: "Session ID", symbol: "number.square", value: id, mono: true)
                    .help("For claude --resume \(id)")
            }
            if let pid = s.pid, s.alive { DetailRow(title: "Process", symbol: "cpu", value: "PID \(pid)", copyValue: String(pid)) }
            if let t = row.tmux {
                DetailRow(title: "Attach", symbol: "terminal", value: "tmux -L \(Tmux.socket) attach -t '=\(t):'", mono: true)
                    .help("Open this session's terminal from any terminal app")
            }
        }
    }
}

/// "Folder    ~/Projects/app  [copy] [extra]": the value is selectable and never pushes the title away.
private struct DetailRow<Extra: View>: View {
    let title: String
    let symbol: String
    let value: String
    var copyValue: String? = nil
    var mono = false
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Text(value)
                    .font(mono ? .callout.monospaced() : .body)
                    .lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Button { copy(copyValue ?? value) } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy")
                extra()
            }
            .buttonStyle(.borderless)
        } label: {
            Label(title, systemImage: symbol)
        }
    }
}

extension DetailRow where Extra == EmptyView {
    init(title: String, symbol: String, value: String, copyValue: String? = nil, mono: Bool = false) {
        self.init(title: title, symbol: symbol, value: value, copyValue: copyValue, mono: mono, extra: { EmptyView() })
    }
}

private func copy(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}
