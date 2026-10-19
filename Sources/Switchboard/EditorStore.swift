import AppKit
import EditorKit
import Foundation

/// One open file. Its own ObservableObject, so typing only redraws the editor, not the whole window.
@MainActor
final class DocumentModel: ObservableObject {
    @Published var doc: TextDocument
    /// the last save stopped because the file on disk is newer (VS Code's save conflict)
    @Published var conflict = false
    /// image files are shown, not edited
    let isImage: Bool
    var path: String { doc.path }
    var name: String { (doc.path as NSString).lastPathComponent }

    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "ico", "icns", "pdf"]

    init(path: String) {
        isImage = Self.imageTypes.contains((path as NSString).pathExtension.lowercased())
        doc = isImage ? TextDocument(path: path) : TextDocument.open(path)
    }

    func openAnyway() { doc = TextDocument.open(path, force: true) }
}

/// Open editors per session (VS Code's preview tabs), and the save / close / reload rules around them.
@MainActor
final class EditorStore: ObservableObject {
    static let shared = EditorStore()

    /// session name → its tabs
    @Published private(set) var tabs: [String: EditorTabs] = [:]
    @Published private(set) var documents: [String: DocumentModel] = [:]
    /// a dirty tab is being closed: ask Save / Don't Save / Cancel
    @Published var closeRequest: (session: String, path: String)?
    /// each increment moves keyboard focus into the editor (double click in the tree)
    @Published private(set) var focusRequest = 0

    private var timer: Timer?

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

    func activate(_ path: String, in session: String) {
        tabs[session]?.active = path
    }

    func pin(_ path: String, in session: String) { tabs[session]?.pin(path) }

    /// Called on every edit: a dirty tab is always pinned.
    func edited(_ path: String) {
        for (s, t) in tabs where t.preview == path { tabs[s]?.pin(path) }
    }

    /// Closes the tab, or asks first when it has unsaved changes.
    func requestClose(_ path: String, in session: String) {
        if documents[path]?.doc.isDirty == true { closeRequest = (session, path) } else { close(path, in: session) }
    }

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
        m.doc.revert()
        m.conflict = false
    }

    var dirtyDocuments: [DocumentModel] { documents.values.filter(\.doc.isDirty).sorted { $0.path < $1.path } }

    func dirtyCount(in session: String?) -> Int {
        tabs(of: session).paths.filter { documents[$0]?.doc.isDirty == true }.count
    }

    private func dropIfUnused(_ path: String) {
        guard !tabs.values.contains(where: { $0.paths.contains(path) }) else { return }
        documents[path] = nil
    }

    private func followDisk() {
        for m in documents.values where !m.isImage {
            var d = m.doc
            if d.reloadIfClean() { m.doc = d }
        }
    }
}
