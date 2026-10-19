import Foundation

/// Changed files of the git repository a folder belongs to, so the sidebar shows what a session touched.
public struct GitStatus: Equatable, Sendable {
    public enum Change: String, Equatable, Sendable {
        case modified, added, deleted, untracked, renamed, conflicted

        /// letter shown next to the name, like in editors
        public var letter: String {
            switch self {
            case .modified: "M"
            case .added: "A"
            case .deleted: "D"
            case .untracked: "U"
            case .renamed: "R"
            case .conflicted: "!"
            }
        }
    }

    /// absolute path → change
    public let files: [String: Change]
    /// absolute folder paths that contain at least one change
    public let dirtyFolders: Set<String>
    public let branch: String?

    public static let empty = GitStatus(files: [:], dirtyFolders: [], branch: nil)

    public init(files: [String: Change], dirtyFolders: Set<String>, branch: String?) {
        self.files = files
        self.dirtyFolders = dirtyFolders
        self.branch = branch
    }

    /// Parses `git status --porcelain=v1 -z --branch` run in `repoRoot`.
    public static func parse(_ output: String, repoRoot: String) -> GitStatus {
        var files: [String: Change] = [:]
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
            // a rename carries the old path as the next field
            if x == "R" || x == "C" { _ = parts.popFirst() }
            let change: Change
            switch (x, y) {
            case ("?", "?"): change = .untracked
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"): change = .conflicted
            case ("R", _), ("C", _): change = .renamed
            case ("A", _): change = .added
            case ("D", _), (_, "D"): change = .deleted
            default: change = .modified
            }
            let trimmed = rel.hasSuffix("/") ? String(rel.dropLast()) : rel
            files[repoRoot + "/" + trimmed] = change
        }
        var dirty = Set<String>()
        for path in files.keys {
            var dir = (path as NSString).deletingLastPathComponent
            while dir.count >= repoRoot.count, dirty.insert(dir).inserted {
                dir = (dir as NSString).deletingLastPathComponent
            }
        }
        return GitStatus(files: files, dirtyFolders: dirty, branch: branch)
    }

    /// Change for a path: its own, or the one of an untracked folder above it (git reports those as a whole).
    public func change(for path: String) -> Change? {
        if let c = files[path] { return c }
        var dir = (path as NSString).deletingLastPathComponent
        while dir.count > 1 {
            if files[dir] == .untracked { return .untracked }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// Runs git for `folder`; `.empty` when it isn't in a repository or git is missing.
    public static func load(folder: String) -> GitStatus {
        guard let top = git(["-C", folder, "rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !top.isEmpty,
            let out = git(["-C", top, "status", "--porcelain=v1", "-z", "--branch", "--untracked-files=normal"])
        else { return .empty }
        // git prints the real path; the sidebar's root is a real path too (FolderListing.realPath)
        return parse(out, repoRoot: FolderListing.realPath(top))
    }

    static let gitPath = ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    static func git(_ args: [String]) -> String? {
        guard let gitPath else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gitPath)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
