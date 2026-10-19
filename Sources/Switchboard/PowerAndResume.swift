import AppKit
import Foundation
import IOKit.pwr_mgt
import SessionCore
import SwiftUI

/// Light, dark, or whatever macOS uses.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    /// nil follows macOS
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// App settings (Settings, ⌘,): appearance, keeping the Mac awake, continuing sessions after a usage limit.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var appearance: Appearance {
        didSet {
            d.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }

    @Published var iconStyle: IconStyle {
        didSet {
            d.set(iconStyle.rawValue, forKey: "iconStyle")
            NSApp.applicationIconImage = AppIcon.image(size: 512)
        }
    }

    @Published var switchTint: SwitchTint {
        didSet {
            d.set(switchTint.rawValue, forKey: "switchTint")
            NSApp.applicationIconImage = AppIcon.image(size: 512)
        }
    }

    /// Sets it for the whole app: every window, the terminal and the editor follow.
    func applyAppearance() {
        // a theme other than Automatic is light or dark by itself (Dracula is always dark)
        let theme = EditorTheme.current
        NSApp.appearance = theme.themesApp ? NSAppearance(named: theme.palette(dark: true).dark ? .darkAqua : .aqua)
            : appearance.nsAppearance
        // the Auto icon follows (also when macOS itself switches, see AppDelegate)
        DispatchQueue.main.async { NSApp.applicationIconImage = AppIcon.image(size: 512) }
    }

    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: "keepAwake") } }
    @Published var keepDisplayOn: Bool { didSet { d.set(keepDisplayOn, forKey: "keepDisplayOn") } }
    /// count a session waiting for its limit to reset as working, so the Mac is awake to continue it
    @Published var awakeForResume: Bool { didSet { d.set(awakeForResume, forKey: "awakeForResume") } }

    @Published var autoContinue: Bool { didSet { d.set(autoContinue, forKey: "autoContinue") } }
    @Published var continueMessage: String { didSet { d.set(continueMessage, forKey: "continueMessage") } }
    /// sessions that should not be continued automatically (names)
    @Published var autoContinueOff: [String] { didSet { d.set(autoContinueOff, forKey: "autoContinueOff") } }
    /// start new sessions with Claude Code's unattended retry mode (it waits out the limit itself)
    @Published var retryWatchdog: Bool { didSet { d.set(retryWatchdog, forKey: "retryWatchdog") } }
    /// the longest a watchdog session waits for a limit, in hours; 0 = no cap
    @Published var watchdogMaxHours: Int { didSet { d.set(watchdogMaxHours, forKey: "watchdogMaxHours") } }

    // Notifications (see Notifications.swift): which kinds, and how
    @Published var notifyNeedsYou: Bool { didSet { d.set(notifyNeedsYou, forKey: "notifyNeedsYou") } }
    @Published var notifyFinished: Bool { didSet { d.set(notifyFinished, forKey: "notifyFinished") } }
    @Published var notifyUsageLimit: Bool { didSet { d.set(notifyUsageLimit, forKey: "notifyUsageLimit") } }
    @Published var notifySubagentFinished: Bool { didSet { d.set(notifySubagentFinished, forKey: "notifySubagentFinished") } }
    @Published var notifyEnded: Bool { didSet { d.set(notifyEnded, forKey: "notifyEnded") } }
    @Published var notifySound: Bool { didSet { d.set(notifySound, forKey: "notifySound") } }
    /// the number of sessions that need you on the Dock icon
    @Published var dockBadge: Bool { didSet { d.set(dockBadge, forKey: "dockBadge") } }
    /// no notifications while Switchboard is the frontmost app
    @Published var notifyOnlyInBackground: Bool { didSet { d.set(notifyOnlyInBackground, forKey: "notifyOnlyInBackground") } }

    private init() {
        appearance = Appearance(rawValue: d.string(forKey: "appearance") ?? "") ?? .system
        iconStyle = .current
        switchTint = .current
        keepAwake = d.object(forKey: "keepAwake") as? Bool ?? true
        keepDisplayOn = d.bool(forKey: "keepDisplayOn")
        awakeForResume = d.object(forKey: "awakeForResume") as? Bool ?? true
        autoContinue = d.bool(forKey: "autoContinue")
        continueMessage = d.string(forKey: "continueMessage") ?? "continue"
        autoContinueOff = d.stringArray(forKey: "autoContinueOff") ?? []
        retryWatchdog = d.bool(forKey: "retryWatchdog")
        watchdogMaxHours = d.object(forKey: "watchdogMaxHours") as? Int ?? 6
        notifyNeedsYou = d.object(forKey: "notifyNeedsYou") as? Bool ?? true
        notifyFinished = d.object(forKey: "notifyFinished") as? Bool ?? true
        notifyUsageLimit = d.object(forKey: "notifyUsageLimit") as? Bool ?? true
        notifySubagentFinished = d.object(forKey: "notifySubagentFinished") as? Bool ?? true
        notifyEnded = d.bool(forKey: "notifyEnded")
        notifySound = d.object(forKey: "notifySound") as? Bool ?? true
        dockBadge = d.object(forKey: "dockBadge") as? Bool ?? true
        notifyOnlyInBackground = d.bool(forKey: "notifyOnlyInBackground")
    }

    /// Whether notifications of this kind are on.
    func notifies(_ kind: NotificationKind) -> Bool {
        switch kind {
        case .needsYou: notifyNeedsYou
        case .finished: notifyFinished
        case .usageLimit, .continued: notifyUsageLimit
        case .subagentFinished: notifySubagentFinished
        case .ended: notifyEnded
        }
    }

    func continues(_ name: String) -> Bool { autoContinue && !autoContinueOff.contains(name) }

    func setContinues(_ name: String, _ on: Bool) {
        autoContinueOff = on ? autoContinueOff.filter { $0 != name } : autoContinueOff + [name]
    }

    /// Environment for a new session's tmux: Claude Code's unattended retry mode, if chosen.
    var newSessionEnvironment: [String: String] {
        guard retryWatchdog else { return [:] }
        var env = ["CLAUDE_CODE_RETRY_WATCHDOG": "1"]
        if watchdogMaxHours > 0 { env["CLAUDE_CODE_RETRY_WATCHDOG_MAX_USAGE_LIMIT_WAIT_MS"] = String(watchdogMaxHours * 3_600_000) }
        return env
    }
}

