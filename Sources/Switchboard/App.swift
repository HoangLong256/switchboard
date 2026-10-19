import AppKit
import SessionCore
import SwiftUI

@main
struct SwitchboardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()
    @StateObject private var usage = UsageStore()

    var body: some Scene {
        WindowGroup("Switchboard") {
            ContentView()
                .environmentObject(store)
                .environmentObject(usage)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .defaultSize(width: 1360, height: 860)
        .windowToolbarStyle(.unified)
        Settings { SettingsView() }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { store.newSessionOpen = true }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { if let p = activeFile { EditorStore.shared.save(p) } }
                    .keyboardShortcut("s").disabled(activeFile == nil)
                Button("Save All") { for m in EditorStore.shared.dirtyDocuments { EditorStore.shared.save(m.path) } }
                    .keyboardShortcut("s", modifiers: [.command, .option])
                Divider()
                // like VS Code, ⌘W closes the editor while the Editor tab is showing, otherwise the window
                Button(store.tab == .editor && activeFile != nil ? "Close Editor" : "Close Window") {
                    if store.tab == .editor, let p = activeFile, let s = store.selected {
                        EditorStore.shared.requestClose(p, in: s)
                    } else {
                        NSApp.keyWindow?.performClose(nil)
                    }
                }
                .keyboardShortcut("w")
                // VS Code: ⌥⌘T closes the other editors; ⌥⌘W is macOS's "close all"
                Button("Close Other Editors") {
                    if let p = activeFile, let s = store.selected { EditorStore.shared.closeOthers(p, in: s) }
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(store.tab != .editor || EditorStore.shared.tabs(of: store.selected).paths.count < 2)
                Button("Close All Editors") { if let s = store.selected { EditorStore.shared.closeAll(in: s) } }
                    .keyboardShortcut("w", modifiers: [.command, .option])
                    .disabled(store.tab != .editor || activeFile == nil)
            }
            TextEditingCommands()
            CommandGroup(after: .sidebar) {
                Picker("Appearance", selection: Binding(get: { AppSettings.shared.appearance },
                                                        set: { AppSettings.shared.appearance = $0 })) {
                    Text("System").tag(Appearance.system).keyboardShortcut("0", modifiers: [.command, .option])
                    Text("Light").tag(Appearance.light).keyboardShortcut("l", modifiers: [.command, .option])
                    Text("Dark").tag(Appearance.dark).keyboardShortcut("d", modifiers: [.command, .option])
                }
                EditorThemePicker()
                Picker("File Icon Theme", selection: Binding(
                    get: { IconTheme(rawValue: UserDefaults.standard.string(forKey: "iconTheme") ?? "") ?? .seti },
                    set: { UserDefaults.standard.set($0.rawValue, forKey: "iconTheme") })) {
                    ForEach(IconTheme.allCases) { Text($0.title).tag($0) }
                }
                Divider()
            }
            CommandMenu("Session") {
                Button("Next Waiting Session") { store.jumpToWaiting() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Focus Terminal") { store.focusTerminal() }.keyboardShortcut("j")
                Divider()
                ForEach(Array(DetailTab.allCases.enumerated()), id: \.element) { i, tab in
                    Button(tab.rawValue) { store.tab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                        .disabled(tab == .editor && EditorStore.shared.tabs(of: store.selected).paths.isEmpty)
                }
                Divider()
                Button("Toggle Favorite") { if let s = store.selected { store.toggleFavorite(s) } }
                    .keyboardShortcut("d").disabled(store.selected == nil)
                Button("Refresh") { Task { await store.refresh() } }.keyboardShortcut("r")
            }
        }
    }
}

extension SwitchboardApp {
    private var activeFile: String? { EditorStore.shared.tabs(of: store.selected).active }
}

/// The Dock icon, drawn from `AppMark`. `Switchboard --export-icon <dir.iconset>` writes the PNG sizes for
/// `iconutil` (scripts/bundle.sh), so the bundle's icon and the in-app mark are the same drawing.
@MainActor
enum AppIcon {
    static func image(size: CGFloat) -> NSImage? {
        // macOS icon grid: the shape takes about 80 % of the canvas
        // Auto: the theme of the app's current appearance
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let r = ImageRenderer(content: AppMark(size: size * 0.8, style: IconStyle.current.resolved(dark: dark), tint: .current)
            .frame(width: size, height: size))
        r.scale = 1
        return r.nsImage
    }

    static func export(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                guard let img = image(size: CGFloat(base * scale)), let tiff = img.tiffRepresentation,
                      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appearanceObserver: NSKeyValueObservation?
    func applicationWillFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--export-icon-sheet"), i + 1 < args.count {
            MainActor.assumeIsolated {
                let r = ImageRenderer(content: IconSheet())
                r.scale = 2
                if let tiff = r.nsImage?.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: args[i + 1]))
                }
            }
            exit(0)
        }
        if let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
            MainActor.assumeIsolated { AppIcon.export(to: args[i + 1]) }
            exit(0)
        }
    }

    /// Unsaved files: Save All / Don't Save / Cancel before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let dirty = EditorStore.shared.dirtyDocuments
            guard !dirty.isEmpty else { return .terminateNow }
            let a = NSAlert()
            a.messageText = dirty.count == 1
                ? "Do you want to save the changes you made to \(dirty[0].name)?"
                : "Do you want to save the changes to the following \(dirty.count) files?"
            a.informativeText = (dirty.count > 1 ? dirty.map(\.name).joined(separator: "\n") + "\n\n" : "")
                + "Your changes will be lost if you don't save them."
            a.addButton(withTitle: dirty.count == 1 ? "Save" : "Save All")
            a.addButton(withTitle: "Cancel")
            a.addButton(withTitle: "Don't Save")
            switch a.runModal() {
            case .alertFirstButtonReturn:
                let ok = dirty.allSatisfy { EditorStore.shared.save($0.path) }
                return ok ? .terminateNow : .terminateCancel   // a conflict shows its banner instead
            case .alertThirdButtonReturn: return .terminateNow
            default: return .terminateCancel
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // started with `swift run`: become a regular app with a Dock icon and a key window
        NSApp.setActivationPolicy(.regular)
        MainActor.assumeIsolated { NSApp.applicationIconImage = AppIcon.image(size: 512) }
        // macOS switching between light and dark (appearance "System") updates the Auto icon
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { NSApp.applicationIconImage = AppIcon.image(size: 512) }
        }
        MainActor.assumeIsolated { AppSettings.shared.applyAppearance() }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Sessions | folder of the selected session | terminal, file, handover, notes, info.
struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var columns = NavigationSplitViewVisibility.all
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SessionList()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } content: {
            FolderSidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 460)
        } detail: {
            DetailView()
        }
        .tint(theme.themesApp ? Color(hex: theme.palette(dark: true).accent) : nil)
        .background(ToolbarTipsInstaller())
        .onChange(of: theme) { AppSettings.shared.applyAppearance() }
        .navigationTitle("Switchboard")
        // the session's name is in the header; the toolbar stays clean
        .hidingToolbarTitle()
        .sheet(isPresented: $store.newSessionOpen) { NewSessionSheet() }
        .alert("Switchboard", isPresented: Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
        .confirmationDialog("Move “\(store.moveRequest?.name ?? "")” into Switchboard?",
                            isPresented: Binding(get: { store.moveRequest != nil }, set: { if !$0 { store.moveRequest = nil } }),
                            presenting: store.moveRequest) { row in
            Button("Move") { Task { await store.moveIn(row) } }
            Button("Cancel", role: .cancel) {}
        } message: { row in
            Text(moveMessage(row))
        }
    }

    private func moveMessage(_ row: Row) -> String {
        let app = row.session.pid.flatMap(MoveIn.hostApp(of:)) ?? "its terminal"
        var m = "It ends in \(app), and the same conversation continues here in a new terminal (claude --resume)."
        if row.session.status == "busy" { m += " It is still working: the current step stops." }
        return m
    }
}

struct NewSessionSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder = UserDefaults.standard.string(forKey: "lastFolder") ?? NSHomeDirectory()
    @AppStorage("newSessionAgentTeam") private var agentTeam = false
    @AppStorage("newSessionStartClaude") private var startClaude = true
    /// the name last filled in from the folder; replaced when the folder changes, unless you typed your own
    @State private var suggested = ""

    private var valid: Bool { Notes.validName(name) && !name.hasPrefix(".") && !store.rows.contains { $0.name == name } }

    var body: some View {
        Form {
            TextField("Name", text: $name, prompt: Text("myapp.01"))
            LabeledContent("Folder") {
                HStack {
                    Text(abbreviated(folder)).lineLimit(1).truncationMode(.head)
                    Button("Choose…", action: choose)
                }
            }
            Toggle(isOn: $agentTeam) {
                Text("Agent team (experimental)")
                Text("Sets CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 for this session only, so Claude can split work across teammates. They show up under the session and in its Team tab.")
            }
            Toggle(isOn: $startClaude) {
                Text("Start Claude right away")
                Text("Opens a shell in Switchboard's tmux server and runs `claude -n \(name.isEmpty ? "<name>" : name)` in it. Off: the command is only typed in, so you can change it before pressing Enter.")
            }
            if !name.isEmpty && !valid {
                Text("Use letters, digits and . _ # - (unique, no “..”).").font(.caption).foregroundStyle(Palette.need)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { suggestName() }
        .onChange(of: folder) { suggestName() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    UserDefaults.standard.set(folder, forKey: "lastFolder")
                    let (n, f, team, start) = (name, folder, agentTeam, startClaude)
                    dismiss()
                    Task { await store.startSession(name: n, folder: f, agentTeam: team, start: start) }
                }
                .disabled(!valid)
            }
        }
    }

    /// The folder's name as the session name, while the field is empty or still holds the last suggestion.
    private func suggestName() {
        guard name.isEmpty || name == suggested else { return }
        suggested = Notes.suggestedName(folder: folder, taken: Set(store.rows.map(\.name)))
        name = suggested
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: folder)
        if panel.runModal() == .OK, let url = panel.url { folder = url.path }
    }
}
