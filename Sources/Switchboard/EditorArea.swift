import AppKit
import EditorKit
import FolderKit
import MarkdownUI
import SwiftUI

/// Editor tab of a session: open files as tabs (preview in italics, a dot for unsaved changes) above the editor.
struct EditorArea: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var editors = EditorStore.shared
    let session: String

    var body: some View {
        let tabs = editors.tabs(of: session)
        VStack(spacing: 0) {
            if !tabs.paths.isEmpty {
                TabStrip(session: session, tabs: tabs)
                Divider()
            }
            if let m = editors.activeDocument(of: session) {
                DocumentView(model: m, session: session).id(m.path)
            } else if let d = editors.activeDiff(of: session) {
                DiffView(model: d, session: session).id(d.key)
            } else {
                ContentUnavailableView("No open file", systemImage: "doc.text",
                                       description: Text("Click a file in the folder sidebar to preview it; double-click to keep it open."))
            }
        }
        .alert(closeTitle, isPresented: closeBinding) {
            Button(closeNames.count > 1 ? "Save All" : "Save") { closeDirty(save: true) }
            Button("Don't Save", role: .destructive) { closeDirty(save: false) }
            Button("Cancel", role: .cancel) { editors.closeRequest = nil }
        } message: {
            Text((closeNames.count > 1 ? closeNames.joined(separator: "\n") + "\n\n" : "")
                + "Your changes will be lost if you don't save them.")
        }
    }

    private var closeNames: [String] { (editors.closeRequest?.paths ?? []).map { ($0 as NSString).lastPathComponent } }

    private var closeTitle: String {
        closeNames.count > 1 ? "Do you want to save the changes to the following \(closeNames.count) files?"
            : "Do you want to save the changes you made to \(closeNames.first ?? "")?"
    }

    private var closeBinding: Binding<Bool> {
        Binding(get: { editors.closeRequest?.session == session }, set: { if !$0 { editors.closeRequest = nil } })
    }

    private func closeDirty(save: Bool) {
        guard let r = editors.closeRequest else { return }
        editors.closeRequest = nil
        for path in r.paths {
            if save, !editors.save(path) { continue }   // conflict or error: keep the tab open
            if !save { editors.revert(path) }
            editors.close(path, in: r.session)
        }
    }
}

private struct TabStrip: View {
    @ObservedObject private var editors = EditorStore.shared
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    let session: String
    let tabs: EditorTabs

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.paths, id: \.self) { path in
                        if let m = editors.documents[path] {
                            TabItem(model: m, session: session, active: tabs.active == path, preview: tabs.preview == path)
                                .contextMenu { TabMenu(session: session, path: path, tabs: tabs) }
                        } else if let d = editors.diffs[path] {
                            DiffTabItem(model: d, session: session, active: tabs.active == path, preview: tabs.preview == path)
                                .contextMenu { TabMenu(session: session, path: path, tabs: tabs) }
                        }
                        Divider().frame(height: 18)
                    }
                }
            }
            Divider().frame(height: 18)
            // VS Code's "…" at the end of the tab bar
            Menu {
                if let active = tabs.active { TabMenu(session: session, path: active, tabs: tabs) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, 10)
            .help("Close Others, Close All, …")
        }
        .frame(height: 32)
        .background(theme.themesApp ? AnyShapeStyle(Color(hex: theme.palette(dark: true).sidebar)) : AnyShapeStyle(.bar))
    }
}

/// A diff tab: "Package.swift (Working Tree)" with the diff icon.
private struct DiffTabItem: View {
    @ObservedObject private var editors = EditorStore.shared
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @Environment(\.colorScheme) private var scheme
    let model: DiffModel
    let session: String
    let active: Bool
    let preview: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            FileIconView(name: model.name)
            Text(model.title).italic(preview).lineLimit(1)
            Button { editors.requestClose(model.key, in: session) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 14, height: 14)
                    .opacity(hover || active ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help("Close (⌘W)")
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(active ? Color(hex: theme.palette(dark: scheme == .dark).background) : .clear)
        .overlay(alignment: .top) { if active { Rectangle().fill(Color.accentColor).frame(height: 2) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { editors.pin(model.key, in: session) }
        .onTapGesture { editors.activate(model.key, in: session) }
        .help("\(model.entry.rel) – \(model.staged ? "staged changes (HEAD ↔ index)" : "changes in the working tree (index ↔ file)")")
    }
}

/// Closing tabs, as in VS Code's tab context menu.
struct TabMenu: View {
    @ObservedObject private var editors = EditorStore.shared
    let session: String
    /// the tab's key: a file path, or a diff tab's key
    let path: String
    let tabs: EditorTabs

    /// the file behind the tab
    private var file: String { editors.diffs[path]?.path ?? path }

    var body: some View {
        Button("Close") { editors.requestClose(path, in: session) }
        Button("Close Others") { editors.closeOthers(path, in: session) }
            .disabled(tabs.others(than: path).isEmpty)
        Button("Close to the Right") { editors.closeToTheRight(of: path, in: session) }
            .disabled(tabs.right(of: path).isEmpty)
        Button("Close Saved") { editors.closeSaved(in: session) }
            .disabled(!tabs.paths.contains { editors.documents[$0]?.doc.isDirty != true })
        Button("Close All") { editors.closeAll(in: session) }
        Divider()
        if tabs.preview == path { Button("Keep Open") { editors.pin(path, in: session) } }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(file, forType: .string)
        }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file)]) }
    }
}

