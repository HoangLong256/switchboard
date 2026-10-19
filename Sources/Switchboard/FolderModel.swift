import FolderKit
import Foundation
import Observation
import SessionCore

/// State of the folder sidebar for one root: loaded folders, open folders, git status. Changes on disk
/// (a session writing files) reload the open folders and the git status.
@MainActor
@Observable
final class FolderModel {
    private(set) var root: String? { didSet { cachedRows = nil } }
    private(set) var children: [String: [FolderEntry]] = [:] { didSet { cachedRows = nil } }
    private(set) var git = GitStatus.empty
    /// staged and unstaged files for the Source Control view (only loaded while it shows)
    private(set) var changes = GitChanges.empty
    var wantsChanges = false { didSet { if wantsChanges && !oldValue { loadChanges() } } }
    /// the last git action failed: its message
    var gitError: String?
    /// linked worktrees of the root's repository (empty with only one)
    private(set) var worktrees: [Worktree] = []
    var expanded: Set<String> = [] { didSet { cachedRows = nil; saveExpanded() } }
    var filter = "" { didSet { cachedRows = nil; if !filter.isEmpty { loadForFilter() } } }
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden") {
        didSet { UserDefaults.standard.set(showHidden, forKey: "showHidden"); reloadAll() }
    }

    @ObservationIgnored private var watcher: Watcher?
    @ObservationIgnored private var generation = 0
    /// the tree as rows, built once per change instead of on every redraw of the sidebar (not observed: `rows`
    /// fills it while a view reads it)
    @ObservationIgnored private var cachedRows: [FolderTree.Row]?
    /// a reload with git status is running; another request waits for it instead of starting a second one
    @ObservationIgnored private var loadingGit = false
    @ObservationIgnored private var reloadAgain = false
    @ObservationIgnored private var loadingChanges = false

    var rows: [FolderTree.Row] {
        if let cachedRows { return cachedRows }
        guard let root else { return [] }
        let r = FolderTree.rows(root: root, children: children, expanded: expanded, filter: filter)
        cachedRows = r
        return r
    }

    /// Changes inside `.git/` that don't change what the sidebar shows: `git status` itself rewrites the index,
    /// which would otherwise trigger the next reload. HEAD and refs still count (commits, branch switches).
    nonisolated static func ignored(_ path: String) -> Bool {
        guard let r = path.range(of: "/.git/") else { return false }
        let inside = path[r.upperBound...]
        return !(inside == "HEAD" || inside.hasPrefix("refs/"))
    }

    /// Shows `folder` (nil clears the sidebar). Open folders are remembered per root.
    func show(_ folder: String?) {
        let real = folder.map(FolderListing.realPath)
        guard real != root else { return }
        root = real
        children = [:]
        git = .empty
        changes = .empty
        worktrees = []
        filter = ""
        watcher = nil
        generation += 1
        guard let real else { return }
        expanded = Set(UserDefaults.standard.stringArray(forKey: Self.expandedKey(real)) ?? [])
        reloadAll()
        watcher = Watcher(paths: [real], delay: 0.6, ignore: Self.ignored) { [weak self] in
            Task { @MainActor in self?.reloadAll() }
        }
    }

    func toggle(_ entry: FolderEntry) {
        guard entry.isDir else { return }
        if expanded.contains(entry.path) {
            expanded.remove(entry.path)
        } else {
            expanded.insert(entry.path)
            if children[entry.path] == nil { load([entry.path]) }
        }
    }

    func collapseAll() { expanded = [] }

    /// Opens every folder on the way to `path` (e.g. "Reveal in sidebar").
    func reveal(_ path: String) {
        guard let root, path.hasPrefix(root + "/") else { return }
        var dir = (path as NSString).deletingLastPathComponent
        var add: [String] = []
        while dir.count > root.count { add.append(dir); dir = (dir as NSString).deletingLastPathComponent }
        expanded.formUnion(add)
        load(add.filter { children[$0] == nil })
    }

    /// Reloads the root, every open folder, and git status.
    func reloadAll() {
        guard let root else { return }
        // a big repository's git status can outlast the next file event: run one at a time, then once more
        guard !loadingGit else { reloadAgain = true; return }
        load([root] + expanded.filter { $0.hasPrefix(root + "/") }, withGit: true)
        if wantsChanges { loadChanges() }
    }

    func loadChanges() {
        guard let root, !loadingChanges else { return }
        let gen = generation
        loadingChanges = true
        Task {
            let c = await Task.detached { GitChanges.load(folder: root) }.value
            loadingChanges = false
            guard gen == generation else { return }
            if c != changes { changes = c }
        }
    }

    // MARK: Source Control actions

    func stage(_ entries: [GitChanges.Entry]) { act { GitChanges.stage(entries.map(\.rel), repo: $0) } }
    func unstage(_ entries: [GitChanges.Entry]) { act { GitChanges.unstage(entries.map(\.rel), repo: $0) } }
    func discard(_ entries: [GitChanges.Entry]) { act { GitChanges.discard(entries, repo: $0) } }

    /// Commits what is staged; true when it worked (the message field is cleared then).
    func commit(_ message: String) async -> Bool {
        guard let repo = changes.repoRoot else { return false }
        let err = await Task.detached { GitChanges.commit(message: message, repo: repo) }.value
        gitError = err
        reloadAll()
        return err == nil
    }

    /// Runs a git action off the main thread, then shows its error (if any) and the new state.
    private func act(_ action: @escaping @Sendable (String) -> String?) {
        guard let repo = changes.repoRoot else { return }
        Task {
            let err = await Task.detached { action(repo) }.value
            if let err { gitError = err }
            reloadAll()
        }
    }

    private func load(_ dirs: [String], withGit: Bool = false) {
        guard let root, !dirs.isEmpty || withGit else { return }
        let gen = generation, hidden = showHidden
        if withGit { loadingGit = true }
        Task {
            defer {
                if withGit {
                    loadingGit = false
                    if reloadAgain { reloadAgain = false; reloadAll() }
                }
            }
            let (lists, status, trees) = await Task.detached {
                (dirs.map { ($0, FolderListing.list($0, showHidden: hidden)) },
                 withGit ? GitStatus.load(folder: root) : nil,
                 withGit ? Worktree.load(folder: root) : nil)
            }.value
            guard gen == generation else { return }   // another session was selected meanwhile
            var c = children
            for (dir, list) in lists { c[dir] = list }
            if c != children { children = c }
            if let status, status != git { git = status }
            if let trees, trees != worktrees { worktrees = trees }
        }
    }

    /// With a filter, search a few levels deep (skipping big generated folders) so matches show up
    /// without opening folders by hand.
    private func loadForFilter() {
        guard let root else { return }
        let gen = generation, hidden = showHidden, known = children
        Task {
            let found = await Task.detached { Self.crawl(root, known: known, showHidden: hidden, depth: 4, budget: 3000) }.value
            guard gen == generation else { return }
            var c = children
            for (k, v) in found where c[k] == nil { c[k] = v }
            if c != children { children = c }
        }
    }

    nonisolated static func crawl(_ root: String, known: [String: [FolderEntry]], showHidden: Bool,
                                  depth: Int, budget: Int) -> [String: [FolderEntry]] {
        var out = known
        var queue: [(String, Int)] = [(root, 0)]
        var left = budget
        while !queue.isEmpty, left > 0 {
            let (dir, d) = queue.removeFirst()
            let list = out[dir] ?? FolderListing.list(dir, showHidden: showHidden)
            out[dir] = list
            left -= list.count
            guard d < depth else { continue }
            for e in list where e.isDir && !FolderListing.heavy.contains(e.name) { queue.append((e.path, d + 1)) }
        }
        return out
    }

    private static func expandedKey(_ root: String) -> String { "expanded:\(root)" }

    private func saveExpanded() {
        guard let root else { return }
        UserDefaults.standard.set(Array(expanded), forKey: Self.expandedKey(root))
    }
}
