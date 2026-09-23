import Foundation

struct ScanScheduler {
    enum Decision: Equatable {
        case scanNow
        case wait
        case deferred(TimeInterval)
    }

    let minimumInterval: TimeInterval
    private(set) var isScanning = false
    private(set) var isQueued = false
    private(set) var hasDeferred = false
    private(set) var lastFinished: Date?

    init(minimumInterval: TimeInterval = 60) {
        self.minimumInterval = minimumInterval
    }

    mutating func request(automatic: Bool, now: Date) -> Decision {
        if isScanning {
            isQueued = true
            return .wait
        }
        if automatic, let lastFinished {
            let remaining = minimumInterval - now.timeIntervalSince(lastFinished)
            if remaining > 0 {
                guard !hasDeferred else { return .wait }
                hasDeferred = true
                return .deferred(remaining)
            }
        }
        isScanning = true
        hasDeferred = false
        return .scanNow
    }

    mutating func deferredFired() {
        hasDeferred = false
    }

    mutating func finished(now: Date) -> Bool {
        isScanning = false
        lastFinished = now
        defer { isQueued = false }
        return isQueued
    }

    static func isWorktreeChange(_ changed: String, agentRoots: [String]) -> Bool {
        let path = changed.hasSuffix("/") ? String(changed.dropLast()) : changed
        let parent = (path as NSString).deletingLastPathComponent
        return path.hasSuffix("/.git/worktrees") || agentRoots.contains { path == $0 || parent == $0 }
    }

    mutating func interrupted() {
        isScanning = false
        isQueued = false
    }
}
