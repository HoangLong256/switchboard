import Foundation

/// Keeps the selected row through the changes a terminal goes through: Claude exits to the shell (`/exit`), is
/// started again there, was renamed (`/rename`), or the tmux session ends.
public enum SessionSelection {
    /// A row as the selection sees it: its name (the selection) and its tmux session (the terminal shown).
    public struct Item: Equatable, Sendable {
        public let name: String
        public let tmux: String?
        public init(name: String, tmux: String?) {
            self.name = name
            self.tmux = tmux
        }
    }

    /// Identity of the rows in the sessions list. A row in Switchboard's tmux goes by its tmux session: after `/exit`
    /// the registry entry (with the pid in the session's id) is gone and the terminal shows a shell, but it is the same
    /// row, and the list must not drop it and its selection. Otherwise the session's id. When two sessions share a
    /// tmux session (a `claude` started from inside a session), only the first goes by it.
    public static func rowIDs(_ ids: [(id: String, tmux: String?)]) -> [String] {
        var seen = Set<String>()
        return ids.map { r in
            guard let t = r.tmux, seen.insert(t).inserted else { return r.id }
            return "tmux:\(t)"
        }
    }

    /// The selection after the rows changed from `before` to `after`. The row keeps its selection while it has the
    /// same name and terminal. Else the terminal wins: the row with the old row's tmux session (the shell after
    /// `/exit` under the tmux name, Claude registered again under its own name). Else the name (the session is
    /// known offline from its handover). If all of it is gone (`exit` in the shell, "Close"), the nearest row in
    /// the old order (the one after, else the one before) that still exists; nil only when nothing is left.
    /// An unknown selection (not in `before`) is left alone.
    public static func follow(_ selected: String?, before: [Item], after: [Item]) -> String? {
        guard let selected, let i = before.firstIndex(where: { $0.name == selected }) else { return selected }
        let old = before[i]
        if after.contains(where: { $0.name == old.name && $0.tmux == old.tmux }) { return old.name }
        if let t = old.tmux, let r = after.first(where: { $0.tmux == t }) { return r.name }
        if after.contains(where: { $0.name == old.name }) { return old.name }
        let names = Set(after.map(\.name))
        let neighbors = before[(i + 1)...].map(\.name) + before[..<i].reversed().map(\.name)
        return neighbors.first { names.contains($0) }
    }
}
