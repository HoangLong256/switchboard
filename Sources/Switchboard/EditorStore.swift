import AppKit
import EditorKit
import FolderKit
import Foundation
import Observation

/// One open file. Its own Observable, so typing only redraws the editor, not the whole window.
@MainActor
@Observable
final class DocumentModel {
    var doc: TextDocument
    /// the last save stopped because the file on disk is newer (VS Code's save conflict)
    var conflict = false
    /// counts the times the text was replaced from outside the editor (reload, revert, Open Anyway), so the
    /// editor view takes the new text without comparing whole files on every update
    private(set) var replacements = 0
    /// image files are shown, not edited
    let isImage: Bool
    var path: String { doc.path }
    var name: String { (doc.path as NSString).lastPathComponent }

    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico", "icns", "pdf"]

    init(path: String) {
        isImage = Self.imageTypes.contains((path as NSString).pathExtension.lowercased())
        doc = isImage ? TextDocument(path: path) : TextDocument.open(path)
    }

    func openAnyway() { replace(TextDocument.open(path, force: true)) }

    func replace(_ new: TextDocument) {
        replacements += 1
        doc = new
    }
}

/// Open editors per session (VS Code's preview tabs), and the save / close / reload rules around them.
@MainActor
@Observable
final class EditorStore {
    static let shared = EditorStore()

    /// session name → its tabs
    private(set) var tabs: [String: EditorTabs] = [:]
    private(set) var documents: [String: DocumentModel] = [:]
    /// diff tabs by their key (`DiffModel.key`), next to the files in the same tab strip
    private(set) var diffs: [String: DiffModel] = [:]
    /// dirty tabs are being closed: ask Save / Don't Save / Cancel
    var closeRequest: CloseRequest?
    /// each increment moves keyboard focus into the editor (double click in the tree)
    private(set) var focusRequest = 0

    @ObservationIgnored private var timer: Timer?

    private init() {
        // clean documents follow the disk (a session editing the file); a stat per open file per second is cheap
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.followDisk() }
        }
    }

    func tabs(of session: String?) -> EditorTabs { session.flatMap { tabs[$0] } ?? EditorTabs() }

    func activeDocument(of session: String?) -> DocumentModel? {
        tabs(of: session).active.flatMap { documents[$0] }
    }

    /// Single click: preview, focus stays in the tree. Double click / Enter: pinned, focus in the editor.
    func open(_ path: String, in session: String, pinned: Bool, focus: Bool = false) {
        if documents[path] == nil { documents[path] = DocumentModel(path: path) }
        var t = tabs[session] ?? EditorTabs()
        let replaced = pinned ? nil : t.preview
        t.open(path, pinned: pinned || documents[path]?.doc.isDirty == true)
        tabs[session] = t
        if let replaced, replaced != path { dropIfUnused(replaced) }
        if focus { focusRequest += 1 }
    }

    /// Opens a file's changes in a diff tab: a single click previews it, like a file.
    func openDiff(_ entry: GitChanges.Entry, repo: String, staged: Bool, in session: String, pinned: Bool) {
        let key = DiffModel.key(entry.path, staged: staged)
        if let d = diffs[key] { d.reload() } else { diffs[key] = DiffModel(entry: entry, repo: repo, staged: staged) }
        var t = tabs[session] ?? EditorTabs()
        let replaced = pinned ? nil : t.preview
        t.open(key, pinned: pinned)
        tabs[session] = t
        if let replaced, replaced != key { dropIfUnused(replaced) }
    }

    func activeDiff(of session: String?) -> DiffModel? { tabs(of: session).active.flatMap { diffs[$0] } }

    func activate(_ path: String, in session: String) {
        tabs[session]?.active = path
    }

    func pin(_ path: String, in session: String) { tabs[session]?.pin(path) }

    /// Called on every edit: a dirty tab is always pinned.
    func edited(_ path: String) {
        for (s, t) in tabs where t.preview == path { tabs[s]?.pin(path) }
    }

    struct CloseRequest: Equatable {
        let session: String
        /// the tabs with unsaved changes; the others are closed already
        let paths: [String]
    }

    /// Closes the tab, or asks first when it has unsaved changes.
    func requestClose(_ path: String, in session: String) { requestClose([path], in: session) }

    /// Closes the clean tabs right away, then asks once about the ones with unsaved changes (VS Code's
    /// "Close All" with Save All / Don't Save / Cancel).
    func requestClose(_ paths: [String], in session: String) {
        let dirty = paths.filter { documents[$0]?.doc.isDirty == true }
        for p in paths where !dirty.contains(p) { close(p, in: session) }
        if !dirty.isEmpty { closeRequest = CloseRequest(session: session, paths: dirty) }
    }

    /// Close Others: keeps `path` open and active.
    func closeOthers(_ path: String, in session: String) {
        activate(path, in: session)
        requestClose(tabs(of: session).others(than: path), in: session)
    }

    func closeToTheRight(of path: String, in session: String) {
        if let active = tabs(of: session).active, tabs(of: session).right(of: path).contains(active) {
            activate(path, in: session)
        }
        requestClose(tabs(of: session).right(of: path), in: session)
    }

    /// Close Saved: only the tabs without unsaved changes, never asks.
    func closeSaved(in session: String) {
        for p in tabs(of: session).paths where documents[p]?.doc.isDirty != true { close(p, in: session) }
    }

    func closeAll(in session: String) { requestClose(tabs(of: session).paths, in: session) }

    func close(_ path: String, in session: String) {
        tabs[session]?.close(path)
        dropIfUnused(path)
    }

    /// Saves; on a conflict the document shows Compare / Overwrite instead. Returns whether it was written.
    @discardableResult
    func save(_ path: String, overwrite: Bool = false) -> Bool {
        guard let m = documents[path] else { return false }
        switch m.doc.save(overwrite: overwrite) {
        case .saved:
            m.conflict = false
            return true
        case .conflict:
            m.conflict = true
            return false
        case .failed(let why):
            let a = NSAlert()
            a.messageText = "Failed to save “\(m.name)”"
            a.informativeText = why
            a.runModal()
            return false
        }
    }

    func revert(_ path: String) {
        guard let m = documents[path] else { return }
        var d = m.doc
        d.revert()
        m.replace(d)
        m.conflict = false
    }

    var dirtyDocuments: [DocumentModel] { documents.values.filter(\.doc.isDirty).sorted { $0.path < $1.path } }

    func dirtyCount(in session: String?) -> Int {
        tabs(of: session).paths.filter { documents[$0]?.doc.isDirty == true }.count
    }

    private func dropIfUnused(_ path: String) {
        guard !tabs.values.contains(where: { $0.paths.contains(path) }) else { return }
        documents[path] = nil
        diffs[path] = nil
    }

    private func followDisk() {
        for m in documents.values where !m.isImage {
            var d = m.doc
            if d.reloadIfClean() { m.replace(d) }
        }
        for d in diffs.values { d.reloadIfChanged() }
    }
}

