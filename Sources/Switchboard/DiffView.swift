import AppKit
import FolderKit
import SwiftUI

/// A file's changes like VS Code's diff editor: side by side (old left, new right) or inline, with unchanged
/// regions folded away, in the editor theme's colors.
struct DiffView: View {
    @Environment(Store.self) private var store
    let model: DiffModel
    let session: String
    @AppStorage("diffInline") private var inline = false
    @AppStorage("diffHideUnchanged") private var hideUnchanged = true
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @Environment(\.colorScheme) private var scheme
    /// folds opened by a click, by their first row
    @State private var opened: Set<Int> = []

    private var palette: EditorPalette { theme.palette(dark: scheme == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(hex: palette.background))
    }

    @ViewBuilder
    private var content: some View {
        if let notice = model.notice {
            ContentUnavailableView(notice, systemImage: "doc.questionmark")
        } else if !model.loaded {
            ProgressView().controlSize(.small)
        } else if model.rows.allSatisfy({ $0.kind == .same }) {
            ContentUnavailableView("No changes", systemImage: "checkmark.circle",
                                   description: Text(model.staged ? "Nothing of this file is staged." : "The file matches the index."))
        } else {
            ScrollView([.vertical]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        switch item {
                        case .row(let i):
                            if inline { inlineRows(model.rows[i]) } else { sideBySide(model.rows[i]) }
                        case .fold(let range):
                            foldRow(range)
                        }
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.bottom, 12)
            }
        }
    }

    private var items: [LineDiff.Item] {
        guard hideUnchanged else { return model.rows.indices.map(LineDiff.Item.row) }
        // opened folds show their rows again
        return LineDiff.fold(model.rows).flatMap { item -> [LineDiff.Item] in
            if case .fold(let r) = item, opened.contains(r.lowerBound) { return r.map(LineDiff.Item.row) }
            return [item]
        }
    }

    // MARK: Bar

    private var bar: some View {
        let (added, removed) = LineDiff.stats(model.rows)
        return HStack(spacing: 8) {
            (Text(model.entry.folder.isEmpty ? "" : model.entry.folder + "/").foregroundColor(.secondary.opacity(0.6))
                + Text(model.name).foregroundColor(.secondary))
                .lineLimit(1).truncationMode(.head)
            Text(model.staged ? "HEAD ↔ Index" : "Index ↔ Working Tree").font(.caption).foregroundStyle(.tertiary)
            Spacer()
            if model.loaded && model.notice == nil {
                Text("+\(added)").foregroundStyle(Palette.added).monospacedDigit()
                Text("−\(removed)").foregroundStyle(Palette.deleted).monospacedDigit()
            }
            Picker("", selection: $inline) {
                Image(systemName: "rectangle.split.2x1").tag(false).help("Side by side")
                Image(systemName: "rectangle.grid.1x2").tag(true).help("Inline")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            Toggle(isOn: $hideUnchanged) { Image(systemName: "arrow.up.and.down.text.horizontal") }
                .toggleStyle(.button)
                .help(hideUnchanged ? "Show unchanged regions" : "Hide unchanged regions")
            Button { stageToggle() } label: { Image(systemName: model.staged ? "minus" : "plus") }
                .help(model.staged ? "Unstage Changes" : "Stage Changes")
            Button { store.openFile(model.path, pinned: true) } label: { Image(systemName: "doc.text") }
                .help("Open File")
                .disabled(!FileManager.default.fileExists(atPath: model.path))
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    private func stageToggle() {
        let (entry, repo, staged) = (model.entry, model.repo, model.staged)
        Task {
            let err = await Task.detached {
                staged ? GitChanges.unstage([entry.rel], repo: repo) : GitChanges.stage([entry.rel], repo: repo)
            }.value
            if let err { store.notice = err }
            model.reload()
        }
    }

    // MARK: Rows

    private var gutterWidth: CGFloat {
        let digits = String(model.rows.count).count
        return CGFloat(max(digits, 2)) * 7.5 + 10
    }

    private func tint(_ added: Bool) -> Color {
        (added ? Palette.added : Palette.deleted).opacity(palette.dark ? 0.2 : 0.14)
    }

    private func sideBySide(_ r: LineDiff.Row) -> some View {
        HStack(spacing: 0) {
            half(r.oldNumber, r.oldText, background: r.kind == .removed || r.kind == .changed ? tint(false)
                 : (r.oldText == nil ? filler : .clear))
            Rectangle().fill(Color(hex: palette.gutter).opacity(0.25)).frame(width: 1)
            half(r.newNumber, r.newText, background: r.kind == .added || r.kind == .changed ? tint(true)
                 : (r.newText == nil ? filler : .clear))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// the side without a line in this row
    private var filler: Color { Color(hex: palette.gutter).opacity(0.08) }

    private func half(_ number: Int?, _ text: String?, background: Color) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(number.map(String.init) ?? "")
                .foregroundColor(Color(hex: palette.gutter))
                .frame(width: gutterWidth, alignment: .trailing)
                .padding(.trailing, 10)
            Text(text.map { $0.isEmpty ? " " : $0 } ?? "")
                .foregroundColor(Color(hex: palette.foreground))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
    }

    @ViewBuilder
    private func inlineRows(_ r: LineDiff.Row) -> some View {
        switch r.kind {
        case .same: inlineLine(r.oldNumber, r.newNumber, " ", r.newText, nil)
        case .removed: inlineLine(r.oldNumber, nil, "−", r.oldText, false)
        case .added: inlineLine(nil, r.newNumber, "+", r.newText, true)
        case .changed:
            inlineLine(r.oldNumber, nil, "−", r.oldText, false)
            inlineLine(nil, r.newNumber, "+", r.newText, true)
        }
    }

    private func inlineLine(_ old: Int?, _ new: Int?, _ mark: String, _ text: String?, _ added: Bool?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(old.map(String.init) ?? "").frame(width: gutterWidth, alignment: .trailing)
            Text(new.map(String.init) ?? "").frame(width: gutterWidth, alignment: .trailing)
            Text(mark).frame(width: 22)
                .foregroundColor(added.map { $0 ? Palette.added : Palette.deleted } ?? .clear)
            Text(text.map { $0.isEmpty ? " " : $0 } ?? "")
                .foregroundColor(Color(hex: palette.foreground))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(Color(hex: palette.gutter))
        .padding(.vertical, 1)
        .background(added.map(tint) ?? .clear)
    }

    private func foldRow(_ range: Range<Int>) -> some View {
        Button { opened.insert(range.lowerBound) } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up.chevron.down")
                Text("\(range.count) unchanged lines")
            }
            .font(.caption)
            .foregroundColor(Color(hex: palette.gutter))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(Color(hex: palette.gutter).opacity(0.1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show these lines")
    }
}
