@testable import FolderKit
import XCTest

final class FolderListingTests: XCTestCase {
    private var dir: String!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("folderkit-\(UUID().uuidString)").path
        let fm = FileManager.default
        for d in ["src", "Docs", ".git", ".github", "node_modules"] {
            try fm.createDirectory(atPath: "\(dir!)/\(d)", withIntermediateDirectories: true)
        }
        for f in ["b.txt", "a10.txt", "a2.txt", ".env", ".DS_Store", "src/main.swift"] {
            try Data("x".utf8).write(to: URL(fileURLWithPath: "\(dir!)/\(f)"))
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    func testFoldersFirstNaturalOrderNoDotFiles() {
        let names = FolderListing.list(dir, showHidden: false).map(\.name)
        XCTAssertEqual(names, ["Docs", "node_modules", "src", "a2.txt", "a10.txt", "b.txt"])
    }

    func testHiddenShownButNeverGitOrDSStore() {
        let names = FolderListing.list(dir, showHidden: true).map(\.name)
        XCTAssertTrue(names.contains(".github"))
        XCTAssertTrue(names.contains(".env"))
        XCTAssertFalse(names.contains(".git"))
        XCTAssertFalse(names.contains(".DS_Store"))
    }

    func testSymlinkToFolderCountsAsFolder() throws {
        try FileManager.default.createSymbolicLink(atPath: "\(dir!)/link", withDestinationPath: "\(dir!)/src")
        let link = FolderListing.list(dir, showHidden: false).first { $0.name == "link" }
        XCTAssertEqual(link?.isDir, true)
    }

    func testMissingFolderIsEmpty() {
        XCTAssertEqual(FolderListing.list("\(dir!)/nope", showHidden: true), [])
    }
}

final class FolderTreeTests: XCTestCase {
    private func e(_ path: String, dir: Bool = false) -> FolderEntry {
        FolderEntry(name: (path as NSString).lastPathComponent, path: path, isDir: dir)
    }

    private var children: [String: [FolderEntry]] {
        ["/r": [e("/r/src", dir: true), e("/r/tests", dir: true), e("/r/README.md")],
         "/r/src": [e("/r/src/app", dir: true), e("/r/src/main.swift")],
         "/r/src/app": [e("/r/src/app/View.swift")]]
    }

    func testOnlyExpandedFoldersShowChildren() {
        let rows = FolderTree.rows(root: "/r", children: children, expanded: ["/r/src"])
        XCTAssertEqual(rows.map(\.entry.name), ["src", "app", "main.swift", "tests", "README.md"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 1, 0, 0])
        XCTAssertEqual(rows.first?.expanded, true)
        XCTAssertEqual(rows[1].expanded, false)
    }

    func testExpandedButNotLoadedShowsNothingBelow() {
        let rows = FolderTree.rows(root: "/r", children: children, expanded: ["/r/tests"])
        XCTAssertEqual(rows.map(\.entry.name), ["src", "tests", "README.md"])
    }