/// A diff tab: one file's changes, as VS Code's diff editor shows them. `staged`: HEAD ↔ index
/// ("Staged Changes"), otherwise index ↔ working tree ("Changes").
@MainActor
@Observable
final class DiffModel {
    /// tab key: "diff:index:<path>" or "diff:work:<path>"
    let key: String
    let entry: GitChanges.Entry
    let repo: String
    let staged: Bool
    private(set) var rows: [LineDiff.Row] = []
    private(set) var notice: String?
    private(set) var loaded = false
    @ObservationIgnored private var stamp: (Date?, Date?) = (nil, nil)

    var path: String { entry.path }
    var name: String { entry.name }
    /// "Package.swift (Index)" like VS Code's tab title
    var title: String { "\(entry.name) (\(staged ? "Index" : "Working Tree"))" }

    static func key(_ path: String, staged: Bool) -> String { "diff:\(staged ? "index" : "work"):\(path)" }

    init(entry: GitChanges.Entry, repo: String, staged: Bool) {
        self.entry = entry
        self.repo = repo
        self.staged = staged
        key = Self.key(entry.path, staged: staged)
        reload()
    }

    /// Reloads when the file or the index changed on disk (checked once a second by EditorStore).
    func reloadIfChanged() {
        if currentStamp() != stamp { reload() }
    }

    private func currentStamp() -> (Date?, Date?) {
        let fm = FileManager.default
        let m = { (p: String) in (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date }
        return (m(entry.path), m(repo + "/.git/index"))
    }

    func reload() {
        stamp = currentStamp()
        let (entry, repo, staged) = (entry, repo, staged)
        Task {
            let result = await Task.detached { () -> ([LineDiff.Row], String?) in
                // old side: HEAD for staged changes, else the index (falling back to HEAD)
                let oldOrig = entry.oldRel ?? entry.rel
                let old: Data = staged
                    ? GitChanges.contents(oldOrig, repo: repo, fromIndex: false) ?? Data()
                    : GitChanges.contents(entry.rel, repo: repo, fromIndex: true)
                        ?? GitChanges.contents(oldOrig, repo: repo, fromIndex: false) ?? Data()
                let new: Data = staged
                    ? GitChanges.contents(entry.rel, repo: repo, fromIndex: true) ?? Data()
                    : FileManager.default.contents(atPath: entry.path) ?? Data()
                if old.contains(0) || new.contains(0) { return ([], "Binary file – no text to compare.") }
                guard let o = String(data: old, encoding: .utf8), let n = String(data: new, encoding: .utf8) else {
                    return ([], "Not UTF-8 text – no text to compare.")
                }
                let ol = LineDiff.lines(o), nl = LineDiff.lines(n)
                if ol.count + nl.count > LineDiff.maxLines { return ([], "Too large to compare here.") }
                return (LineDiff.rows(old: ol, new: nl), nil)
            }.value
            rows = result.0
            notice = result.1
            loaded = true
        }
    }
}
