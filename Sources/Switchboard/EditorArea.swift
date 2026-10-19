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
            } else {
                ContentUnavailableView("No open file", systemImage: "doc.text",
                                       description: Text("Click a file in the folder sidebar to preview it; double-click to keep it open."))
            }
        }
        .alert("Do you want to save the changes you made to \(closeName)?", isPresented: closeBinding) {
            Button("Save") { closeDirty(save: true) }
            Button("Don't Save", role: .destructive) { closeDirty(save: false) }
            Button("Cancel", role: .cancel) { editors.closeRequest = nil }
        } message: {
            Text("Your changes will be lost if you don't save them.")
        }
    }

    private var closeName: String { ((editors.closeRequest?.path ?? "") as NSString).lastPathComponent }

    private var closeBinding: Binding<Bool> {
        Binding(get: { editors.closeRequest?.session == session }, set: { if !$0 { editors.closeRequest = nil } })
    }

    private func closeDirty(save: Bool) {
        guard let r = editors.closeRequest else { return }
        editors.closeRequest = nil
        if save, !editors.save(r.path) { return }   // conflict or error: keep the tab open
        if !save { editors.revert(r.path) }
        editors.close(r.path, in: r.session)
    }
}

private struct TabStrip: View {
    @ObservedObject private var editors = EditorStore.shared
    let session: String
    let tabs: EditorTabs

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(tabs.paths, id: \.self) { path in
                    if let m = editors.documents[path] {
                        TabItem(model: m, session: session, active: tabs.active == path, preview: tabs.preview == path)
                    }
                    Divider().frame(height: 18)
                }
            }
        }
        .frame(height: 32)
        .background(.bar)
    }
}

private struct TabItem: View {
    @ObservedObject private var editors = EditorStore.shared
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
            Image(systemName: "doc.text").font(.caption).foregroundStyle(.secondary)
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
        .background(active ? Color(nsColor: .textBackgroundColor) : .clear)
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

/// Editable source text: NSTextView with line numbers, undo, find (⌘F), no smart quotes.
struct CodeEditor: NSViewRepresentable {
    @ObservedObject var model: DocumentModel
    let session: String
    @ObservedObject private var editors = EditorStore.shared

    static let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)

    final class Coordinator: NSObject, NSTextViewDelegate {
        var model: DocumentModel
        var focusSeen = 0
        init(model: DocumentModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            let text = tv.string
            MainActor.assumeIsolated {
                model.doc.text = text
                EditorStore.shared.edited(model.path)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

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
        tv.textColor = .textColor
        tv.backgroundColor = .textBackgroundColor
        tv.insertionPointColor = .textColor
        tv.typingAttributes = [.font: Self.font, .foregroundColor: NSColor.textColor]
        tv.textContainerInset = NSSize(width: GutterTextView.gutter, height: 6)
        Self.setText(tv, model.doc.text)
        tv.delegate = context.coordinator
        context.coordinator.focusSeen = editors.focusRequest
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        // reloaded from disk (or reverted): take the new text, keep the selection and scroll position
        if tv.string != model.doc.text {
            let sel = tv.selectedRanges
            let origin = scroll.contentView.bounds.origin
            Self.setText(tv, model.doc.text)
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

    /// Replaces the text with explicit font and color. (`string =` gave loaded text no color: black on a dark
    /// background, until the first keystroke redrew it with the typing attributes.)
    static func setText(_ tv: NSTextView, _ text: String) {
        tv.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.textColor,
        ]))
        tv.needsDisplay = true
    }
}

/// NSTextView that draws line numbers in its own left inset. (An NSRulerView broke the SwiftUI layout: the
/// scroll view overlapped the views above it and the text didn't draw.)
final class GutterTextView: NSTextView {
    static let gutter: CGFloat = 44
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor.tertiaryLabelColor,
    ]

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lm = layoutManager, let tc = textContainer else { return }
        let text = string as NSString
        let origin = textContainerOrigin
        func draw(_ n: Int, _ frag: NSRect) {
            let label = "\(n)" as NSString
            let size = label.size(withAttributes: Self.attrs)
            label.draw(at: NSPoint(x: Self.gutter - size.width - 10, y: origin.y + frag.minY + (frag.height - size.height) / 2),
                       withAttributes: Self.attrs)
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
