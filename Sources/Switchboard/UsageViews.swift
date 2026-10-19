import SessionCore
import StatusLineKit
import SwiftUI

extension PlanLimits.Outlook {
    /// green: lasts until the reset, orange: gets tight, red: runs out before it
    var color: Color {
        switch self {
        case .lasts: Palette.busy
        case .tight: Palette.block
        case .runsOut: Palette.need
        }
    }
}

/// Bottom of the sessions column: 5-hour and weekly limit as thin bars colored by whether they last until the
/// reset (green lasts, orange gets tight, red runs out), and today's tokens. A click opens the details.
struct UsageFooter: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: Store
    @State private var open = false

    var body: some View {
        let now = store.now
        Button { open.toggle() } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let l = usage.current(now: now), l.fiveHour != nil || l.sevenDay != nil {
                    if let w = l.fiveHour { bar("5-hour", w, length: PlanLimits.fiveHourLength, now: now) }
                    if let w = l.sevenDay { bar("Weekly", w, length: PlanLimits.weekLength, now: now) }
                } else {
                    Text(usage.setup == .installed ? "Plan limits appear with the next status line update" : "Plan limits: set up the live status line")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let t = usage.stats?.today {
                    Text("Today: \(UsageFormat.tokens(t.total)) tokens · \(UsageFormat.usd(t.usd))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PowerToggles().padding(.horizontal, 12).padding(.bottom, 8)
        }
        .overlay(alignment: .top) { Divider() }
        .help("Plan limits and token usage")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            UsagePopover().environmentObject(usage).environmentObject(store)
        }
        // `--show-usage` opens the details at launch (for trying things out); a popover needs the window first
        .task {
            guard CommandLine.arguments.contains("--show-usage") else { return }
            try? await Task.sleep(for: .seconds(2))
            open = true
        }
    }

    /// "5-hour  39%   resets in 2h 27m" over a thin bar; colored only when it won't last.
    private func bar(_ name: String, _ w: PlanLimits.Window, length: TimeInterval, now: Date) -> some View {
        let outlook = w.outlook(length: length, now: now)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(name)
                Text("\(Int(w.percent.rounded()))%").fontWeight(.semibold).monospacedDigit()
                Spacer()
                if let r = w.resetsAt {
                    Text(UsageFormat.countdown(r.timeIntervalSince(now))).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .font(.caption)
            ProgressView(value: min(1, max(0, w.percent / 100)))
                .controlSize(.small)
                .tint(outlook == .runsOut ? Palette.need : outlook == .tight ? Palette.block : Color.accentColor)
        }
    }
}

