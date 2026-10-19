import AppKit
import Observation
import SessionCore
import SwiftUI
import UserNotifications

/// The notifications the user can turn on and off one by one (Settings → Notifications).
enum NotificationKind: String, CaseIterable, Identifiable {
    case needsYou, finished, usageLimit, continued, subagentFinished, ended
    var id: String { rawValue }

    init(_ kind: SessionEvent.Kind) {
        switch kind {
        case .needsYou: self = .needsYou
        case .finished: self = .finished
        case .usageLimit: self = .usageLimit
        case .ended: self = .ended
        }
    }

    /// the tab a click opens: the terminal to answer, the Info tab for the rest
    var tab: DetailTab { self == .needsYou ? .terminal : .info }
}

/// Turns session events into macOS notifications, keeps the Dock badge, and opens the session when a
/// notification is clicked. `SessionEventTracker` (SessionCore) decides what happened between two refreshes.
///
/// `UNUserNotificationCenter` only works inside an app bundle. Run as a bare executable (`swift run`), the app
/// has no bundle identifier and the center would crash, so it bounces the Dock icon instead.
@MainActor
@Observable
final class Notifier: NSObject {
    static let shared = Notifier()

    /// the system's answer; nil until asked (lazily, the first time a notification is due or a kind is turned on)
    private(set) var authorization: UNAuthorizationStatus?
    /// false as a bare executable: no notification center, only the Dock icon and a sound
    let hasCenter = Bundle.main.bundleIdentifier != nil
    /// set by the Store: shows the session (and tab) of a clicked notification
    @ObservationIgnored var open: ((String, DetailTab) -> Void)?
    /// set by the Store: shows a message in the app (an answer from a notification that couldn't be sent)
    @ObservationIgnored var notice: ((String) -> Void)?

    /// Notification categories with answer buttons, for a session that needs you
    enum Category {
        static let permission = "needs-permission"
        static let question = "needs-reply"
    }

    @ObservationIgnored private var tracker = SessionEventTracker()
    @ObservationIgnored private var installed = false
    @ObservationIgnored private var warnedOnce = false
    @ObservationIgnored private var badge: String?

    var denied: Bool { authorization == .denied }

    override init() {
        super.init()
        // receive clicks from the start (also on notifications from before a relaunch); asks for nothing yet
        if hasCenter { install() }
    }

    /// Called after every refresh with the new rows. Fires only on changes since the last call.
    func update(rows: [Row], selected: String?, now: Date) {
        let snapshots = rows.map {
            SessionSnapshot(name: $0.name, rank: $0.status.rank, why: $0.status.why,
                            limitHit: $0.session.limitHit.map { $0.at ?? $0.text })
        }
        let events = tracker.update(snapshots, now: now)
        showBadge(rows.filter { $0.status.rank == 0 }.count)
        for e in events {
            let row = rows.first { $0.name == e.name }
            let (title, body) = text(for: e, row: row)
            post(NotificationKind(e.kind), name: e.name, title: title, body: body, selected: selected,
                 answer: e.kind == .needsYou ? answerable(row) : nil)
        }
    }

    /// Switchboard typed the continue message into the session after its limit reset (AutoContinue).
    func continued(_ name: String) {
        post(.continued, name: name, title: "\(name) continues", body: "The usage limit reset, so Switchboard typed “continue”.",
             selected: nil)
    }

    /// A subagent of `session` stopped (called by `SubagentStore` when a running subagent no longer runs).
    func subagentFinished(session: String, subagent: String) {
        post(.subagentFinished, name: session, title: "\(session): subagent finished", body: subagent, selected: nil)
    }

    /// Which answer buttons a "needs you" notification gets: Allow / Deny for a permission, a reply field for a
    /// question; none for a session outside Switchboard's tmux (nothing to type into) or a multiple choice.
    private func answerable(_ row: Row?) -> (category: String, tmux: String)? {
        guard let row, let tmux = row.tmux, let now = NowLine(row.session, rank: 0) else { return nil }
        switch now.kind {
        case .permission: return (Category.permission, tmux)
        case .question: return (Category.question, tmux)
        default: return nil
        }
    }

