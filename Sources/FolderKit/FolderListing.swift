import Foundation

/// One file or folder in the sidebar.
public struct FolderEntry: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    /// absolute path
    public let path: String
    public let isDir: Bool
    public let size: Int64?
    public let modifiedAt: Date?

    public var id: String { path }

    public init(name: String, path: String, isDir: Bool, size: Int64? = nil, modifiedAt: Date? = nil) {
        self.name = name
        self.path = path
        self.isDir = isDir
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

public enum FolderListing {
    /// Never shown: noise that is never what you're looking for.
    public static let alwaysHidden: Set<String> = [".git", ".DS_Store"]
    /// Folders shown but never expanded on their own (big, generated)
    public static let heavy: Set<String> = ["node_modules", ".build", "build", "DerivedData", "Pods", ".venv", "dist", "target"]
    public static let limit = 5000

    /// Path with all symlinks resolved (`/tmp` → `/private/tmp`), like git prints it. Unchanged if it doesn't exist.
    public static func realPath(_ path: String) -> String {
        guard let r = realpath(path, nil) else { return path }
        defer { free(r) }
        return String(cString: r)
    }

    /// Folders first, then files, each by name (case-insensitive, numbers in order, like Finder).
    /// `showHidden`: dot files too (except `alwaysHidden`). Symlinks to folders count as folders.
    public static func list(_ dir: String, showHidden: Bool) -> [FolderEntry] {
        let url = URL(fileURLWithPath: dir)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys) else {
            return []
        }
        var entries: [FolderEntry] = urls.compactMap { u in
            let name = u.lastPathComponent
            if alwaysHidden.contains(name) || (!showHidden && name.hasPrefix(".")) { return nil }
            let v = try? u.resourceValues(forKeys: Set(keys))
            var folder = v?.isDirectory ?? false
            if v?.isSymbolicLink == true {
                folder = (try? u.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            }
            return FolderEntry(name: name, path: u.path, isDir: folder,
                               size: folder ? nil : v?.fileSize.map(Int64.init), modifiedAt: v?.contentModificationDate)
        }
        sort(&entries)
        return Array(entries.prefix(limit))
    }

    public static func sort(_ entries: inout [FolderEntry]) {
        entries.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// The tree as the list shows it: every entry of the root, and below each expanded folder its entries,
/// indented by depth. Folders that were never loaded show nothing below them yet.
public enum FolderTree {
    public struct Row: Equatable, Identifiable, Sendable {
        public let entry: FolderEntry
        public let depth: Int
        public let expanded: Bool
        public var id: String { entry.path }
    }

    /// `children`: folder path → its entries (loaded so far). `filter`: only rows whose name contains it
    /// (case-insensitive), plus the folders on the way to them; with a filter every loaded folder counts as open.
    public static func rows(root: String, children: [String: [FolderEntry]], expanded: Set<String>,
                            filter: String = "") -> [Row] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        var out: [Row] = []

        /// Appends the rows below `dir`; returns whether anything matched (for the filter).
        @discardableResult
        func walk(_ dir: String, depth: Int, into rows: inout [Row]) -> Bool {
            var any = false
            for e in children[dir] ?? [] {
                let open = e.isDir && (needle.isEmpty ? expanded.contains(e.path) : children[e.path] != nil)
                var below: [Row] = []
                let childMatched = open ? walk(e.path, depth: depth + 1, into: &below) : false
                let selfMatched = needle.isEmpty || e.name.lowercased().contains(needle)
                guard selfMatched || childMatched else { continue }
                rows.append(Row(entry: e, depth: depth, expanded: open))
                rows.append(contentsOf: below)
                any = true
            }
            return any
        }

        walk(root, depth: 0, into: &out)
        return out
    }
}
