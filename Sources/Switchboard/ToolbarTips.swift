import AppKit
import SwiftUI

/// Tooltips for the window's toolbar buttons. SwiftUI's `.help` doesn't reach toolbar items on macOS, so they are
/// set on the AppKit items by their label, also on items added later (the folder buttons change with the mode).
enum ToolbarTips {
    static let tips: [String: String] = [
        "Group By": "Group sessions by parent folder or status",
        "New Session": "New Session (⌘N)",
        "Hide Sidebar": "Show or hide the sessions column",
        "Hidden Files": "Show or hide hidden files (names starting with a dot)",
        "Collapse All": "Collapse all folders",
        "Refresh Explorer": "Reload the folder tree and its git status",
        "Refresh Changes": "Reload the changed files",
        "Stage All Changes": "Stage all changes (+)",
    ]

    static func apply(to item: NSToolbarItem) {
        guard let tip = tips[item.label], item.toolTip != tip else { return }
        item.toolTip = tip
        item.view?.toolTip = tip
    }

    static func apply(to window: NSWindow?) {
        window?.toolbar?.items.forEach(apply)
    }
}

/// Put in the window's content once: applies the tooltips now and whenever the toolbar gains an item.
struct ToolbarTipsInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { ToolbarTips.apply(to: view.window) }
    }

    final class Probe: NSView {
        private var observer: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            ToolbarTips.apply(to: window)
            observer = NotificationCenter.default.addObserver(forName: NSToolbar.willAddItemNotification, object: nil,
                                                              queue: .main) { [weak window] note in
                guard let window, let toolbar = note.object as? NSToolbar, toolbar === window.toolbar else { return }
                // the item is about to be added; its label and view are set right after
                DispatchQueue.main.async { ToolbarTips.apply(to: window) }
            }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
