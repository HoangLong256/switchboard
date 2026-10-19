import SessionCore
import SwiftUI

/// Settings (⌘,): keep the Mac awake, and continue sessions after a usage limit.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var awake = KeepAwake.shared
    @ObservedObject private var resume = AutoContinue.shared
    @AppStorage("editorTheme") private var editorTheme: EditorTheme = .automatic
    @AppStorage("sessionsGrouping") private var grouping: SessionGrouping = .none
    @AppStorage("showModelInTabs") private var showModel = true
    @AppStorage("iconTheme") private var iconTheme: IconTheme = .seti
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { a in Label(a.title, systemImage: a.symbol).tag(a) }
                }
                .pickerStyle(.segmented)
                .disabled(editorTheme.themesApp)
                .help(editorTheme.themesApp ? "Set by the theme \(editorTheme.title)" : "")
                LabeledContent("App Icon") {
                    HStack(spacing: 10) {
                        ForEach(IconStyle.allCases) { s in
                            Button { settings.iconStyle = s } label: {
                                AppMark(size: 34, style: s)
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .strokeBorder(settings.iconStyle == s ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .help(s.title)
                        }
                    }
                }
                if [.switchesAuto, .switchesPaper, .switchesTerminal].contains(settings.iconStyle) {
                    Picker("Icon Color", selection: $settings.switchTint) {
                        ForEach(SwitchTint.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Sessions") {
                Picker("Group by", selection: $grouping) {
                    ForEach(SessionGrouping.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show model and effort next to the session's tabs", isOn: $showModel)
            }

            Section {
                LabeledContent("Theme") {
                    HStack(spacing: 10) {
                        ThemeSwatches(palette: editorTheme.palette(dark: scheme == .dark))
                        Picker("Theme", selection: $editorTheme) {
                            ForEach(EditorTheme.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                Picker("File Icons", selection: $iconTheme) {
                    ForEach(IconTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Theme")
            } footer: {
                Text("Colors the app, the editor and the terminal like the VS Code theme of the same name. A theme is light or dark by itself, so it takes over from Appearance. Automatic keeps the macOS look, with Light Modern or Dark Modern in the editor and terminal.")
            }

            Section {
                Toggle("Keep the Mac awake while sessions are working", isOn: $settings.keepAwake)
                Toggle("Keep the display on too", isOn: $settings.keepDisplayOn).disabled(!settings.keepAwake)
                Toggle("Also while a session waits to be continued after a usage limit", isOn: $settings.awakeForResume)
                    .disabled(!settings.keepAwake)
                LabeledContent("Now", value: awake.reason?.replacingOccurrences(of: "Switchboard: ", with: "Awake – ") ?? "Sleeping as usual")
            } header: {
                Text("Keep Awake")
            } footer: {
                Text("Like caffeinate: prevents idle sleep while any session works, and lets the Mac sleep again as soon as none does. Closing the lid still sleeps a MacBook on battery.")
            }

            Section {
                Toggle("Continue sessions when their usage limit resets", isOn: $settings.autoContinue)
                TextField("Message", text: $settings.continueMessage, prompt: Text("continue"))
                    .disabled(!settings.autoContinue)
                if !resume.pending.isEmpty {
                    ForEach(resume.pending.values.sorted { $0.name < $1.name }, id: \.name) { p in
                        LabeledContent(p.name, value: describe(p))
                    }
                }
                ForEach(resume.log.prefix(5), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("Usage Limits")
            } footer: {
                Text("When a session stops with “You've hit your session limit · resets …”, Switchboard types the message into it a minute after the reset. Only for sessions running in Switchboard's tmux, and only if nobody wrote to the session since.")
            }

            Section {
                Toggle("Start new sessions with Claude Code's unattended retry", isOn: $settings.retryWatchdog)
                Picker("Longest wait for a limit", selection: $settings.watchdogMaxHours) {
                    Text("6 hours (covers the 5-hour limit)").tag(6)
                    Text("1 day").tag(24)
                    Text("No limit (also waits out the weekly limit)").tag(0)
                }
                .disabled(!settings.retryWatchdog)
            } footer: {
                Text("Sets CLAUDE_CODE_RETRY_WATCHDOG=1 for sessions started with ⌘N: Claude Code then waits at a usage limit itself and carries on with the same request when it resets, without a new message. Sessions started elsewhere use the option above.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func describe(_ p: AutoContinue.Pending) -> String {
        let when = p.resetAt.map { "resets \($0.formatted(date: .omitted, time: .shortened))" } ?? "reset unknown"
        return p.willContinue ? "\(when) · continues then" : "\(when) · not continued: \(p.reasonNot ?? "")"
    }
}

/// Two quick switches at the bottom of the sessions column: keep awake and auto-continue, with what they do now.
struct PowerToggles: View {
    @ObservedObject private var settings = AppSettings.shared
    @AppStorage("editorTheme") private var theme: EditorTheme = .automatic
    @ObservedObject private var awake = KeepAwake.shared
    @ObservedObject private var resume = AutoContinue.shared

    var body: some View {
        HStack(spacing: 6) {
            chip(on: $settings.keepAwake, symbol: "cup.and.saucer",
                 title: "Keep awake", active: awake.reason != nil,
                 help: awake.reason ?? (settings.keepAwake ? "Keeps the Mac awake while sessions work" : "Keep Awake is off"))
            chip(on: $settings.autoContinue, symbol: "arrow.clockwise", title: "Auto-continue",
                 active: resume.pending.values.contains(where: \.willContinue),
                 help: settings.autoContinue ? "Continues sessions when their usage limit resets" : "Auto-continue is off")
            Spacer()
            // System → Light → Dark
            Button {
                let all = Appearance.allCases
                settings.appearance = all[(all.firstIndex(of: settings.appearance)! + 1) % all.count]
            } label: { Image(systemName: settings.appearance.symbol) }
            .buttonStyle(.borderless)
            .disabled(theme.themesApp)
            .help(theme.themesApp ? "Appearance is set by the theme \(theme.title)"
                  : "Appearance: \(settings.appearance.title) – click for \(next.title)")
            SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings (⌘,)")
        }
        .font(.caption)
    }

    private var next: Appearance {
        let all = Appearance.allCases
        return all[(all.firstIndex(of: settings.appearance)! + 1) % all.count]
    }

    /// A small checkbox-like switch: icon filled while it acts, plain text otherwise.
    private func chip(on: Binding<Bool>, symbol: String, title: String, active: Bool, help: String) -> some View {
        Toggle(isOn: on) {
            Text(title).foregroundStyle(active ? .primary : .secondary)
        }
        .toggleStyle(.checkbox)
        .controlSize(.small)
        .help(help)
    }
}