    private func text(for e: SessionEvent, row: Row?) -> (String, String) {
        switch e.kind {
        case .needsYou: ("\(e.name) needs you", e.detail ?? "Input needed")
        case .finished: ("\(e.name) finished", row?.session.lastSentence ?? "Ready for your next message")
        case .usageLimit:
            ("\(e.name) hit a usage limit", {
                let hit = row?.session.limitHit?.text ?? "Usage limit reached"
                guard let p = AutoContinue.shared.pending[e.name], p.willContinue, let at = p.resetAt else { return hit }
                return "\(hit) · continues \(at.formatted(date: .omitted, time: .shortened))"
            }())
        case .ended: ("\(e.name) ended", "The session went offline.")
        }
    }

    // MARK: Delivery

    /// `selected`: the session on screen; it gets no notification while Switchboard is in front.
    private func post(_ kind: NotificationKind, name: String, title: String, body: String, selected: String?,
                      answer: (category: String, tmux: String)? = nil) {
        let settings = AppSettings.shared
        guard settings.notifies(kind) else { return }
        if NSApp.isActive, settings.notifyOnlyInBackground || selected == name { return }
        guard hasCenter else { fallback(settings); return }
        Task { await deliver(kind, name: name, title: title, body: body, sound: settings.notifySound, answer: answer) }
    }

    /// Without a bundle: bounce the Dock icon (macOS ignores it while the app is in front) and play the sound.
    private func fallback(_ settings: AppSettings) {
        if !warnedOnce {
            warnedOnce = true
            NSLog("Switchboard: no bundle identifier, so notifications only bounce the Dock icon (run Switchboard.app for banners)")
        }
        NSApp.requestUserAttention(.informationalRequest)
        if settings.notifySound { NSSound(named: "Glass")?.play() }
    }

    private func deliver(_ kind: NotificationKind, name: String, title: String, body: String, sound: Bool,
                         answer: (category: String, tmux: String)?) async {
        guard await authorize() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound ? .default : nil
        var info: [String: Any] = ["name": name, "tab": kind.tab.rawValue]
        if let answer {
            // the dialog as it is now: an answer button only acts on this very dialog, not on a later one
            let tmux = answer.tmux
            let shown = await Task.detached { SessionAnswer.dialog(tmux) }.value
            if answer.category == Category.question || shown != nil {
                content.categoryIdentifier = answer.category
                info["tmux"] = tmux
                if let shown { info["dialog"] = Self.fingerprint(shown) }
            }
        }
        content.userInfo = info
        content.threadIdentifier = name
        // one per session and kind: a newer one replaces the older in Notification Center
        let request = UNNotificationRequest(identifier: "\(kind.rawValue)-\(name)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Asks macOS the first time; afterwards only reads the answer. False when denied (or no bundle).
    @discardableResult
    func authorize() async -> Bool {
        guard hasCenter else { return false }
        install()
        let center = UNUserNotificationCenter.current()
        var status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            status = await center.notificationSettings().authorizationStatus
        }
        if status != authorization { authorization = status }
        return status != .denied
    }

    /// Re-reads the answer (when Settings opens: the user may have changed it in System Settings).
    func refreshAuthorization() {
        guard hasCenter else { return }
        Task {
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            if status != authorization { authorization = status }
        }
    }

    private func install() {
        guard !installed else { return }
        installed = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // answer buttons; they act in the background, without bringing Switchboard forward
        let allow = UNNotificationAction(identifier: "allow", title: "Allow")
        let always = UNNotificationAction(identifier: "always", title: "Always Allow")
        let deny = UNNotificationAction(identifier: "deny", title: "Deny", options: [.destructive])
        let reply = UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [],
                                                  textInputButtonTitle: "Send", textInputPlaceholder: "Reply to Claude")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.permission, actions: [allow, always, deny], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.question, actions: [reply], intentIdentifiers: []),
        ])
    }

    /// What identifies a dialog: its options and the text above them.
    nonisolated static func fingerprint(_ d: ScreenDialog) -> String {
        (d.context + d.options.map { "\($0.number). \($0.label)" }).joined(separator: "\n")
    }

    /// An answer button of a notification: sends it if the session still shows the same prompt, else says why not
    /// and shows the session.
    func perform(action: String, text: String?, info: [AnyHashable: Any]) {
        guard let name = info["name"] as? String, let tmux = info["tmux"] as? String else { return }
        let expected = info["dialog"] as? String
        Task {
            let err = await Task.detached { () -> String? in
                if action == "reply" { return SessionAnswer.reply(text ?? "", tmux: tmux) }
                guard let dialog = SessionAnswer.dialog(tmux) else { return "The prompt is no longer on the screen." }
                guard Self.fingerprint(dialog) == expected else { return "The prompt changed since the notification." }
                let choice: ScreenDialog.PermissionChoice = action == "deny" ? .deny : action == "always" ? .alwaysAllow : .allow
                return SessionAnswer.choose(.permission(choice), expected: dialog, tmux: tmux)
            }.value
            if let err {
                NSApp.activate(ignoringOtherApps: true)
                open?(name, .info)
                notice?("Couldn't answer \(name): \(err)")
            }
        }
    }

    /// System Settings → Notifications, for when the user said no at first.
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Dock badge

    private func showBadge(_ needsYou: Int) {
        let label: String? = AppSettings.shared.dockBadge && needsYou > 0 ? String(needsYou) : nil
        guard label != badge else { return }
        badge = label
        NSApp.dockTile.badgeLabel = label
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Banners also while Switchboard is in front (the selected session is filtered out before).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// A click brings Switchboard forward and shows the session.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let name = info["name"] as? String
        let tab = (info["tab"] as? String).flatMap(DetailTab.init(rawValue:)) ?? .terminal
        let action = response.actionIdentifier
        if ["allow", "always", "deny", "reply"].contains(action) {
            // an answer button: no window, just send it
            let text = (response as? UNTextInputNotificationResponse)?.userText
            nonisolated(unsafe) let sendable = info
            Task { @MainActor in
                Notifier.shared.perform(action: action, text: text, info: sendable)
                completionHandler()
            }
            return
        }
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            if let name { Notifier.shared.open?(name, tab) }
            completionHandler()
        }
    }
}

