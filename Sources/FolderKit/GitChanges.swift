import Foundation

/// The repository's changes as VS Code's Source Control view lists them: staged (index) and unstaged (working
/// tree) per file, plus merge conflicts. Also the git calls behind its buttons.
public struct GitChanges: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        /// absolute path
        public let path: String
        /// path relative to the repository, as git prints it
        public let rel: String
        /// the old path of a rename
        public let oldRel: String?
        /// porcelain status letters: X (index) and Y (working tree)
        public let index: Character
        public let worktree: Character

        public var id: String { path }
        public var name: String { (rel as NSString).lastPathComponent }
        /// folder part of `rel`, "" at the top
        public var folder: String { (rel as NSString).deletingLastPathComponent }

        public var isConflict: Bool {
            index == "U" || worktree == "U" || (index == "A" && worktree == "A") || (index == "D" && worktree == "D")
        }

        /// the change in the index ("Staged Changes"), nil when nothing is staged
        public var staged: GitStatus.Change? {
            guard !isConflict, index != " ", index != "?" else { return nil }
            return Self.change(index)
        }

        /// the change in the working tree ("Changes"), nil when the working tree matches the index
        public var unstaged: GitStatus.Change? {
            guard !isConflict, worktree != " " else { return nil }
            return worktree == "?" ? .untracked : Self.change(worktree)
        }

        static func change(_ c: Character) -> GitStatus.Change {
            switch c {
            case "A": .added
            case "D": .deleted
            case "R", "C": .renamed
            case "U": .conflicted
            case "?": .untracked
            default: .modified
            }
        }
    }

    public let repoRoot: String?
    public let branch: String?
    public let entries: [Entry]

    public static let empty = GitChanges(repoRoot: nil, branch: nil, entries: [])

    public init(repoRoot: String?, branch: String?, entries: [Entry]) {
        self.repoRoot = repoRoot
        self.branch = branch
        self.entries = entries
    }

    public var conflicts: [Entry] { entries.filter(\.isConflict) }
    public var staged: [Entry] { entries.filter { $0.staged != nil } }
    public var unstaged: [Entry] { entries.filter { $0.unstaged != nil } }
    /// what the Source Control badge counts: every file with a change, once
    public var count: Int { entries.count }

    /// Parses `git status --porcelain=v1 -z --branch` run in `repoRoot`, sorted by path like VS Code's list.
    public static func parse(_ output: String, repoRoot: String) -> GitChanges {
        var entries: [Entry] = []
        var branch: String?
        var parts = output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let item = parts.popFirst() {
            if item.hasPrefix("## ") {
                let b = item.dropFirst(3)
                let name = b.components(separatedBy: "...").first ?? String(b)
                branch = name.hasPrefix("No commits yet on ") ? String(name.dropFirst("No commits yet on ".count)) : name
                continue
            }
            guard item.count > 3 else { continue }
            let x = item[item.startIndex], y = item[item.index(after: item.startIndex)]
            let rel = String(item.dropFirst(3))
            // a rename or copy carries its old path as the next field
            let old = (x == "R" || x == "C") ? parts.popFirst() : nil
            guard !rel.hasSuffix("/") else { continue }   // untracked folders: listed file by file with -uall
            entries.append(Entry(path: repoRoot + "/" + rel, rel: rel, oldRel: old, index: x, worktree: y))
        }
        entries.sort { $0.rel.localizedStandardCompare($1.rel) == .orderedAscending }
        return GitChanges(repoRoot: repoRoot, branch: branch, entries: entries)
    }

    /// The changes of the repository `folder` is in; `.empty` outside a repository.
    public static func load(folder: String) -> GitChanges {
        guard let top = toplevel(folder),
              let out = GitStatus.git(["-C", top, "status", "--porcelain=v1", "-z", "--branch", "--untracked-files=all"])
        else { return .empty }
        return parse(out, repoRoot: top)
    }

    public static func toplevel(_ folder: String) -> String? {
        guard let top = GitStatus.git(["-C", folder, "rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty else { return nil }
        return FolderListing.realPath(top)
    }

    // MARK: Contents

    /// A file as stored in git: `HEAD` (last commit) or the index (`staged`). Nil when it isn't there.
    public static func contents(_ rel: String, repo: String, fromIndex: Bool) -> Data? {
        let r = run(["show", (fromIndex ? ":" : "HEAD:") + rel], in: repo)
        return r.status == 0 ? r.out : nil
    }

    // MARK: Actions (each returns git's error message, nil on success)

    /// "+": stage the files (also deletions and new files).
    public static func stage(_ rels: [String], repo: String) -> String? {
        guard !rels.isEmpty else { return nil }
        return error(run(["add", "-A", "--"] + rels, in: repo))
    }

    /// "−": take the files out of the index again, keeping the working tree.
    public static func unstage(_ rels: [String], repo: String) -> String? {
        guard !rels.isEmpty else { return nil }
        // before the first commit there is no HEAD to restore from
        let hasHead = run(["rev-parse", "--verify", "-q", "HEAD"], in: repo).status == 0
        return error(run(hasHead ? ["restore", "--staged", "--"] + rels : ["rm", "--cached", "-q", "-r", "--"] + rels, in: repo))
    }

    /// "Discard Changes": the working tree goes back to the index. New (untracked) files go to the Trash.
    public static func discard(_ entries: [Entry], repo: String) -> String? {
        let untracked = entries.filter { $0.worktree == "?" }
        let tracked = entries.filter { $0.worktree != "?" }.map(\.rel)
        for e in untracked {
            do { try FileManager.default.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil) }
            catch { return "Couldn't move \(e.name) to the Trash: \(error.localizedDescription)" }
        }
        guard !tracked.isEmpty else { return nil }
        return error(run(["restore", "--"] + tracked, in: repo))
    }

    public static func commit(message: String, repo: String) -> String? {
        let m = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !m.isEmpty else { return "Enter a commit message." }
        return error(run(["commit", "-q", "-m", m], in: repo))
    }

    // MARK: git

    struct Result {
        let status: Int32
        let out: Data
        let err: String
    }

    static func run(_ args: [String], in repo: String) -> Result {
        guard let gitPath = GitStatus.gitPath else { return Result(status: -1, out: Data(), err: "git not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = ["-C", repo] + args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return Result(status: -1, out: Data(), err: error.localizedDescription) }
        // read both pipes while git runs, so a large output can't block it
        var errData = Data()
        let reader = Thread { errData = err.fileHandleForReading.readDataToEndOfFile() }
        reader.start()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        while !reader.isFinished { usleep(1000) }
        return Result(status: p.terminationStatus, out: data, err: String(decoding: errData, as: UTF8.self))
    }

    private static func error(_ r: Result) -> String? {
        guard r.status != 0 else { return nil }
        let msg = r.err.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "git failed (\(r.status))" : msg
    }
}
