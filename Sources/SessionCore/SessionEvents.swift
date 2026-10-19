import Foundation

/// What a session looks like in one refresh, as far as notifications care.
public struct SessionSnapshot: Equatable, Sendable {
    public let name: String
    /// 0 needs you, 1 working, 2 ready, 3 offline (SessionStatus.rank)
    public let rank: Int
    /// the hint line of the status ("Allow Bash: go test …")
    public let why: String?
    /// identity of the usage limit the session stands at (its time, else its text); nil = none
    public let limitHit: String?

    public init(name: String, rank: Int, why: String? = nil, limitHit: String? = nil) {
        self.name = name
        self.rank = rank
        self.why = why
        self.limitHit = limitHit
    }
}

/// Something worth telling the user about a session. The app turns these into user notifications.
public struct SessionEvent: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// the session started waiting for a permission, a question or an answer
        case needsYou
        /// the session worked and is ready again
        case finished
        /// the session stopped at a usage limit
        case usageLimit
        /// a live session went offline
        case ended
    }

    public let kind: Kind
    public let name: String
    /// the body of the notification (what it waits for, the limit message); nil = the kind's default text
    public let detail: String?

    public init(_ kind: Kind, _ name: String, detail: String? = nil) {
        self.kind = kind
        self.name = name
        self.detail = detail
    }
}

/// Finds the events between one refresh and the next: a session that starts needing you, one that finishes a
/// stretch of work, one that hits a usage limit, one that goes offline. Pure: feed it snapshots, get events.
/// The first update only remembers the sessions (nothing happened yet), so nothing fires at launch.
public struct SessionEventTracker: Equatable, Sendable {
    struct Seen: Equatable, Sendable {
        let rank: Int
        let why: String?
        let limitHit: String?
        /// when the session was first seen in this rank
        let since: Date
    }

    /// Work shorter than this doesn't count as "finished": the session only answered a quick question.
    public var minimumWork: TimeInterval
    private var seen: [String: Seen] = [:]
    private var primed = false

    public init(minimumWork: TimeInterval = 20) {
        self.minimumWork = minimumWork
    }

    /// Compares `snapshots` with the last update and returns what changed, in the order of `snapshots`.
    public mutating func update(_ snapshots: [SessionSnapshot], now: Date) -> [SessionEvent] {
        var events: [SessionEvent] = []
        var next: [String: Seen] = [:]
        for s in snapshots {
            let p = seen[s.name]
            next[s.name] = Seen(rank: s.rank, why: s.why, limitHit: s.limitHit,
                                since: p?.rank == s.rank ? p!.since : now)
            guard primed, let p else { continue }
            // a new question counts too (rank stays 0 when one permission prompt follows another)
            if s.rank == 0, p.rank != 0 || p.why != s.why {
                events.append(SessionEvent(.needsYou, s.name, detail: s.why))
            }
            if s.rank == 2, p.rank == 1, now.timeIntervalSince(p.since) >= minimumWork {
                events.append(SessionEvent(.finished, s.name))
            }
            if let hit = s.limitHit, hit != p.limitHit {
                events.append(SessionEvent(.usageLimit, s.name))
            }
            if s.rank == 3, p.rank < 3 {
                events.append(SessionEvent(.ended, s.name))
            }
        }
        // a session without a handover disappears from the list when it ends
        if primed {
            for (name, p) in seen where next[name] == nil && p.rank < 3 {
                events.append(SessionEvent(.ended, name))
            }
        }
        seen = next
        primed = true
        return events
    }
}
