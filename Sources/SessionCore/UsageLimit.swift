import Foundation

/// When a usage limit that stopped a session resets, from Claude Code's message ("resets 3:10pm (Asia/Saigon)",
/// "resets 5am", "resets Oct 20, 3pm (Asia/Saigon)") or, failing that, from the plan limits.
public enum UsageLimit {
    private static let pattern = try! NSRegularExpression(
        pattern: #"resets\s+(?:([A-Za-z]{3,9})\.?\s+(\d{1,2}),?\s+(?:at\s+)?)?(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?\s*(?:\(([^)]+)\))?"#,
        options: [.caseInsensitive])

    /// Reset time in `message`; times without a date are the next such time after `after` (when the limit hit).
    public static func resetTime(in message: String, after: Date) -> Date? {
        let ns = message as NSString
        guard let m = pattern.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        guard var hour = group(3).flatMap(Int.init) else { return nil }
        let minute = group(4).flatMap(Int.init) ?? 0
        if let ampm = group(5)?.lowercased() {
            guard (1...12).contains(hour) else { return nil }
            let pm = ampm.hasPrefix("p")
            hour = hour % 12 + (pm ? 12 : 0)
        }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = group(6).flatMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) } ?? .current

        if let monthName = group(1), let day = group(2).flatMap(Int.init), let month = month(monthName) {
            var c = cal.dateComponents([.year], from: after)
            c.month = month; c.day = day; c.hour = hour; c.minute = minute
            guard let d = cal.date(from: c) else { return nil }
            // "Jan 2" seen in late December is next year
            return d < after.addingTimeInterval(-86_400) ? cal.date(byAdding: .year, value: 1, to: d) : d
        }
        return cal.nextDate(after: after, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime)
    }

    /// The reset of a limit hit: from its message, else the matching plan window (5 hours or week) if it resets
    /// after the hit. nil when neither says.
    public static func reset(of hit: LimitHit, limits: PlanLimits?) -> Date? {
        let at = hit.at.flatMap(parseISO) ?? Date()
        if let d = resetTime(in: hit.text, after: at) { return d }
        let window = hit.weekly ? limits?.sevenDay : limits?.fiveHour
        return window?.resetsAt.flatMap { $0 > at ? $0 : nil }
    }

    private static func month(_ name: String) -> Int? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return names.firstIndex(of: String(name.lowercased().prefix(3))).map { $0 + 1 }
    }
}
