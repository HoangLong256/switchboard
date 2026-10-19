import CoreServices
import Foundation

/// Reports changes under the folders (recursively). Throttled: the first event triggers exactly one
/// report after `delay`, further events within that time merge into it. This way, a session that is
/// currently writing to the log triggers at most five rebuilds per second.
public final class Watcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "switchboard.watcher")
    private let delay: TimeInterval
    private let onChange: @Sendable () -> Void
    /// paths whose changes don't count (e.g. git's own writes inside `.git/`)
    private let ignore: (@Sendable (String) -> Bool)?
    private var scheduled = false   // only on `queue`

    public init(paths: [String], delay: TimeInterval = 0.2, ignore: (@Sendable (String) -> Bool)? = nil,
                onChange: @escaping @Sendable () -> Void) {
        self.delay = delay
        self.onChange = onChange
        self.ignore = ignore
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<Watcher>.fromOpaque(info).takeUnretainedValue()
            if let ignore = watcher.ignore {
                let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
                guard list.prefix(count).contains(where: { !ignore($0) }) else { return }
            }
            watcher.eventArrived()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                                             | kFSEventStreamCreateFlagUseCFTypes)
        stream = FSEventStreamCreate(nil, callback, &context, paths as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    private func eventArrived() {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.onChange()
        }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
