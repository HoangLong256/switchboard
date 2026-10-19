import Foundation

/// Short names for model ids, as Claude Code shows them: "claude-opus-5-5" → "Opus 5.5",
/// "claude-haiku-4-5-20251001" → "Haiku 4.5", "claude-sonnet-5-5[1m]" → "Sonnet 5.5 (1M)".
public enum ModelName {
    public static func short(_ id: String) -> String {
        var s = id.trimmingCharacters(in: .whitespaces)
        var suffix = ""
        if let r = s.range(of: "[1m]", options: [.caseInsensitive, .backwards]) {
            s.removeSubrange(r)
            suffix = " (1M)"
        }
        // only rewrite ids, not names Claude Code already displays ("Opus 5.5")
        guard s.hasPrefix("claude-") else { return id }
        var parts = s.dropFirst("claude-".count).split(separator: "-").map(String.init)
        // a date at the end ("20251001")
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, !family.isEmpty else { return id }
        let version = parts.dropFirst().filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return (version.isEmpty ? name : "\(name) \(version)") + suffix
    }
}
