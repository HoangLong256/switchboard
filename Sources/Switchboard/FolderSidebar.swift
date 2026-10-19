import AppKit
import FolderKit
import SessionCore
import SwiftUI

/// The folder structure of the selected session: its working directory as a tree, with git changes marked.
/// Clicks work like VS Code's Explorer: a single click previews a file (focus stays here), a double click or
/// Return keeps it open and moves focus into the editor, arrow keys only move the selection, Space previews.
/// Folders open and close with a click or ←/→.
struct FolderSidebar: View {
    @Environment(Store.self) private var store
    @State private var model = FolderModel()
    private var editors: EditorStore { .shared }
    /// highlighted row in the tree (keyboard focus), not necessarily the open file
    @State private var selection: String?
    @State private var lookingUp = false
    /// worktree picked per session instead of its own folder
    @State private var worktreeOf: [String: String] = [:]
    @AppStorage("sidebarMode") private var mode: SidebarMode = .explorer
    /// turns of the refresh button
    @State private var spins = 0

    enum SidebarMode: String { case explorer, sourceControl }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if mode == .sourceControl && model.root != nil {
                SourceControlView(model: model)
            } else {
                content
            }
        }
        .themeBackground(sidebar: true)
        .frame(minWidth: 220)
        // re-run when the selection or its folder changes (the folder may only be known after the first refresh)
        .task(id: "\(store.selected ?? "")|\(store.selectedFolder ?? "")") { await follow() }
        .toolbar { toolbarButtons }
    }

    /// The buttons above the column, for what it shows: the tree (hidden files, collapse, refresh) or the changes
    /// (stage all, refresh). Their tooltips come from `ToolbarTips`, by label.
    @ToolbarContentBuilder
    private var toolbarButtons: some ToolbarContent {
        ToolbarItemGroup {
            if mode == .sourceControl && model.root != nil {
                Button { model.stage(model.changes.unstaged) } label: { Label("Stage All Changes", systemImage: "plus") }
                    .disabled(model.changes.unstaged.isEmpty)
                refreshButton("Refresh Changes")
            } else {
                // a fixed label (the tooltip goes by it); the icon and the toggle's highlight show the state
                Toggle(isOn: Bindable(model).showHidden) {
                    Label("Hidden Files", systemImage: model.showHidden ? "eye" : "eye.slash")
                }
                .disabled(model.root == nil)
                Button { model.collapseAll() } label: { Label("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .disabled(model.root == nil || model.expanded.isEmpty)
                refreshButton("Refresh Explorer")
            }
        }
    }

    /// Turns once when clicked, so a refresh that finds nothing new still shows it happened.
    private func refreshButton(_ title: String) -> some View {
        Button {
            model.reloadAll()
            withAnimation(.easeInOut(duration: 0.5)) { spins += 1 }
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(Double(spins) * 360))
            }
        }
        .disabled(model.root == nil)
    }

    /// Explorer | Source Control, like VS Code's activity bar; Source Control shows how many files changed.
    private var modePicker: some View {
        let count = model.git.files.count
        return Picker("", selection: $mode) {
            Label("Explorer", systemImage: "doc.on.doc").tag(SidebarMode.explorer)
            Label(count > 0 ? "Changes \(count)" : "Changes", systemImage: "arrow.triangle.branch").tag(SidebarMode.sourceControl)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Explorer or Source Control")
    }

    private func follow() async {
        guard let row = store.selectedRow else { model.show(nil); return }
        if let w = worktreeOf[row.name] { model.show(w); return }
        if let f = store.folder(of: row) { model.show(f); return }
        lookingUp = true
        model.show(await store.findFolder(of: row))
        lookingUp = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let root = model.root {
                modePicker
                HStack(alignment: .firstTextBaseline) {
                    Text((root as NSString).lastPathComponent).font(.headline).lineLimit(1)
                    Spacer()
                    if let b = model.git.branch {
                        Label(b, systemImage: "arrow.triangle.branch").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if !model.worktrees.isEmpty { worktreePicker(root) }
                if mode == .explorer {
                    TextField("Filter", text: Bindable(model).filter)
                        .textFieldStyle(.roundedBorder).controlSize(.small)
                }
            } else {
                Text("Folder").font(.headline)
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.selected == nil {
            placeholder("sidebar.left", "No session selected", "Select a session to see its folder.")
        } else if model.root == nil {
            if lookingUp { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { placeholder("questionmark.folder", "No folder", "This session's working directory isn't known.") }
        } else {
            let rows = model.rows
            if rows.isEmpty && !model.filter.isEmpty {
                placeholder("magnifyingglass", "No matches", "Nothing loaded matches “\(model.filter)”.")
            } else {
                List(rows, selection: $selection) { row in
                    FolderRowView(row: row, change: change(of: row.entry), toggle: { model.toggle(row.entry) },
                                  open: editors.tabs(of: store.selected).paths.contains(row.entry.path))
                        .tag(row.entry.path)
                        .listRowSeparator(.hidden)
                        // drag onto the terminal to type the path (itemProvider keeps clicks and selection working)
                        .itemProvider { NSItemProvider(object: URL(fileURLWithPath: row.entry.path) as NSURL) }
                }
                .listStyle(.inset)
                .themeBackground(sidebar: true)
                .contextMenu(forSelectionType: String.self) { paths in
                    if let p = paths.first, let e = entry(p) { menu(e) }
                } primaryAction: { paths in
                    // double click or Return
                    guard let p = paths.first, let e = entry(p) else { return }
                    if e.isDir {
                        // the first click of a double click already toggled the folder
                        if NSApp.currentEvent?.type == .keyDown { model.toggle(e) }
                    } else {
                        store.openFile(p, pinned: true)
                    }
                }
                .onChange(of: selection) { _, path in clicked(path) }
                .onKeyPress(.rightArrow) { arrow(open: true) }
                .onKeyPress(.leftArrow) { arrow(open: false) }
                .onKeyPress(.space) {
                    guard let p = selection, let e = entry(p), !e.isDir else { return .ignored }
                    store.openFile(p, pinned: false)
                    return .handled
                }
                // reveal the active editor's file in the tree (explorer.autoReveal)
                .onChange(of: editors.tabs(of: store.selected).active) { _, path in
                    guard let path else { return }
                    model.reveal(path)
                    if selection != path { selection = path }
                }
            }
        }
    }

    private func entry(_ path: String) -> FolderEntry? { model.rows.first { $0.entry.path == path }?.entry }

    /// Selection changed. Only a mouse click opens something; arrow keys just move the highlight.
    private func clicked(_ path: String?) {
        guard let path, let e = entry(path) else { return }
        let type = NSApp.currentEvent?.type
        guard type == .leftMouseDown || type == .leftMouseUp else { return }
        if e.isDir { model.toggle(e) } else { store.openFile(path, pinned: false) }
    }

    private func arrow(open: Bool) -> KeyPress.Result {
        guard let path = selection ?? model.rows.first?.entry.path,
              let row = model.rows.first(where: { $0.entry.path == path }), row.entry.isDir,
              row.expanded != open else { return .ignored }
        model.toggle(row.entry)
        return .handled
    }

    /// Switch the tree between the repository's worktrees (sessions started with `claude --worktree`).
    private func worktreePicker(_ root: String) -> some View {
        Menu {
            ForEach(model.worktrees) { w in
                Button {
                    guard let name = store.selected else { return }
                    let own = store.selectedFolder.map(FolderListing.realPath)
                    worktreeOf[name] = w.path == own ? nil : w.path
                    model.show(w.path)
                } label: {
                    Label("\(w.isMain ? "main" : w.name) · \(w.branch ?? "detached")",
                          systemImage: w.path == root ? "checkmark" : (w.isMain ? "house" : "arrow.triangle.branch"))
                }
            }
        } label: {
            Label("\(model.worktrees.count) worktrees", systemImage: "square.stack.3d.up")
        }
        .menuStyle(.borderlessButton).controlSize(.small).fixedSize()
        .help("Browse another worktree of this repository")
    }

    private func change(of e: FolderEntry) -> GitStatus.Change? {
        if let c = model.git.change(for: e.path) { return c }
        return e.isDir && model.git.dirtyFolders.contains(e.path) ? .modified : nil
    }

    @ViewBuilder
    private func menu(_ e: FolderEntry) -> some View {
        if !e.isDir {
            Button("Open") { store.openFile(e.path, pinned: true) }
            Button("Open Preview") { store.openFile(e.path, pinned: false) }
        }
        Button("Open with Default App") { NSWorkspace.shared.open(URL(fileURLWithPath: e.path)) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: e.path)]) }
        Divider()
        Button("Insert @Path into Terminal") { store.insertIntoTerminal("@\(relative(e.path)) ") }
            .disabled(store.selectedTmux == nil)
        Button("Copy Relative Path") { copy(relative(e.path)) }
        Button("Copy Full Path") { copy(e.path) }
    }

    private func relative(_ path: String) -> String {
        guard let root = model.root, path.hasPrefix(root + "/") else { return path }
        return String(path.dropFirst(root.count + 1))
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func placeholder(_ symbol: String, _ title: String, _ text: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(text))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FolderRowView: View {
    let row: FolderTree.Row
    let change: GitStatus.Change?
    let toggle: () -> Void
    /// open in an editor tab of this session
    var open = false

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if row.entry.isDir {
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(row.expanded ? 90 : 0))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: toggle)
                } else {
                    Color.clear
                }
            }
            .frame(width: 12)
            FileIconView(name: row.entry.name, isDir: row.entry.isDir, expanded: row.expanded)
            Text(row.entry.name).lineLimit(1).truncationMode(.middle)
                .fontWeight(open ? .semibold : .regular)
                // names take their git color, like VS Code's Explorer (folders with changes inside too)
                .foregroundStyle(change == .deleted ? AnyShapeStyle(.secondary)
                                 : change.map { AnyShapeStyle(color($0).opacity(row.entry.isDir ? 0.85 : 1)) } ?? AnyShapeStyle(.primary))
                .strikethrough(change == .deleted)
            Spacer(minLength: 4)
            if let change, !row.entry.isDir {
                Text(change.letter).font(.caption.monospaced().weight(.semibold)).foregroundStyle(color(change))
            } else if change != nil {
                Circle().fill(Color.secondary.opacity(0.6)).frame(width: 5, height: 5)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .help(row.entry.path)
    }

    private func color(_ c: GitStatus.Change) -> Color {
        switch c {
        case .added, .untracked: Palette.added
        case .deleted, .conflicted: Palette.deleted
        case .modified, .renamed: Palette.modified
        }
    }
}