private struct TabItem: View {
    @ObservedObject private var editors = EditorStore.shared
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @Environment(\.colorScheme) private var scheme
    /// observed, so the dot for unsaved changes follows every keystroke
    @ObservedObject var model: DocumentModel
    let session: String
    let active: Bool
    let preview: Bool
    @State private var hover = false

    private var path: String { model.path }
    private var dirty: Bool { model.doc.isDirty }

    var body: some View {
        HStack(spacing: 6) {
            FileIconView(name: (path as NSString).lastPathComponent)
            Text((path as NSString).lastPathComponent)
                .italic(preview)
                .lineLimit(1)
            // a dot for unsaved changes, the close button while hovering (like VS Code)
            Button { editors.requestClose(path, in: session) } label: {
                Image(systemName: dirty && !hover ? "circle.fill" : "xmark")
                    .font(.system(size: dirty && !hover ? 7 : 9, weight: .bold))
                    .frame(width: 14, height: 14)
                    .opacity(hover || active || dirty ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help(dirty ? "Unsaved changes – close" : "Close (⌘W)")
        }
        .padding(.horizontal, 10).frame(height: 32)
        // the active tab joins the editor below it, in the editor's background
        .background(active ? Color(hex: theme.palette(dark: scheme == .dark).background) : .clear)
        .overlay(alignment: .top) { if active { Rectangle().fill(Color.accentColor).frame(height: 2) } }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { editors.pin(path, in: session) }
        .onTapGesture { editors.activate(path, in: session) }
        .help(path + (preview ? " (preview – double-click to keep open)" : ""))
    }
}

/// One file: editable text (Markdown with a preview), an image, or VS Code's placeholders for binary, large
/// and missing files. Shows the save conflict banner when needed.
struct DocumentView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject var model: DocumentModel
    let session: String
    @AppStorage("markdownPreview") private var markdownPreview = false
    @State private var comparing = false

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider()
            if model.conflict { conflictBanner; Divider() }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $comparing) { CompareSheet(model: model) }
    }

    @ViewBuilder
    private var content: some View {
        if model.isImage {
            if let img = NSImage(contentsOfFile: model.path) {
                ScrollView([.horizontal, .vertical]) { Image(nsImage: img).padding(20) }
            } else {
                placeholder("photo", "Can't show this image.", anyway: false)
            }
        } else {
            switch model.doc.load {
            case .text:
                if FileContent.isMarkdown(model.path) && markdownPreview {
                    ScrollView {
                        Markdown(model.doc.text).markdownTheme(.gitHub).textSelection(.enabled)
                            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    CodeEditor(model: model, session: session)
                }
            case .binary:
                placeholder("doc.questionmark", "The file is not displayed in the editor because it is either binary or uses an unsupported text encoding.", anyway: true)
            case .tooLarge(let size):
                placeholder("doc.badge.ellipsis", "The file is not displayed in the editor because it is very large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))).", anyway: true)
            case .missing:
                placeholder("trash", "The file was deleted or moved.", anyway: false)
            case .unreadable(let why):
                placeholder("exclamationmark.triangle", why, anyway: false)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            (Text(abbreviated((model.path as NSString).deletingLastPathComponent) + "/").foregroundColor(.secondary.opacity(0.6))
                + Text(model.name).foregroundColor(.secondary))
                .lineLimit(1).truncationMode(.head)
            Spacer()
            if model.doc.isDirty { Text("Edited").font(.caption).foregroundStyle(.secondary) }
            if FileContent.isMarkdown(model.path) && model.doc.load == .text {
                Picker("", selection: $markdownPreview) {
                    Text("Edit").tag(false)
                    Text("Preview").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 130).labelsHidden()
            }
            Menu {
                EditorThemePicker().pickerStyle(.inline)
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Theme")
            Button { EditorStore.shared.save(model.path) } label: { Image(systemName: "square.and.arrow.down") }
                .help("Save (⌘S)").disabled(!model.doc.isDirty)
            Button { store.insertIntoTerminal("@\(model.path) ") } label: { Image(systemName: "at") }
                .help("Insert @path into the terminal").disabled(store.selectedRow?.tmux == nil)
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: model.path)) } label: { Image(systemName: "arrow.up.forward.app") }
                .help("Open with the default app")
        }
        .font(.callout)
        .buttonStyle(.borderless)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// VS Code: "Failed to save: The content of the file is newer." with Compare and Overwrite.
    private var conflictBanner: some View {
        let message = HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.block)
            VStack(alignment: .leading, spacing: 1) {
                Text("Failed to save “\(model.name)”").fontWeight(.semibold)
                Text("The file on disk is newer. Compare, overwrite it with yours, or revert to it.")
                    .foregroundStyle(.secondary)
            }
        }
        let buttons = HStack {
            Button("Compare") { comparing = true }
            Button("Overwrite") { EditorStore.shared.save(model.path, overwrite: true) }
            Button("Revert") { EditorStore.shared.revert(model.path) }
                .help("Discard your changes and load the file from disk")
        }
        // one row when it fits, the buttons below the message when the editor is narrow
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { message.fixedSize(); Spacer(); buttons }
            VStack(alignment: .leading, spacing: 8) { message.fixedSize(horizontal: false, vertical: true); buttons }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.block.opacity(0.12))
    }

    private func placeholder(_ symbol: String, _ text: String, anyway: Bool) -> some View {
        ContentUnavailableView {
            Label { Text(text).font(.body) } icon: { Image(systemName: symbol) }
        } actions: {
            if anyway { Button("Open Anyway") { model.openAnyway() } }
            Button("Open with Default App") { NSWorkspace.shared.open(URL(fileURLWithPath: model.path)) }
        }
    }
}