/// A power assertion while sessions work, like `caffeinate -i` (and `-d` with the display option). Shows in
/// `pmset -g assertions` under the reason. It can't stop sleep when the lid closes on battery; macOS decides that.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    /// what is holding the Mac awake right now, nil = not holding
    @Published private(set) var reason: String?
    private var systemID: IOPMAssertionID = 0
    private var displayID: IOPMAssertionID = 0
    private var systemReason: String?
    private var displayReason: String?

    /// `working`: sessions working (or waiting to be continued). Takes or releases the assertions.
    func update(working: Int, waitingForReset: Int, settings: AppSettings) {
        let counted = working + (settings.awakeForResume ? waitingForReset : 0)
        let wanted: String? = settings.keepAwake && counted > 0 ? Self.describe(working, settings.awakeForResume ? waitingForReset : 0) : nil
        hold(&systemID, &systemReason, kIOPMAssertionTypePreventUserIdleSystemSleep, wanted)
        hold(&displayID, &displayReason, kIOPMAssertionTypePreventUserIdleDisplaySleep, settings.keepDisplayOn ? wanted : nil)
        if wanted != reason { reason = wanted }
    }

    static func describe(_ working: Int, _ waiting: Int) -> String {
        var parts: [String] = []
        if working > 0 { parts.append(working == 1 ? "1 session working" : "\(working) sessions working") }
        if waiting > 0 { parts.append(waiting == 1 ? "1 waiting for its limit to reset" : "\(waiting) waiting for limits to reset") }
        return "Switchboard: " + parts.joined(separator: ", ")
    }

    /// Takes, renames or releases one assertion; nothing happens while the reason stays the same.
    private func hold(_ id: inout IOPMAssertionID, _ current: inout String?, _ type: String, _ reason: String?) {
        guard reason != current else { return }
        current = reason
        if id != 0 {
            IOPMAssertionRelease(id)
            id = 0
        }
        guard let reason else { return }
        IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), reason as CFString, &id)
    }
}

/// Continues sessions that stopped at a usage limit: once the limit has reset, types the continue message
/// (default "continue") into the session's terminal, once per limit hit. Only sessions in Switchboard's tmux
/// server can be continued; only if nothing was said in the conversation since the limit (the parser checks
/// that the limit message is still the newest one).
@MainActor
final class AutoContinue: ObservableObject {
    static let shared = AutoContinue()

    struct Pending: Equatable {
        let name: String
        let resetAt: Date?
        /// would be continued (setting on, not turned off for it, runs in our tmux)
        let willContinue: Bool
        let reasonNot: String?
    }

    /// sessions standing at a limit, by name
    @Published private(set) var pending: [String: Pending] = [:]
    /// last resumes, newest first (shown in Settings)
    @Published private(set) var log: [String] = []
    /// limit hits already continued: name → hit time
    private var done: [String: String] = [:]
    /// a minute after the reset, so the limit has really lifted
    static let grace: TimeInterval = 60

    func update(rows: [Row], limits: PlanLimits?, settings: AppSettings, now: Date) {
        var p: [String: Pending] = [:]
        for r in rows {
            guard let hit = r.session.limitHit, r.session.alive else { continue }
            if let at = hit.at, done[r.name] == at { continue }
            let reset = UsageLimit.reset(of: hit, limits: limits)
            let why: String? = !settings.autoContinue ? "auto-continue is off"
                : !settings.continues(r.name) ? "turned off for this session"
                : r.tmux == nil ? "runs outside Switchboard's tmux, so it can't be typed into"
                : reset == nil ? "reset time unknown"
                : nil
            p[r.name] = Pending(name: r.name, resetAt: reset, willContinue: why == nil, reasonNot: why)
            guard why == nil, let reset, let tmux = r.tmux, now >= reset.addingTimeInterval(Self.grace),
                  r.session.status != "busy" else { continue }
            send(settings.continueMessage, to: tmux, name: r.name, hit: hit)
            p[r.name] = nil
        }
        if p != pending { pending = p }
    }

    /// "Continue Now" in the Info tab, or the automatic resume.
    func continueNow(_ r: Row, message: String) {
        guard let tmux = r.tmux, let hit = r.session.limitHit else { return }
        send(message, to: tmux, name: r.name, hit: hit)
        pending[r.name] = nil
    }

    private func send(_ message: String, to tmux: String, name: String, hit: LimitHit) {
        done[name] = hit.at ?? ISO8601DateFormatter().string(from: Date())
        let text = SessionControl.replyText(message) ?? "continue"
        Task.detached {
            let err = Tmux.type(text, into: tmux)
            await MainActor.run {
                let time = Date().formatted(date: .omitted, time: .shortened)
                self.log.insert(err.map { "\(time) \(name): couldn't continue – \($0)" } ?? "\(time) \(name): continued after the usage limit reset", at: 0)
                self.log = Array(self.log.prefix(20))
                if err == nil { Notifier.shared.continued(name) }
            }
        }
    }
}