/// Both limits with bars and countdowns, then tokens over 1/7/30 days and the top sessions and projects.
struct UsagePopover: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var store: Store
    @AppStorage("usagePeriod") private var period: UsagePeriod = .week
    @State private var confirmSetup = false
    @State private var setupError: String?

    var body: some View {
        let now = store.now
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                limits(now: now)
                Divider()
                if let s = usage.stats { tokens(s) }
                else { HStack { ProgressView().controlSize(.small); Text("Reading transcripts…").foregroundStyle(.secondary) } }
            }
            .padding(18)
        }
        .frame(width: 380)
        .frame(maxHeight: 640)
        .alert("Set up the live status line?", isPresented: $confirmSetup) {
            Button("Set Up") { setupError = usage.installStatusLine() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(setupMessage)
        }
        .alert("Status line", isPresented: Binding(get: { setupError != nil }, set: { if !$0 { setupError = nil } })) {
            Button("OK") { setupError = nil }
        } message: { Text(setupError ?? "") }
    }

    @ViewBuilder
    private func limits(now: Date) -> some View {
        if let l = usage.current(now: now) {
            VStack(alignment: .leading, spacing: 14) {
                if let w = l.fiveHour { LimitRow(title: "5-hour window", window: w, length: PlanLimits.fiveHourLength, now: now) }
                if let w = l.sevenDay { LimitRow(title: "Week", window: w, length: PlanLimits.weekLength, now: now) }
                ForEach(l.scoped, id: \.name) { s in
                    LimitRow(title: "Week · \(s.name)", window: s.window, length: PlanLimits.weekLength, now: now)
                }
            }
            Text(source(l, now: now)).font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("No current plan limits").font(.headline)
                Text("Claude Code only hands its live 5-hour and weekly usage to a status line command. Its own cache in ~/.claude.json is used when it is fresh, but it isn't right now.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        setupRow
    }

    @ViewBuilder
    private var setupRow: some View {
        switch usage.setup {
        case .installed:
            Label("Live status line installed; limits update whenever a session refreshes its status line.", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .notConfigured, .other:
            Button { confirmSetup = true } label: { Label("Set Up Live Status Line…", systemImage: "gauge.with.dots.needle.67percent") }
                .controlSize(.small)
        case .unknown:
            EmptyView()
        }
    }

    private var setupMessage: String {
        var s = "This copies switchboard-statusline to ~/.switchboard/bin and sets \"statusLine\" in ~/.claude/settings.json (a timestamped backup is saved next to it). Claude Code then hands it the plan limits, context and cost of each session; it stores them in ~/.switchboard and shows a short line under the prompt."
        if case .other(let cmd) = usage.setup { s += "\n\nYour current status line command will be replaced:\n\(cmd)" }
        return s
    }

    private func source(_ l: PlanLimits, now: Date) -> String {
        let from = l.source == .statusLine ? "from the status line" : "from Claude Code's cache"
        let age = UsageFormat.age(now.timeIntervalSince(l.fetchedAt))
        return "\(from), \(age == "<1 min" ? "just now" : "\(age) ago")"
    }

    @ViewBuilder
    private func tokens(_ s: UsageStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TokenHeader(title: "Tokens")
            TokenRow(name: "Today", tokens: s.today, bold: true)
            TokenRow(name: "Last 7 days", tokens: s.last7Days, bold: true)
            TokenRow(name: "Last 30 days", tokens: s.last30Days, bold: true)
            DayBars(days: Array(s.days.prefix(UsagePeriod.month.days))).padding(.top, 4)
            Text("Bars: output tokens per day. Total includes cache reads. API $: value at Anthropic's API list prices, not what a subscription costs.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Divider()
        Picker("", selection: $period) {
            ForEach(UsagePeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        let sessions = s.sessions(period), projects = s.projects(period)
        if sessions.isEmpty && projects.isEmpty {
            Text("No usage \(period == .today ? "today" : "in the last \(period.label)").").foregroundStyle(.secondary)
        }
        if !sessions.isEmpty { section("Sessions · \(period.label.lowercased())", sessions) }
        if !projects.isEmpty { section("Projects · \(period.label.lowercased())", projects) }
    }

    private func section(_ title: String, _ rows: [UsageStats.Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TokenHeader(title: title)
            ForEach(rows.prefix(8)) { r in TokenRow(name: r.name, tokens: r.tokens) }
        }
    }
}

extension UsagePeriod {
    var label: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }
}

private enum PaceArrow {
    static func text(_ pace: PlanLimits.Pace) -> Text {
        let symbol = switch pace.outlook {
        case .lasts: "arrow.down.right"
        case .tight: "arrow.right"
        case .runsOut: "arrow.up.right"
        }
        return Text(Image(systemName: symbol)).font(.system(size: 10, weight: .bold)).foregroundColor(pace.outlook.color)
    }

    static func sentence(_ pace: PlanLimits.Pace) -> String {
        if let t = pace.runsOutIn { return t <= 0 ? "limit reached" : "runs out in \(UsageFormat.countdown(t)) at this pace" }
        return "\(pace.outlook == .tight ? "tight" : "lasts") · about \(Int(pace.projectedPercent.rounded())) % at the reset at this pace"
    }
}

private struct LimitRow: View {
    let title: String
    let window: PlanLimits.Window
    let length: TimeInterval
    let now: Date

    var body: some View {
        let color = window.outlook(length: length, now: now)?.color
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.medium)
                Spacer()
                Text("\(Int(window.percent.rounded())) %").fontWeight(.semibold).monospacedDigit().foregroundStyle(color ?? .primary)
            }
            ProgressView(value: min(1, max(0, window.percent / 100))).tint(color ?? .accentColor)
            if let r = window.resetsAt {
                Text("resets in \(UsageFormat.countdown(r.timeIntervalSince(now))) · \(r.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            if let pace = window.pace(length: length, now: now) {
                (PaceArrow.text(pace) + Text(" ") + Text(PaceArrow.sentence(pace)).foregroundColor(pace.outlook == .lasts ? .secondary : pace.outlook.color))
                    .font(.caption).monospacedDigit()
            }
        }
    }
}

private struct TokenHeader: View {
    let title: String
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("Output").frame(width: 60, alignment: .trailing)
            Text("Total").frame(width: 60, alignment: .trailing)
            Text("API $").frame(width: 60, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}

private struct TokenRow: View {
    let name: String
    let tokens: TokenCounts
    var bold = false

    var body: some View {
        HStack {
            Text(name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(UsageFormat.tokens(tokens.output)).frame(width: 60, alignment: .trailing)
            Text(UsageFormat.tokens(tokens.total)).frame(width: 60, alignment: .trailing).foregroundStyle(.secondary)
            Text(UsageFormat.usd(tokens.usd)).frame(width: 60, alignment: .trailing)
        }
        .font(.system(size: 12.5, weight: bold ? .medium : .regular)).monospacedDigit()
    }
}

/// Output tokens per day, oldest on the left, today on the right.
private struct DayBars: View {
    let days: [UsageStats.Day]

    var body: some View {
        let peak = max(1, days.map(\.tokens.output).max() ?? 1)
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(days.enumerated().reversed()), id: \.offset) { i, d in
                let h = d.tokens.output == 0 ? 0 : max(2, 28 * Double(d.tokens.output) / Double(peak))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5).fill(i == 0 ? Color.accentColor : Color.secondary.opacity(0.35)).frame(height: h)
                }
                .frame(maxWidth: .infinity)
                .help("\(d.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))): \(UsageFormat.tokens(d.tokens.output)) output · \(UsageFormat.usd(d.tokens.usd))")
            }
        }
        .frame(height: 28)
    }
}