/// "<file> (on disk) ↔ (yours)": both versions side by side, then keep one.
private struct CompareSheet: View {
    @ObservedObject var model: DocumentModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.name) (on disk) ↔ (yours) – resolve save conflict").font(.headline)
                Spacer()
            }
            .padding(12)
            Divider()
            HStack(spacing: 0) {
                pane("On disk", model.doc.diskText())
                Divider()
                pane("Yours", model.doc.text)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Keep Disk Version") { EditorStore.shared.revert(model.path); dismiss() }
                Button("Overwrite with Mine") { EditorStore.shared.save(model.path, overwrite: true); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private func pane(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(8)
            CodeTextView(text: text)
        }
    }
}

/// Editable source text: NSTextView with line numbers, undo, find (⌘F), no smart quotes, in the editor theme.
struct CodeEditor: NSViewRepresentable {
    @ObservedObject var model: DocumentModel
    let session: String
    @ObservedObject private var editors = EditorStore.shared
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @Environment(\.colorScheme) private var scheme

    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    private var palette: EditorPalette { theme.palette(dark: scheme == .dark) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: DocumentModel
        var focusSeen = 0
        var palette: EditorPalette?
        let language: SyntaxTokens.Language?
        private var coloring = false
        init(model: DocumentModel, language: SyntaxTokens.Language?) {
            self.model = model
            self.language = language
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let text = tv.string
            MainActor.assumeIsolated {
                model.doc.text = text
                EditorStore.shared.edited(model.path)
                recolor(tv)
            }
        }

        /// Once per run loop pass, however many edits came in (pasting, undo of many steps).
        @MainActor func recolor(_ tv: NSTextView) {
            guard !coloring, let palette else { return }
            coloring = true
            DispatchQueue.main.async { [weak self, weak tv] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.coloring = false
                    if let tv { SyntaxColoring.apply(tv, palette: palette, language: self.language) }
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model, language: SyntaxTokens.language(for: model.path)) }

    func makeNSView(context: Context) -> NSScrollView {
        // Apple's recipe for a text view in a scroll view, with our subclass that draws the line numbers
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        // a real starting size: text laid out at width 0 (the scroll view's size before layout) never drew
        let size = NSSize(width: 600, height: 400)
        scroll.frame = NSRect(origin: .zero, size: size)
        // TextKit 1 from the start: the gutter uses `layoutManager`, and touching it on a TextKit 2 view switches
        // it over mid-draw, after which it neither drew its text nor took input
        let tv = GutterTextView(usingTextLayoutManager: false)
        tv.frame = NSRect(origin: .zero, size: size)
        tv.minSize = .zero
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = NSSize(width: size.width, height: .greatestFiniteMagnitude)
        tv.textContainer?.widthTracksTextView = true
        scroll.documentView = tv
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.font = Self.font
        tv.textContainerInset = NSSize(width: GutterTextView.gutter, height: 6)
        Self.style(tv, scroll: scroll, palette)
        context.coordinator.palette = palette
        Self.setText(tv, model.doc.text, palette)
        SyntaxColoring.apply(tv, palette: palette, language: context.coordinator.language)
        tv.delegate = context.coordinator
        context.coordinator.focusSeen = editors.focusRequest
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let palette = palette
        // another theme, or the appearance changed under Automatic
        if context.coordinator.palette != palette {
            context.coordinator.palette = palette
            Self.style(tv, scroll: scroll, palette)
            tv.textStorage?.addAttribute(.foregroundColor, value: palette.ns(palette.foreground),
                                         range: NSRange(location: 0, length: (tv.string as NSString).length))
            SyntaxColoring.apply(tv, palette: palette, language: context.coordinator.language)
            tv.needsDisplay = true
        }
        // reloaded from disk (or reverted): take the new text, keep the selection and scroll position
        if tv.string != model.doc.text {
            let sel = tv.selectedRanges
            let origin = scroll.contentView.bounds.origin
            Self.setText(tv, model.doc.text, palette)
            SyntaxColoring.apply(tv, palette: palette, language: context.coordinator.language)
            let length = (tv.string as NSString).length
            tv.selectedRanges = sel.map { r in
                let range = r.rangeValue
                return NSValue(range: NSRange(location: min(range.location, length), length: 0))
            }
            scroll.contentView.scroll(to: origin)
            scroll.reflectScrolledClipView(scroll.contentView)
            tv.needsDisplay = true
        }
        if context.coordinator.focusSeen != editors.focusRequest {
            context.coordinator.focusSeen = editors.focusRequest
            // after the double click has finished, or the tree takes the focus back with its second click
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { tv.window?.makeFirstResponder(tv) }
        }
    }

    /// Take exactly the space offered; the text scrolls inside.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 400)
    }

