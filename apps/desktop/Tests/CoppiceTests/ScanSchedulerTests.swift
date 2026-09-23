import XCTest
@testable import Coppice

final class ScanSchedulerTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func testFirstRequestScansImmediately() {
        var scheduler = ScanScheduler(minimumInterval: 60)
        XCTAssertEqual(scheduler.request(automatic: true, now: start), .scanNow)
        XCTAssertTrue(scheduler.isScanning)
    }

    func testWatcherRequestsAreThrottledToOneDeferredScan() {
        var scheduler = ScanScheduler(minimumInterval: 60)
        _ = scheduler.request(automatic: true, now: start)
        _ = scheduler.finished(now: start)

        let soon = start.addingTimeInterval(10)
        XCTAssertEqual(scheduler.request(automatic: true, now: soon), .deferred(50))
        XCTAssertEqual(scheduler.request(automatic: true, now: soon), .wait, "only one deferred scan is ever pending")

        scheduler.deferredFired()
        XCTAssertEqual(scheduler.request(automatic: true, now: start.addingTimeInterval(60)), .scanNow)
    }

    func testManualRequestIgnoresTheThrottle() {
        var scheduler = ScanScheduler(minimumInterval: 60)
        _ = scheduler.request(automatic: false, now: start)
        _ = scheduler.finished(now: start)
        XCTAssertEqual(scheduler.request(automatic: false, now: start.addingTimeInterval(1)), .scanNow)
    }

    func testRequestDuringAScanIsQueuedAndRunsOnce() {
        var scheduler = ScanScheduler(minimumInterval: 60)
        _ = scheduler.request(automatic: false, now: start)
        XCTAssertEqual(scheduler.request(automatic: false, now: start), .wait)
        XCTAssertEqual(scheduler.request(automatic: true, now: start), .wait)

        XCTAssertTrue(scheduler.finished(now: start), "a settings change mid-scan must not be lost")
        XCTAssertFalse(scheduler.isQueued)
        XCTAssertEqual(scheduler.request(automatic: false, now: start), .scanNow)
        XCTAssertFalse(scheduler.finished(now: start))
    }

    func testInterruptingAScanDropsTheQueue() {
        var scheduler = ScanScheduler(minimumInterval: 60)
        _ = scheduler.request(automatic: false, now: start)
        _ = scheduler.request(automatic: false, now: start)
        scheduler.interrupted()

        XCTAssertFalse(scheduler.isScanning)
        XCTAssertFalse(scheduler.isQueued)
        XCTAssertEqual(scheduler.request(automatic: false, now: start), .scanNow, "an action's own rescan runs right away")
    }

    func testOnlyWorktreeLevelChangesTriggerAScan() {
        let roots = ["/Users/me/.t3/worktrees"]
        XCTAssertTrue(ScanScheduler.isWorktreeChange("/Users/me/Code/app/.git/worktrees/", agentRoots: roots))
        XCTAssertTrue(ScanScheduler.isWorktreeChange("/Users/me/.t3/worktrees/app/", agentRoots: roots))
        XCTAssertFalse(ScanScheduler.isWorktreeChange("/Users/me/Code/app/src/", agentRoots: roots), "a file save in a repo")
        XCTAssertFalse(ScanScheduler.isWorktreeChange("/Users/me/Code/app/.git/worktrees/feature/", agentRoots: roots), "git index churn")
        let agentEdit = "/Users/me/.t3/worktrees/app/task-1/src/"
        XCTAssertFalse(ScanScheduler.isWorktreeChange(agentEdit, agentRoots: roots), "an agent editing files")
    }
}