    func testFilterKeepsPathToMatches() {
        let rows = FolderTree.rows(root: "/r", children: children, expanded: [], filter: "view")
        XCTAssertEqual(rows.map(\.entry.name), ["src", "app", "View.swift"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }
}

final class GitStatusTests: XCTestCase {
    func testParsesPorcelain() {
        let out = ["## main...origin/main [ahead 1]", " M src/a.swift", "A  src/new.swift", "?? scratch/",
                   "R  b.swift", "old.swift", " D gone.txt", "UU conflict.txt"].joined(separator: "\0") + "\0"
        let s = GitStatus.parse(out, repoRoot: "/repo")
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.files["/repo/src/a.swift"], .modified)
        XCTAssertEqual(s.files["/repo/src/new.swift"], .added)
        XCTAssertEqual(s.files["/repo/scratch"], .untracked)
        XCTAssertEqual(s.files["/repo/b.swift"], .renamed)
        XCTAssertNil(s.files["/repo/old.swift"])
        XCTAssertEqual(s.files["/repo/gone.txt"], .deleted)
        XCTAssertEqual(s.files["/repo/conflict.txt"], .conflicted)
        XCTAssertTrue(s.dirtyFolders.contains("/repo/src"))
        XCTAssertTrue(s.dirtyFolders.contains("/repo"))
    }

    func testFileInsideUntrackedFolder() {
        let s = GitStatus.parse("?? scratch/\0", repoRoot: "/repo")
        XCTAssertEqual(s.change(for: "/repo/scratch/deep/x.txt"), .untracked)
        XCTAssertNil(s.change(for: "/repo/other.txt"))
    }

    func testNoCommitsYet() {
        XCTAssertEqual(GitStatus.parse("## No commits yet on main\0", repoRoot: "/r").branch, "main")
    }
}

final class FileContentTests: XCTestCase {
    func testTextBinaryImage() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("a.txt"), bin = dir.appendingPathComponent("b.bin")
        try Data("hello".utf8).write(to: text)
        try Data([0x01, 0x00, 0x02]).write(to: bin)
        XCTAssertEqual(FileContent.load(text.path), .text("hello", truncated: false))
        XCTAssertEqual(FileContent.load(text.path, limit: 2), .text("he", truncated: true))
        XCTAssertEqual(FileContent.load(bin.path), .binary(size: 3))
        XCTAssertEqual(FileContent.load(dir.appendingPathComponent("x.png").path), .image)
    }
}

final class WorktreeTests: XCTestCase {
    func testParsesPorcelain() {
        let out = """
        worktree /repo
        HEAD 1111111111111111111111111111111111111111
        branch refs/heads/main

        worktree /repo/.claude/worktrees/fix-login
        HEAD 2222222222222222222222222222222222222222
        branch refs/heads/claude/fix-login

        worktree /tmp/detached
        HEAD 3333333333333333333333333333333333333333
        detached

        worktree /gone
        HEAD 4444444444444444444444444444444444444444
        branch refs/heads/old
        prunable gitdir file points to non-existent location

        """
        let w = Worktree.parse(out)
        XCTAssertEqual(w, [
            Worktree(path: "/repo", branch: "main", isMain: true),
            Worktree(path: "/repo/.claude/worktrees/fix-login", branch: "claude/fix-login", isMain: false),
            Worktree(path: "/tmp/detached", branch: nil, isMain: false),
        ])
        XCTAssertEqual(w[1].name, "fix-login")
    }

    func testRealRepository() throws {
        let fm = FileManager.default
        let dir = FolderListing.realPath(fm.temporaryDirectory.path) + "/wt-\(UUID().uuidString)"
        try fm.createDirectory(atPath: dir + "/main", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: dir) }
        func git(_ args: String...) throws {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir + "/main", "-c", "user.name=t", "-c", "user.email=t@t"] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
        }
        try git("init", "-q", "-b", "main")
        try Data("x".utf8).write(to: URL(fileURLWithPath: dir + "/main/a.txt"))
        try git("add", ".")
        try git("commit", "-q", "-m", "init")
        XCTAssertEqual(Worktree.load(folder: dir + "/main"), [], "a single worktree is not worth a picker")
        try git("worktree", "add", "-q", "-b", "feature", dir + "/feature")
        let w = Worktree.load(folder: dir + "/main")
        XCTAssertEqual(w.map(\.branch), ["main", "feature"])
        XCTAssertEqual(w.last?.path, dir + "/feature")
        // git status sees the change from the worktree, too
        try Data("y".utf8).write(to: URL(fileURLWithPath: dir + "/feature/a.txt"))
        XCTAssertEqual(GitStatus.load(folder: dir + "/feature").files[dir + "/feature/a.txt"], .modified)
    }
}

