import Foundation

/// Linked git worktrees of a repository. Claude Code runs sessions and subagents in their own worktree
/// (`claude --worktree`), so the sidebar offers to switch between them.
public struct Worktree: Equatable, Hashable, Sendable, Identifiable {
    public let path: String
    /// short branch name, nil when detached
    public let branch: String?
    public let isMain: Bool
    public var id: String { path }

    public var name: String { (path as NSString).lastPathComponent }

    public init(path: String, branch: String?, isMain: Bool) {
        self.path = path
        self.branch = branch
        self.isMain = isMain
    }

    /// Parses `git worktree list --porcelain`: blocks separated by blank lines, the first one is the main worktree.
    /// Bare and prunable entries are left out (nothing to browse).
    public static func parse(_ output: String) -> [Worktree] {
        var result: [Worktree] = []
        for (i, block) in output.components(separatedBy: "\n\n").enumerated() {
            var path: String?, branch: String?, skip = false
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst("worktree ".count)) }
                else if line.hasPrefix("branch ") {
                    let ref = line.dropFirst("branch ".count)
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : String(ref)
                } else if line == "bare" || line.hasPrefix("prunable") { skip = true }
            }
            guard let path, !skip else { continue }
            result.append(Worktree(path: path, branch: branch, isMain: i == 0))
        }
        return result
    }

    /// Worktrees of the repository `folder` belongs to; empty outside a repository or with just one worktree.
    public static func load(folder: String) -> [Worktree] {
        guard let out = GitStatus.git(["-C", folder, "worktree", "list", "--porcelain"]) else { return [] }
        let all = parse(out)
        return all.count > 1 ? all : []
    }
}
