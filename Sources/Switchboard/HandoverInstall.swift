import Foundation
import SessionCore

/// Sets up `switchboard-task` so Claude keeps each session's handover: copies the helper to `~/.switchboard/bin`,
/// adds a marked section to `~/.claude/CLAUDE.md` and a permission rule to `~/.claude/settings.json`. Only on
/// request, with timestamped backups of both files; `uninstall()` takes it all out again.
enum HandoverInstall {
    static let installedHelper = "\(UsageStore.dataDir)/bin/switchboard-task"
    static let claudeMdPath = "\(StateBuilder.defaultClaudeHome)/CLAUDE.md"
    static var settingsPath: String { StatusLineSetup.settingsPath }

    /// The helper built next to the app's executable (`.build/<config>/` or `Switchboard.app/Contents/MacOS/`).
    static var bundledHelper: String? {
        let p = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("switchboard-task").path
        return p.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
    }

    static var isInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: installedHelper),
              let md = try? String(contentsOfFile: claudeMdPath, encoding: .utf8) else { return false }
        return HandoverSetup.hasInstructions(md)
    }

    /// Returns an error message, nil on success.
    static func install() -> String? {
        guard let helper = bundledHelper else {
            return "switchboard-task wasn't found next to the app. Build it with `swift build` or scripts/bundle.sh."
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: (installedHelper as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if fm.fileExists(atPath: installedHelper) { try fm.removeItem(atPath: installedHelper) }
            try fm.copyItem(atPath: helper, toPath: installedHelper)
            if let err = try editSettings({ HandoverSetup.addingAllow($0, rule: HandoverSetup.allowRule(helper: installedHelper)) }) {
                return err
            }
            try editClaudeMd { HandoverSetup.addingInstructions(to: $0, helper: installedHelper) }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func uninstall() -> String? {
        do {
            if let err = try editSettings({ HandoverSetup.removingAllow($0, rule: HandoverSetup.allowRule(helper: installedHelper)) }) {
                return err
            }
            try editClaudeMd { HandoverSetup.removingInstructions(from: $0) }
            try? FileManager.default.removeItem(atPath: installedHelper)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func backup(_ path: String, _ data: Data) throws {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        try data.write(to: URL(fileURLWithPath: "\(path).switchboard-backup-\(f.string(from: Date()))"))
    }

    /// nil, or a message when settings.json isn't JSON (then nothing changes).
    private static func editSettings(_ change: ([String: Any]) -> [String: Any]) throws -> String? {
        var settings: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: settingsPath) {
            guard let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return "~/.claude/settings.json isn't valid JSON; nothing was changed."
            }
            settings = j
            try backup(settingsPath, data)
        }
        let out = try JSONSerialization.data(withJSONObject: change(settings), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
        return nil
    }

    private static func editClaudeMd(_ change: (String) -> String) throws {
        let old = FileManager.default.contents(atPath: claudeMdPath)
        if let old { try backup(claudeMdPath, old) }
        let text = change(old.map { String(decoding: $0, as: UTF8.self) } ?? "")
        try FileManager.default.createDirectory(atPath: (claudeMdPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try text.write(toFile: claudeMdPath, atomically: true, encoding: .utf8)
    }
}
