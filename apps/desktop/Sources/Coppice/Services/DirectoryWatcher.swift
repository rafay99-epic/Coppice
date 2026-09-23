import Foundation
import CoreServices

final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let latency: TimeInterval
    private let debounce: TimeInterval
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let isRelevant: @Sendable (String) -> Bool
    private var pendingWork: DispatchWorkItem?

    init(
        paths: [String],
        latency: TimeInterval = 3.0,
        debounce: TimeInterval = 5.0,
        isRelevant: @escaping @Sendable (String) -> Bool = { _ in true },
        onChange: @escaping @Sendable () -> Void
    ) {
        self.paths = paths
        self.isRelevant = isRelevant
        self.latency = latency
        self.debounce = debounce
        self.onChange = onChange
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

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
            guard changed.contains(where: watcher.isRelevant) else { return }
            watcher.scheduleNotification()
        }

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
        ) else {
            Log.shared.error("could not watch \(paths.count) folders for changes; rescan manually")
            return
        }

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
