import AppKit
import SwiftTerm
import SwiftUI

/// SwiftTerm terminal attached to the session with `tmux attach`.
/// Closing the view only ends the attach process; the tmux session keeps running.
struct TmuxTerminal: NSViewRepresentable {
    let name: String
    let focusRequest: Int
    @Environment(\.colorScheme) private var scheme

    final class Coordinator { var focusSeen = 0 }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func applyColors(_ view: SessionTerminalView) {
        let dark = scheme == .dark
        view.nativeBackgroundColor = NSColor(white: dark ? 0.08 : 1, alpha: 1)
        view.nativeForegroundColor = NSColor(white: dark ? 0.96 : 0.04, alpha: 1)
        view.caretColor = view.nativeForegroundColor
        view.selectedTextBackgroundColor = .selectedTextBackgroundColor
    }

    func makeNSView(context: Context) -> SessionTerminalView {
        let view = SessionTerminalView(frame: .zero)
        view.font = NSFont(name: "MesloLGS-NF-Regular", size: 13) ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.optionAsMetaKey = false
        view.getTerminal().setCursorStyle(.steadyBar)
        applyColors(view)
        hideScroller(view)
        view.startProcess(executable: Tmux.path!, args: Tmux.attachArgs(name),
                          environment: Tmux.environmentList(), execName: "tmux")
        context.coordinator.focusSeen = focusRequest
        view.wantsFocus = true
        return view
    }

    func updateNSView(_ view: SessionTerminalView, context: Context) {
        applyColors(view)
        hideScroller(view)
        if context.coordinator.focusSeen != focusRequest {
            context.coordinator.focusSeen = focusRequest
            view.wantsFocus = true
        }
        view.takeFocusIfWanted()
    }

    /// tmux keeps the history, so SwiftTerm's own scroller stays empty
    private func hideScroller(_ view: SessionTerminalView) {
        view.subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    static func dismantleNSView(_ view: SessionTerminalView, coordinator: Coordinator) { view.terminate() }
}

final class SessionTerminalView: LocalProcessTerminalView {
    var wantsFocus = false
    private var keyMonitor: Any?

    func takeFocusIfWanted() {
        guard wantsFocus, let window else { return }
        wantsFocus = false
        window.makeFirstResponder(self)
    }

    /// Shift/Option+Return = new line in Claude Code (ESC CR), Option+←/→ word jump, Option+Delete delete word.
    private func watchMetaKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard window != nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window, self.window?.firstResponder === self else { return e }
            let mods = e.modifierFlags.intersection([.shift, .control, .option, .command])
            let seq: String? = switch (e.keyCode, mods) {
            case (36, .shift), (76, .shift), (36, .option), (76, .option): "\u{1B}\r"
            case (123, .option): "\u{1B}b"
            case (124, .option): "\u{1B}f"
            case (51, .option): "\u{1B}\u{7F}"
            default: nil
            }
            guard let seq else { return e }
            self.send(txt: seq)
            return nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watchMetaKeys()
        registerForDraggedTypes([.fileURL])
        takeFocusIfWanted()
    }

    override func removeFromSuperview() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        super.removeFromSuperview()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    /// Files dropped in (also from the folder sidebar) get their path typed, like in iTerm.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                         options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        send(txt: urls.map { Self.shellEscaped($0.path) }.joined(separator: " ") + " ")
        window?.makeFirstResponder(self)
        return true
    }

    static func shellEscaped(_ path: String) -> String {
        let special = Set(" \\'\"()[]{}&;|<>*?$`!#~")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }
}
