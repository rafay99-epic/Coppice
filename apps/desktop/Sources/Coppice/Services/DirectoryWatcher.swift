import Foundation
import CoreServices

/// Watches the worktree roots and reports that something changed.
///
/// Coppice never polls. A timer that re-scans 30 worktrees every minute would
/// burn CPU continuously to learn nothing almost every time, and on a laptop
/// that is a battery cost the user pays all day for a feature they touch weekly.
/// FSEvents pushes instead: the kernel already knows when a directory changed,
/// so the app sleeps at zero CPU until it actually has a reason to look.
///
/// Two settings keep the cost near zero even during a burst:
///
/// - `latency` coalesces events inside the kernel. An `npm install` writes tens
///   of thousands of files; with a multi-second latency that arrives as one
///   callback rather than tens of thousands.
/// - The extra debounce below collapses whatever still gets through, so a long
///   install triggers exactly one rescan after it settles rather than one per
///   burst.
///
/// Directory-level events only. `kFSEventStreamCreateFlagFileEvents` would
/// deliver a callback per file and defeat the entire point.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: TimeInterval
    private let debounce: TimeInterval
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var pendingWork: DispatchWorkItem?

    init(
        paths: [String],
        latency: TimeInterval = 3.0,
        debounce: TimeInterval = 5.0,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.latency = latency
        self.debounce = debounce
        self.onChange = onChange
        // Utility QoS: this is background maintenance and must never compete
        // with whatever the user is actually doing.
        self.queue = DispatchQueue(
            label: "com.syntaxlabtechnology.coppice.watcher",
            qos: .utility
        )
    }

    deinit { stop() }

    func start() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleNotification()
        }

        // NoDefer: deliver the first event immediately, then coalesce the rest of
        // the window. WatchRoot: keep working if a root is renamed or replaced.
        let flags = UInt32(
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagUseCFTypes
        )

        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        pendingWork?.cancel()
        pendingWork = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Collapses a burst of callbacks into one rescan, fired once the filesystem
    /// has been quiet for `debounce`.
    private func scheduleNotification() {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.onChange()
            }
            self.pendingWork = work
            self.queue.asyncAfter(deadline: .now() + self.debounce, execute: work)
        }
    }
}