/// Settings → Notifications: one switch per kind, sound, Dock badge, and a hint when macOS denied them.
struct NotificationSettings: View {
    @Bindable private var settings = AppSettings.shared
    private var notifier: Notifier { .shared }

    private var anyOn: Bool {
        settings.notifyNeedsYou || settings.notifyFinished || settings.notifyUsageLimit
            || settings.notifySubagentFinished || settings.notifyEnded
    }

    var body: some View {
        Section {
            Toggle("A session needs you (permission, question)", isOn: $settings.notifyNeedsYou)
            Toggle("A session finished working", isOn: $settings.notifyFinished)
            Toggle("A session hit a usage limit, or was continued after one", isOn: $settings.notifyUsageLimit)
            Toggle("A subagent finished", isOn: $settings.notifySubagentFinished)
            Toggle("A session ended", isOn: $settings.notifyEnded)
            Divider()
            Toggle("Play a sound", isOn: $settings.notifySound).disabled(!anyOn)
            Toggle("Only while Switchboard is in the background", isOn: $settings.notifyOnlyInBackground).disabled(!anyOn)
            Toggle("Show the number of sessions that need you on the Dock icon", isOn: $settings.dockBadge)
            if notifier.denied {
                LabeledContent {
                    Button("Open System Settings…") { Notifier.openSystemSettings() }
                } label: {
                    Text("Notifications are off for Switchboard in macOS").foregroundStyle(Palette.need)
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text(notifier.hasCenter
                 ? "Only on changes: nothing fires at launch, and not for the session you are looking at while Switchboard is in front. Click a notification to go to the session."
                 : "Started without an app bundle (swift run), so Switchboard can only bounce the Dock icon. Build Switchboard.app for banners.")
        }
        .onAppear { notifier.refreshAuthorization() }
        .onChange(of: anyOn) { _, on in if on { Task { await notifier.authorize() } } }
    }
}
