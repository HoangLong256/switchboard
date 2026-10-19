import Foundation

/// Parsed transcript tails per session, re-read only when a file read for it has changed size.
/// Transcripts only grow, so the size is enough. Saves parsing every session's tail on every refresh
/// (the app refreshes up to five times a second while sessions work).
public final class TranscriptCache: @unchecked Sendable {
    struct Entry {
        let files: [(path: String, size: UInt64?)]
        let tail: Tail
        let starts: [Date?]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    /// keys read since the last `sweep` (the sessions that still exist)
    private var used = Set<String>()
    /// transcripts parsed (for tests)
    public private(set) var parses = 0
    /// sessions cached right now (for tests)
    public var count: Int { lock.withLock { entries.count } }

    public init() {}

    public func read(dir: String, sessionId: String) -> (tail: Tail, backgroundStarts: [Date?]) {
        let key = "\(dir)/\(sessionId)"
        if let e = lock.withLock({ used.insert(key); return entries[key] }), e.files.allSatisfy({ Self.size($0.path) == $0.size }) {
            return (e.tail, e.starts)
        }
        // a tail parse makes many short-lived Foundation objects; free them per session, not per refresh
        let e = autoreleasepool { () -> Entry in
            let (text, files) = Transcript.readTailTracked(dir: dir, sessionId: sessionId)
            return Entry(files: files, tail: Transcript.parseTail(text), starts: Transcript.backgroundStarts(text))
        }
        lock.withLock {
            entries[key] = e
            parses += 1
        }
        return (e.tail, e.starts)
    }

    /// Drops the sessions not read since the last sweep: entries of sessions that ended would otherwise stay
    /// for the life of the app (each holds its last messages). Call once after every full state build.
    public func sweep() {
        lock.withLock {
            entries = entries.filter { used.contains($0.key) }
            used.removeAll(keepingCapacity: true)
        }
    }

    private static func size(_ path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
    }
}