    /// Background, cursor, selection and line numbers in the theme's colors.
    static func style(_ tv: NSTextView, scroll: NSScrollView, _ p: EditorPalette) {
        tv.backgroundColor = p.ns(p.background)
        scroll.backgroundColor = p.ns(p.background)
        tv.insertionPointColor = p.ns(p.cursor)
        tv.selectedTextAttributes = [.backgroundColor: p.ns(p.selection)]
        tv.typingAttributes = [.font: font, .foregroundColor: p.ns(p.foreground)]
        // the scrollers follow the theme, not the app (a dark theme in a light app)
        scroll.appearance = NSAppearance(named: p.dark ? .darkAqua : .aqua)
        (tv as? GutterTextView)?.gutterColor = p.ns(p.gutter)
    }

    /// Replaces the text with explicit font and color. (`string =` gave loaded text no color: black on a dark
    /// background, until the first keystroke redrew it with the typing attributes.)
    static func setText(_ tv: NSTextView, _ text: String, _ p: EditorPalette) {
        tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: p.ns(p.foreground),
        ]))
        tv.needsDisplay = true
    }
}

/// NSTextView that draws line numbers in its own left inset. (An NSRulerView broke the SwiftUI layout: the
/// scroll view overlapped the views above it and the text didn't draw.)
final class GutterTextView: NSTextView {
    static let gutter: CGFloat = 44
    var gutterColor: NSColor = .tertiaryLabelColor {
        didSet { needsDisplay = true }
    }
    private var attrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: gutterColor]
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let text = string as NSString
        let origin = textContainerOrigin
        func draw(_ n: Int, _ frag: NSRect) {
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: Self.gutter - size.width - 10, y: origin.y + frag.minY + (frag.height - size.height) / 2),
                       withAttributes: attrs)
        }
        guard text.length > 0 else {
            draw(1, lm.extraLineFragmentRect.height > 0 ? lm.extraLineFragmentRect : NSRect(x: 0, y: 0, width: 0, height: 15))
            return
        }
        // the lines in the dirty rect, numbered from the start of the text
        let glyphs = lm.glyphRange(forBoundingRect: rect.offsetBy(dx: 0, dy: -origin.y), in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: chars.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in line += 1 }
        var index = text.lineRange(for: NSRange(location: chars.location, length: 0)).location
        while index < NSMaxRange(chars) {
            draw(line, lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: index), effectiveRange: nil))
            line += 1
            let next = NSMaxRange(text.lineRange(for: NSRange(location: index, length: 0)))
            if next <= index { break }
            index = next
        }
        // the empty line after a final newline
        if index >= text.length, text.hasSuffix("\n"), lm.extraLineFragmentRect.height > 0 {
            draw(line, lm.extraLineFragmentRect)
        }
    }


    /// Numbers must follow edits, also for lines below the edited one.
    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }
}
