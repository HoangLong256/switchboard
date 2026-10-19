import Foundation

/// Claude Code's status line hands every session's state to a command as JSON on stdin (on each update).
/// `switchboard-statusline` keeps what Switchboard shows and prints a short line for the terminal:
///
/// - `<data>/usage.json`: plan limits, `{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":<epoch s>},
///   "seven_day":{…}},"written_at":<epoch s>}`, the format `PlanLimits.fromStatusLine` reads
/// - `<data>/context/<session>.json`: `{"used_percentage":37,"written_at":…}` (`ContextUsage`)
/// - `<data>/sessions/<session>.json`: cost, model, effort, tokens in context, lines changed
public enum StatusLine {
    public struct Output: Equatable {
        /// relative path below the data folder → JSON object
        public var files: [String: [String: Any]]
        public var line: String

        public static func == (a: Output, b: Output) -> Bool {
            a.line == b.line && a.files.keys.sorted() == b.files.keys.sorted()
                && a.files.allSatisfy { k, v in NSDictionary(dictionary: v).isEqual(to: b.files[k] ?? [:]) }
        }
    }

    /// Same rule as session names: no path can lead out of the folder.
    static func safe(_ id: String) -> Bool {
        !id.isEmpty && !id.contains("..") && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }

    public static func process(_ input: Data, now: Date = Date()) -> Output {
        guard let j = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any] else {
            return Output(files: [:], line: "")
        }
        let written = now.timeIntervalSince1970.rounded()
        var files: [String: [String: Any]] = [:]
        var parts: [String] = []

        let model = (j["model"] as? [String: Any])?["display_name"] as? String
            ?? (j["model"] as? [String: Any])?["id"] as? String
        if let model { parts.append(model) }

        // plan limits are the same for every session; whichever reports last wins
        if let limits = j["rate_limits"] as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, label) in [("five_hour", "5h"), ("seven_day", "wk")] {
                guard let w = limits[key] as? [String: Any], let p = number(w["used_percentage"]) else { continue }
                var o: [String: Any] = ["used_percentage": p]
                if let r = epoch(w["resets_at"]) { o["resets_at"] = r }
                out[key] = o
                parts.append("\(label) \(Int(p.rounded()))%")
            }
            if !out.isEmpty { files["usage.json"] = ["rate_limits": out, "written_at": written] }
        }

        let ctx = j["context_window"] as? [String: Any]
        let ctxPercent = number(ctx?["used_percentage"])
        if let p = ctxPercent { parts.insert("ctx \(Int(p.rounded()))%", at: min(1, parts.count)) }

        let cost = j["cost"] as? [String: Any]
        if let sid = j["session_id"] as? String, safe(sid) {
            if let p = ctxPercent { files["context/\(sid).json"] = ["used_percentage": p, "written_at": written] }
            var s: [String: Any] = ["written_at": written]
            if let model { s["model"] = model }
            if let v = number(cost?["total_cost_usd"]) { s["cost_usd"] = v }
            if let v = number(cost?["total_duration_ms"]) { s["duration_ms"] = v }
            if let v = number(cost?["total_lines_added"]) { s["lines_added"] = v }
            if let v = number(cost?["total_lines_removed"]) { s["lines_removed"] = v }
            if let v = number(ctx?["total_input_tokens"]) { s["context_input_tokens"] = v }
            if let v = number(ctx?["total_output_tokens"]) { s["context_output_tokens"] = v }
            if let v = number(ctx?["context_window_size"]) { s["context_window_size"] = v }
            if let p = ctxPercent { s["context_percent"] = p }
            if let e = (j["effort"] as? [String: Any])?["level"] as? String { s["effort"] = e }
            files["sessions/\(sid).json"] = s
        }
        return Output(files: files, line: parts.joined(separator: " · "))
    }

    /// Writes the files atomically below `dataDir` (temp file + rename, so readers never see half a file).
    public static func write(_ output: Output, dataDir: String) {
        let fm = FileManager.default
        for (rel, obj) in output.files {
            let url = URL(fileURLWithPath: dataDir).appendingPathComponent(rel)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { continue }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// JSON number, not a bool.
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// Reset time as epoch seconds: a number (seconds, or milliseconds when that large) or an ISO string.
    static func epoch(_ v: Any?) -> Double? {
        if let n = number(v) { return n > 1e11 ? (n / 1000).rounded() : n }
        guard let s = v as? String else { return nil }
        // ISO8601DateFormatter can't read microseconds ("…:59.514957+00:00"): drop the fraction
        let plain = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: plain).map { $0.timeIntervalSince1970.rounded() }
    }
}

/// One session's status line facts, as `switchboard-statusline` stored them.
public struct SessionLine: Equatable, Sendable {
    public let costUSD: Double?
    public let model: String?
    public let effort: String?
    public let contextPercent: Double?
    public let contextTokens: Int?
    public let contextWindow: Int?
    public let linesAdded: Int?
    public let linesRemoved: Int?
    public let durationMs: Double?
    public let writtenAt: Date

    public static func load(dataDir: String, sessionId: String) -> SessionLine? {
        guard StatusLine.safe(sessionId),
              let data = FileManager.default.contents(atPath: "\(dataDir)/sessions/\(sessionId).json"),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let written = StatusLine.number(j["written_at"]) else { return nil }
        let n = { (k: String) in StatusLine.number(j[k]) }
        let i = { (k: String) in n(k).flatMap { Int(exactly: $0.rounded()) } }
        return SessionLine(costUSD: n("cost_usd"), model: j["model"] as? String, effort: j["effort"] as? String,
                           contextPercent: n("context_percent"), contextTokens: i("context_input_tokens"),
                           contextWindow: i("context_window_size"), linesAdded: i("lines_added"),
                           linesRemoved: i("lines_removed"), durationMs: n("duration_ms"),
                           writtenAt: Date(timeIntervalSince1970: written))
    }
}
