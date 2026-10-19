import AppKit
import FolderKit
import SwiftUI

/// VS Code's Source Control view for the selected session's repository: a commit box, then Merge Changes,
/// Staged Changes and Changes. A click opens the file's changes in a diff tab.
struct SourceControlView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: FolderModel
    @ObservedObject private var editors = EditorStore.shared
    @State private var message = ""
    @State private var committing = false
    @State private var confirmDiscard: [GitChanges.Entry]?
    /// staging by another program (`git add` in a session) only touches `.git/index`, which the folder watcher
    /// ignores, so the list looks again every few seconds while it is shown
    private let tick = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var changes: GitChanges { model.changes }

    var body: some View {
        Group {
            if changes.repoRoot == nil {
                ContentUnavailableView("No repository", systemImage: "arrow.triangle.branch",
                                       description: Text("This folder isn't in a git repository."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    commitBox
                    list
                }
            }
        }
        .onAppear { model.wantsChanges = true }
        .onReceive(tick) { _ in model.loadChanges() }
        .onDisappear { model.wantsChanges = false }
        .alert("Git", isPresented: Binding(get: { model.gitError != nil }, set: { if !$0 { model.gitError = nil } })) {
            Button("OK") { model.gitError = nil }
        } message: {
            Text(model.gitError ?? "")
        }
        .confirmationDialog(discardTitle, isPresented: Binding(get: { confirmDiscard != nil },
                                                               set: { if !$0 { confirmDiscard = nil } })) {
            Button(discardButton, role: .destructive) {
                if let e = confirmDiscard { model.discard(e) }
                confirmDiscard = nil
            }
        } message: {
            Text("This can't be undone. New files are moved to the Trash.")
        }
    }

    // MARK: Commit

    private var commitBox: some View {
        VStack(spacing: 6) {
            TextField("Message (⌘↩ to commit on “\(changes.branch ?? "HEAD")”)", text: $message, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
            Button { commit() } label: {
                Label(committing ? "Committing…" : "Commit", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(changes.staged.isEmpty || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || committing)
            .help(changes.staged.isEmpty ? "Stage changes first (+)" : "Commit the staged changes")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func commit() {
        committing = true
        Task {
            if await model.commit(message) { message = "" }
            committing = false
        }
    }

    // MARK: List

    private var list: some View {
        List {
            if !changes.conflicts.isEmpty {
                Section {
                    ForEach(changes.conflicts) { row($0, staged: false, change: .conflicted) }
                } header: {
                    header("Merge Changes", changes.conflicts) {
                        button("plus", "Stage All Merge Changes") { model.stage(changes.conflicts) }
                    }
                }
            }
            if !changes.staged.isEmpty {
                Section {
                    ForEach(changes.staged) { e in row(e, staged: true, change: e.staged!) }
                } header: {
                    header("Staged Changes", changes.staged) {
                        button("minus", "Unstage All Changes") { model.unstage(changes.staged) }
                    }
                }
            }
            Section {
                ForEach(changes.unstaged) { e in row(e, staged: false, change: e.unstaged!) }
            } header: {
                header("Changes", changes.unstaged) {
                    button("arrow.uturn.backward", "Discard All Changes") { confirmDiscard = changes.unstaged }
                        .disabled(changes.unstaged.isEmpty)
                    button("plus", "Stage All Changes") { model.stage(changes.unstaged) }
                        .disabled(changes.unstaged.isEmpty)
                }
            }
            if changes.entries.isEmpty {
                Text("No changes").foregroundStyle(.secondary).font(.callout)
            }
        }
        .listStyle(.sidebar)
        .themeBackground(sidebar: true)
    }

    private func header<Buttons: View>(_ title: String, _ entries: [GitChanges.Entry],
                                       @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Spacer()
            buttons()
            Text("\(entries.count)")
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func row(_ e: GitChanges.Entry, staged: Bool, change: GitStatus.Change) -> some View {
        SourceControlRow(entry: e, change: change, staged: staged,
                         active: editors.tabs(of: store.selected).active == DiffModel.key(e.path, staged: staged),
                         open: { pinned in
                             if let repo = changes.repoRoot { store.openDiff(e, repo: repo, staged: staged, pinned: pinned) }
                         },
                         openFile: { store.openFile(e.path, pinned: true) },
                         stage: { model.stage([e]) },
                         unstage: { model.unstage([e]) },
                         discard: { confirmDiscard = [e] })
    }

    private var discardTitle: String {
        guard let e = confirmDiscard else { return "" }
        return e.count == 1 ? "Discard changes in \(e[0].name)?" : "Discard all \(e.count) changes?"
    }

    private var discardButton: String {
        (confirmDiscard?.count ?? 0) == 1 ? "Discard File" : "Discard All"
    }
}

/// One changed file: icon, name, folder, the buttons on hover, and the status letter.
private struct SourceControlRow: View {
    let entry: GitChanges.Entry
    let change: GitStatus.Change
    let staged: Bool
    let active: Bool
    let open: (Bool) -> Void
    let openFile: () -> Void
    let stage: () -> Void
    let unstage: () -> Void
    let discard: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            FileIconView(name: entry.name)
            Text(entry.name)
                .lineLimit(1)
                .layoutPriority(1)   // the folder gives way first
                .strikethrough(change == .deleted)
                .foregroundStyle(change == .deleted ? .secondary : .primary)
            Text(entry.folder)
                .font(.caption).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 2)
            if hover {
                Group {
                    if change != .deleted { icon("doc.text", "Open File", openFile) }
                    if staged {
                        icon("minus", "Unstage Changes", unstage)
                    } else {
                        icon("arrow.uturn.backward", "Discard Changes", discard)
                        icon("plus", "Stage Changes", stage)
                    }
                }
            }
            Text(change.letter)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 12)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { open(true) }
        .onTapGesture { open(false) }
        .listRowBackground(active ? Color.accentColor.opacity(0.18) : Color.clear)
        .contextMenu {
            Button("Open Changes") { open(true) }
            if change != .deleted { Button("Open File") { openFile() } }
            Divider()
            if staged { Button("Unstage Changes") { unstage() } } else {
                Button("Stage Changes") { stage() }
                Button("Discard Changes…", role: .destructive) { discard() }
            }
            Divider()
            Button("Copy Path") { copy(entry.path) }
            Button("Copy Relative Path") { copy(entry.rel) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.path)]) }
        }
        .help(entry.oldRel.map { "\($0) → \(entry.rel)" } ?? entry.rel)
    }

    private var color: Color {
        switch change {
        case .added, .untracked: Palette.added
        case .deleted, .conflicted: Palette.deleted
        case .modified, .renamed: Palette.modified
        }
    }

    private func icon(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)) }
            .buttonStyle(.borderless)
            .help(help)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
