import SessionCore
import SwiftUI

/// Answering a session that needs you without going to its terminal: pick an option of the dialog on its screen
/// (Allow, Deny, a question's choices) or type a reply. The screen is read again right before a key is sent, and
/// nothing is sent when the dialog changed in between, so a late click can't answer the next prompt.
enum SessionAnswer {
    /// The dialog on the session's screen, nil when none is shown (or tmux can't reach it).
    static func dialog(_ tmux: String) -> ScreenDialog? {
        Tmux.capture(tmux).flatMap(ScreenDialog.parse)
    }

    /// What the screen shows: a numbered dialog to answer with buttons, or another open prompt (no numbers, like the
    /// folder trust prompt) that only the terminal can answer.
    static func look(_ tmux: String) -> (dialog: ScreenDialog?, otherPrompt: Bool) {
        guard let screen = Tmux.capture(tmux) else { return (nil, false) }
        let d = ScreenDialog.parse(screen)
        return (d, d == nil && ScreenDialog.hasOpenPrompt(screen))
    }

    /// Picks the answer in the dialog on screen. `expected`: the dialog the user saw; the answer is only sent when
    /// the screen still shows the same one. Returns an error message, nil when the key was sent.
    static func choose(_ answer: ScreenDialog.Answer, expected: ScreenDialog?, tmux: String) -> String? {
        guard let dialog = dialog(tmux) else { return "The prompt is no longer on the screen." }
        if let expected, !dialog.sameDialog(as: expected) { return "The prompt changed. Look at it again." }
        guard let option = dialog.pick(answer) else { return "That choice isn't on the screen." }
        // Claude Code takes the option's number as a shortcut; two digits would be read as two choices
        guard option.number <= 9 else { return "Pick this option in the terminal." }
        return Tmux.key(String(option.number), into: tmux)
    }

    /// Types the reply and presses Enter, only when no dialog is on screen (a digit in the text would pick an option).
    static func reply(_ text: String, tmux: String) -> String? {
        guard let t = SessionControl.replyText(text) else { return "The reply is empty." }
        let now = look(tmux)
        if now.dialog != nil { return "A prompt with choices is on the screen. Pick one of them first." }
        if now.otherPrompt { return "A prompt is open in the terminal. Answer it there." }
        return Tmux.type(t, into: tmux)
    }
}

/// Info tab: the choices of the dialog on the session's screen as buttons, and a reply field for questions.
/// Reads the screen every 1.5 seconds while the session needs you.
struct AnswerPanel: View {
    @Environment(Store.self) private var store
    let row: Row
    @State private var dialog: ScreenDialog?
    /// a prompt without numbers (folder trust): typing would confirm it, so only the terminal can answer
    @State private var otherPrompt = false
    @State private var reply = ""
    @State private var result: (text: String, failed: Bool)?
    @State private var sending = false
    @FocusState private var replyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dialog {
                Text("Answer").font(.caption).foregroundStyle(.secondary)
                FlowButtons(options: dialog.options, disabled: sending) { choose($0, in: dialog) }
            }
            if otherPrompt {
                Label("A prompt is open in the terminal. Answer it there.", systemImage: "terminal")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    TextField("Reply", text: $reply,
                              prompt: Text(dialog == nil ? "Reply to Claude…" : "Pick a choice above, or type in the terminal"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .focused($replyFocused)
                        .disabled(dialog != nil || sending)
                        .onSubmit(send)
                    Button("Send", action: send)
                        .disabled(dialog != nil || sending || SessionControl.replyText(reply) == nil)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
            if let result {
                Label(result.text, systemImage: result.failed ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(result.failed ? Palette.need : .secondary)
            }
        }
        .task(id: row.tmux) {
            // poll while shown; the task ends when the view goes away or the session changes
            while !Task.isCancelled {
                await look()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private func look() async {
        guard let tmux = row.tmux else { return }
        let now = await Task.detached { SessionAnswer.look(tmux) }.value
        if now.dialog != dialog { dialog = now.dialog }
        if now.otherPrompt != otherPrompt { otherPrompt = now.otherPrompt }
    }

    private func choose(_ option: ScreenDialog.Option, in shown: ScreenDialog) {
        guard let tmux = row.tmux else { return }
        sending = true
        Task {
            let err = await Task.detached { SessionAnswer.choose(.option(option.label), expected: shown, tmux: tmux) }.value
            result = err.map { ($0, true) } ?? ("Sent “\(option.number). \(option.label)”", false)
            sending = false
            await look()
        }
    }

    private func send() {
        guard let tmux = row.tmux, let text = SessionControl.replyText(reply), dialog == nil, !otherPrompt else { return }
        sending = true
        Task {
            let err = await Task.detached { SessionAnswer.reply(text, tmux: tmux) }.value
            if err == nil { reply = "" }
            result = err.map { ($0, true) } ?? ("Sent your reply", false)
            sending = false
        }
    }
}

/// The dialog's options as buttons that wrap to the next line: "Yes" prominent, "No" in red.
private struct FlowButtons: View {
    let options: [ScreenDialog.Option]
    let disabled: Bool
    let action: (ScreenDialog.Option) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options, id: \.number) { o in
                Button { action(o) } label: {
                    HStack(spacing: 6) {
                        Text("\(o.number)").font(.caption.monospacedDigit().weight(.semibold))
                            .frame(width: 16, height: 16)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                        Text(o.label).lineLimit(2).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .tint(tint(o))
                .disabled(disabled)
                .help("Press \(o.number) in the session")
            }
        }
    }

    private func tint(_ o: ScreenDialog.Option) -> Color? {
        let t = o.label.lowercased()
        if t.hasPrefix("yes") { return Palette.busy }
        if t.hasPrefix("no") { return Palette.need }
        return nil
    }
}