final class GitChangesTests: XCTestCase {
    func testStagedUnstagedAndConflicts() {
        let out = ["## main...origin/main", "M  staged.swift", " M edited.swift", "MM both.swift", "?? new.txt",
                   "R  new name.md", "old name.md", "UU clash.swift", " D gone.swift"].joined(separator: "\0")
        let c = GitChanges.parse(out, repoRoot: "/r")
        XCTAssertEqual(c.branch, "main")
        XCTAssertEqual(c.staged.map(\.rel), ["both.swift", "new name.md", "staged.swift"])
        XCTAssertEqual(c.unstaged.map(\.rel), ["both.swift", "edited.swift", "gone.swift", "new.txt"])
        XCTAssertEqual(c.conflicts.map(\.rel), ["clash.swift"])
        XCTAssertEqual(c.entries.first { $0.rel == "new name.md" }?.oldRel, "old name.md")
        XCTAssertEqual(c.entries.first { $0.rel == "new.txt" }?.unstaged, .untracked)
        XCTAssertEqual(c.entries.first { $0.rel == "gone.swift" }?.unstaged, .deleted)
        XCTAssertEqual(c.entries.first { $0.rel == "staged.swift" }?.path, "/r/staged.swift")
    }

    func testRealRepository() throws {
        let dir = NSTemporaryDirectory() + "gc-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        _ = GitChanges.run(["init", "-q"], in: dir)
        try "a\n".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(GitChanges.load(folder: dir).unstaged.map(\.rel), ["a.txt"])
        XCTAssertNil(GitChanges.stage(["a.txt"], repo: dir))
        XCTAssertEqual(GitChanges.load(folder: dir).staged.map(\.rel), ["a.txt"])
        XCTAssertNil(GitChanges.unstage(["a.txt"], repo: dir))   // before the first commit
        XCTAssertEqual(GitChanges.load(folder: dir).staged.map(\.rel), [])
        XCTAssertNil(GitChanges.stage(["a.txt"], repo: dir))
        _ = GitChanges.run(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "one"], in: dir)
        try "b\n".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(String(decoding: GitChanges.contents("a.txt", repo: dir, fromIndex: false) ?? Data(), as: UTF8.self), "a\n")
        let entry = try XCTUnwrap(GitChanges.load(folder: dir).unstaged.first)
        XCTAssertNil(GitChanges.discard([entry], repo: dir))
        XCTAssertEqual(try String(contentsOfFile: dir + "/a.txt", encoding: .utf8), "a\n")
    }
}

final class LineDiffTests: XCTestCase {
    func testPairsAChangedBlockAndKeepsNumbers() {
        let rows = LineDiff.rows(old: ["a", "b", "c", "d"], new: ["a", "B", "c", "d", "e"])
        XCTAssertEqual(rows.map(\.kind), [.same, .changed, .same, .same, .added])
        XCTAssertEqual(rows[1].oldText, "b")
        XCTAssertEqual(rows[1].newText, "B")
        XCTAssertEqual(rows[4].newNumber, 5)
        XCTAssertNil(rows[4].oldNumber)
        XCTAssertEqual(LineDiff.stats(rows).added, 2)
        XCTAssertEqual(LineDiff.stats(rows).removed, 1)
    }

    func testRemovedOnly() {
        let rows = LineDiff.rows(old: ["a", "x", "y", "b"], new: ["a", "b"])
        XCTAssertEqual(rows.map(\.kind), [.same, .removed, .removed, .same])
    }

    func testFoldsLongUnchangedRunsWithContext() {
        let old = (1...30).map(String.init)
        var new = old
        new[14] = "changed"
        let items = LineDiff.fold(LineDiff.rows(old: old, new: new))
        // lines 1–11 folded, 12–14 context, the change, 16–18 context, 19–30 folded
        XCTAssertEqual(items.first, .fold(0..<11))
        XCTAssertEqual(items.last, .fold(18..<30))
        XCTAssertEqual(items.count, 9)
    }

    func testLinesDropTheFinalNewline() {
        XCTAssertEqual(LineDiff.lines("a\nb\n"), ["a", "b"])
        XCTAssertEqual(LineDiff.lines(""), [])
    }
}
