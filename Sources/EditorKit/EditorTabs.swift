import Foundation

/// Open editors of one session, with VS Code's preview rules (`workbench.editor.enablePreview`):
/// - a single click opens a *preview* tab; the next preview replaces it in the same place
/// - a double click, Enter, or the first edit *pins* it, so it stays
/// - a dirty tab is always pinned
public struct EditorTabs: Equatable, Sendable {
    public private(set) var paths: [String] = []
    /// the one tab that the next preview replaces (shown in italics)
    public private(set) var preview: String?
    public var active: String?

    public init() {}

    /// Opens `path`: activates it if open (pinning it when asked), otherwise replaces the preview tab or
    /// appends after the active tab.
    public mutating func open(_ path: String, pinned: Bool) {
        if paths.contains(path) {
            if pinned, preview == path { preview = nil }
            active = path
            return
        }
        if !pinned, let p = preview, let i = paths.firstIndex(of: p) {
            paths[i] = path
        } else {
            let at = active.flatMap { paths.firstIndex(of: $0) }.map { $0 + 1 } ?? paths.count
            paths.insert(path, at: at)
        }
        preview = pinned ? nil : path
        active = path
    }

    /// Keeps the tab (double click on it, or an edit).
    public mutating func pin(_ path: String) {
        if preview == path { preview = nil }
    }

    /// Closes the tab; the neighbor to the right (else left) becomes active, like closing in an editor.
    public mutating func close(_ path: String) {
        guard let i = paths.firstIndex(of: path) else { return }
        paths.remove(at: i)
        if preview == path { preview = nil }
        if active == path { active = paths.isEmpty ? nil : paths[min(i, paths.count - 1)] }
    }

    /// The file was renamed or moved on disk.
    public mutating func rename(_ old: String, to new: String) {
        guard let i = paths.firstIndex(of: old) else { return }
        paths[i] = new
        if preview == old { preview = new }
        if active == old { active = new }
    }
}
