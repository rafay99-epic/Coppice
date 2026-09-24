import XCTest
@testable import Coppice

final class ParsingTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    func testParsesMainAndLinkedWorktrees() {
        let output = """
        worktree /Users/tester/Code/app
        HEAD abc123
        branch refs/heads/main

        worktree /Users/tester/.t3/worktrees/app/t3code-1
        HEAD def456
        branch refs/heads/feature/one

        """
        let result = WorktreeScanner.parseWorktreeList(output, repoPath: "/Users/tester/Code/app", home: home)

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].isMain, "the first record is always the repository's own working copy")
        XCTAssertEqual(result[0].branch, "main")
        XCTAssertFalse(result[1].isMain)
        XCTAssertEqual(result[1].branch, "feature/one")
        XCTAssertEqual(result[1].harness, .t3Code)
    }

    func testParsesPrunableAndLockedFlags() {
        let output = """
        worktree /Users/tester/Code/app
        HEAD abc123
        branch refs/heads/main

        worktree /Users/tester/.t3/worktrees/app/gone
        HEAD def456
        branch refs/heads/dead
        prunable gitdir file points to non-existent location

        worktree /Users/tester/.t3/worktrees/app/held
        HEAD 789abc
        branch refs/heads/held
        locked working on it

        """
        let result = WorktreeScanner.parseWorktreeList(output, repoPath: "/Users/tester/Code/app", home: home)

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[1].isPrunable)
        XCTAssertFalse(result[1].isLocked)
        XCTAssertTrue(result[2].isLocked)
        XCTAssertFalse(result[2].isPrunable)
    }

    func testParsesDetachedHead() {
        let output = """
        worktree /Users/tester/Code/app
        HEAD abc123
        detached

        """
        let result = WorktreeScanner.parseWorktreeList(output, repoPath: "/Users/tester/Code/app", home: home)
        XCTAssertNil(result[0].branch)
        XCTAssertTrue(result[0].displayBranch.contains("detached"))
    }

    func testHarnessOwnershipByPath() {
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.t3/worktrees/app/x", home: home), .t3Code)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.codex/worktrees/x", home: home), .codex)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/Code/app/.claude/worktrees/x", home: home), .claudeCode)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.commandcode/worktrees/app-3456ec99bfe5", home: home), .commandCode)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.local/share/opencode/worktree/abc123/feature", home: home), .openCode)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/Code/app/plain", home: home), .manual)
    }

    func testSessionSlugReplacesSlashesDotsAndUnderscores() {
        XCTAssertEqual(
            SessionHistory.slug(for: "/Users/prometheus/.t3/worktrees/ENV_Connect/t3code-0dd49d63"),
            "-Users-prometheus--t3-worktrees-ENV-Connect-t3code-0dd49d63"
        )
    }

    func testParsesLsofFieldOutput() {
        let output = """
        p26196
        cnode
        fcwd
        n/Users/tester/.t3/worktrees/app/one
        p26200
        cclaude
        fcwd
        n/Users/tester/Code/other
        """
        let holders = ProcessProbe.parse(output)

        XCTAssertEqual(holders.count, 2)
        XCTAssertEqual(holders[0].pid, 26196)
        XCTAssertEqual(holders[0].command, "node")
        XCTAssertEqual(holders[1].command, "claude")
    }

    func testHolderMatchingDoesNotConfuseSiblingPrefixes() {
        let holders = [ProcessProbe.Holder(pid: 1, command: "node", cwd: "/w/feature-2")]
        XCTAssertNil(ProcessProbe.holder(of: "/w/feature", among: holders),
                     "feature-2 must not count as a process inside feature")
        XCTAssertNotNil(ProcessProbe.holder(of: "/w/feature-2", among: holders))
    }

    func testHolderMatchesNestedDirectory() {
        let holders = [ProcessProbe.Holder(pid: 1, command: "vite", cwd: "/w/app/src/pages")]
        XCTAssertNotNil(ProcessProbe.holder(of: "/w/app", among: holders))
    }

    func testManualHarnessIsNeverDetected() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let detected = Harness.detected(home: home)
        XCTAssertTrue(detected.contains(.claudeCode))
        XCTAssertFalse(detected.contains(.manual), "manual has no detect directory")
        XCTAssertNil(Harness.manual.detectDirectory(home: home))

        let saved = Set(detected).union([.manual])
        XCTAssertTrue(saved.contains(.manual))
    }

    func testDockIconSettingSharesOneKeyBetweenStaticAndStorage() {
        let key = "showsDockIcon"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(AppSettings.showsDockIcon, "the static must read the @AppStorage key")

        UserDefaults.standard.set(false, forKey: key)
        XCTAssertFalse(AppSettings.showsDockIcon)

        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(AppSettings.showsDockIcon, "absent means hidden from the Dock")
    }

    func testOnlyCorruptingBlockersAreAbsolute() {
        let absolute: [Blocker] = [
            .mainWorktree,
            .liveProcess(command: "node", pid: 1),
            .outsideScanRoots,
        ]
        for blocker in absolute {
            XCTAssertEqual(blocker.severity, .absolute, "\(blocker) must never be overridable")
            XCTAssertFalse(Verdict.blocked(blocker).canRemove)
        }

        let overridable: [Blocker] = [
            .uncommittedChanges(count: 2),
            .untrackedFiles(count: 1),
            .unpushedCommits(count: 3),
            .aheadOfDefault(count: 1),
            .ignoredConfig(files: [".env.local"]),
            .locked(reason: ""),
            .gitOperationInProgress(operation: "Rebase"),
            .dirtySubmodule(name: "vendor"),
        ]
        for blocker in overridable {
            XCTAssertEqual(blocker.severity, .overridable, "\(blocker) should be the user's call")
            XCTAssertEqual(Verdict.blocked(blocker).status, .hasWork)
            XCTAssertTrue(Verdict.blocked(blocker).canRemove, "has work, so it goes to the Trash")
        }
    }

    func testParsesPullRequestsByBranch() {
        let json = """
        [
          {"number":12,"state":"MERGED","title":"Add uptime","url":"https://x/12","isDraft":false,
           "headRefName":"feat/uptime"},
          {"number":13,"state":"OPEN","title":"Redesign","url":"https://x/13","isDraft":true,
           "headRefName":"feat/redesign"}
        ]
        """
        let byBranch = GitHub.parse(Data(json.utf8))

        XCTAssertEqual(byBranch["feat/uptime"]?.state, .merged)
        XCTAssertTrue(byBranch["feat/uptime"]?.isSettled == true)
        XCTAssertEqual(byBranch["feat/redesign"]?.state, .open)
        XCTAssertTrue(byBranch["feat/redesign"]?.isDraft == true)
        XCTAssertFalse(byBranch["feat/redesign"]?.isSettled == true)
    }

    func testOpenPullRequestWinsOverOlderClosedOne() {
        let json = """
        [
          {"number":4,"state":"CLOSED","title":"First try","url":"https://x/4","isDraft":false,
           "headRefName":"feat/thing"},
          {"number":9,"state":"OPEN","title":"Second try","url":"https://x/9","isDraft":false,
           "headRefName":"feat/thing"}
        ]
        """
        let byBranch = GitHub.parse(Data(json.utf8))
        XCTAssertEqual(byBranch["feat/thing"]?.number, 9)
        XCTAssertEqual(byBranch["feat/thing"]?.state, .open)
    }

    func testMalformedPullRequestPayloadIsIgnored() {
        XCTAssertTrue(GitHub.parse(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(GitHub.parse(Data("[]".utf8)).isEmpty)
    }

    func testConfigClassification() {
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".env"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".env.local"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig("settings.local"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".dev.vars"))

        XCTAssertFalse(WorktreeScanner.looksLikeConfig(".env.example"))
        XCTAssertFalse(WorktreeScanner.looksLikeConfig(".env.sample"))
        XCTAssertFalse(WorktreeScanner.looksLikeConfig("README.md"))
    }

    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.42", than: "0.41"))
        XCTAssertFalse(Updater.isNewer("0.41", than: "0.42"))
        XCTAssertFalse(Updater.isNewer("0.42", than: "0.42"))
        XCTAssertTrue(Updater.isNewer("0.100", than: "0.99"), "components compare numerically, not as strings")
        XCTAssertFalse(Updater.isNewer("0.42-nightly", than: "0.42"), "the channel suffix is not a version bump")
    }

    func testSweepIsOnlyBlockedByALiveProcess() {
        let dirty = Verdict.blocked(.uncommittedChanges(count: 3))
        XCTAssertTrue(dirty.canSweep, "node_modules is not source, so a dirty worktree still sweeps")
        XCTAssertTrue(dirty.canRemove, "and it can go to the Trash")

        let busy = Verdict.blocked(.liveProcess(command: "node", pid: 1))
        XCTAssertFalse(busy.canSweep, "a running process is the one thing that stops a sweep")
        XCTAssertFalse(busy.canRemove)

        XCTAssertFalse(Blocker.uncommittedChanges(count: 3).blocksSweep)
        XCTAssertTrue(Blocker.liveProcess(command: "node", pid: 1).blocksSweep)

        XCTAssertFalse(Verdict.prunable.canSweep, "there is nothing left on disk to sweep")
    }

    func testArtifactGatingRequiresTheManifest() {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        XCTAssertFalse(ArtifactScanner.qualifies(name: "build", parent: base.path))
        XCTAssertTrue(ArtifactScanner.qualifies(name: ".next", parent: base.path))

        FileManager.default.createFile(atPath: base.appending(path: "package.json").path, contents: Data("{}".utf8))
        XCTAssertTrue(ArtifactScanner.qualifies(name: "build", parent: base.path))
        XCTAssertTrue(ArtifactScanner.qualifies(name: "node_modules", parent: base.path))
        XCTAssertFalse(ArtifactScanner.qualifies(name: "target", parent: base.path),
                       "target needs a Cargo.toml, not a package.json")
    }

    func testMergedPullRequestOnlyCountsWhenItsHeadIsTheBranchTip() {
        let worktree = Worktree(
            path: "/tmp/wt", repoPath: "/tmp/repo", branch: "feature", head: "abc123",
            harness: .manual, isMain: false, isPrunable: false, isLocked: false, isOrphan: false
        )
        func report(headOid: String?) -> WorktreeReport {
            let pullRequest = PullRequest(number: 1, state: .merged, title: "", url: "", isDraft: false, headOid: headOid)
            return WorktreeReport(worktree: worktree, verdict: .safe, pullRequest: pullRequest)
        }
        XCTAssertTrue(report(headOid: "abc123").mergedAtHead)
        XCTAssertFalse(report(headOid: "def456").mergedAtHead, "commits after the merge must not count as merged")
        XCTAssertFalse(report(headOid: nil).mergedAtHead)
    }

    func testDirtySubmodulesComeFromPorcelainV2() {
        let porcelain = [
            "1 .M N... 100644 100644 100644 aaa aaa README.md",
            "1 .M SC.. 160000 160000 160000 bbb bbb vendor/lib",
            "1 .M S.M. 160000 160000 160000 ccc ccc tools/edited copy",
            "1 .. S... 160000 160000 160000 ddd ddd clean-module",
            "? scratch.txt",
        ].joined(separator: "\n")
        XCTAssertEqual(Git.parseDirtySubmodules(porcelain), ["vendor/lib", "tools/edited copy"])
        XCTAssertEqual(Git.parseDirtySubmodules(""), [])
    }
}

final class DiagnosticsTests: XCTestCase {
    func testProblemsKeepsOnlyErrorsAndCrashesNewestFirst() {
        let log = """
        2026-09-24T10:00:00Z  Coppice 0.90 (nightly) launched
        2026-09-24T10:01:00Z  ERROR  git failed  in ~/Code/app
        2026-09-24T10:02:00Z  Swept 3 worktrees
        2026-09-24T10:03:00Z  CRASH  Coppice 0.90 stopped on SIGSEGV.
        """
        let problems = Diagnostics.problems(in: log)
        XCTAssertEqual(problems.map(\.kind), ["CRASH", "ERROR"])
        XCTAssertEqual(problems.last?.message, "git failed  in ~/Code/app")
        XCTAssertNotNil(problems.first?.date)
    }

    func testHangLinesAreReadSeparately() {
        let log = """
        2026-09-24T10:00:00Z  HANG  main thread blocked for 1.40 s during sweeping 2 of 3
        2026-09-24T10:01:00Z  ERROR  git failed
        """
        let hangs = Diagnostics.problems(in: log, kinds: ["HANG"])
        XCTAssertEqual(hangs.map(\.message), ["main thread blocked for 1.40 s during sweeping 2 of 3"])
    }

    func testCommandLabelNamesTheRepositoryNotThePath() {
        let label = Telemetry.label("/usr/bin/git", ["-C", "/Users/me/Code/app", "status", "--porcelain", "-uall"], cwd: nil)
        XCTAssertEqual(label, "git status --porcelain · app")
    }
}

final class TelemetryTests: XCTestCase {
    func testWatchdogReportsABlockedMainThread() {
        let caught = expectation(description: "hang reported")
        caught.assertForOverFulfill = false
        let telemetry = Telemetry { seconds, _ in
            if seconds > 0.5 { caught.fulfill() }
        }
        telemetry.startWatchdog()
        Thread.sleep(forTimeInterval: 1.2)
        wait(for: [caught], timeout: 3)
        telemetry.stopWatchdog()
    }

    func testCPUPercentComesFromTheSampleWindow() {
        let start = Telemetry.Usage(date: Date(timeIntervalSince1970: 0), memory: 0, cpuSeconds: 1, threads: 1)
        let end = Telemetry.Usage(date: Date(timeIntervalSince1970: 10), memory: 0, cpuSeconds: 1.5, threads: 1)
        XCTAssertEqual(end.cpuPercent(since: start), 5, accuracy: 0.001)
        XCTAssertEqual(end.cpuPercent(since: nil), 0)
    }
}

final class CrashReportTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/Coppice Dev-2026-09-24-022056.ips")

    private let report = """
    {"app_name":"Coppice Dev","timestamp":"2026-09-24 02:20:56.00 +0500","app_version":"0.21-dev"}
    {"exception":{"type":"EXC_CRASH","signal":"SIGABRT"},
     "usedImages":[{"name":"CoreFoundation"},{"name":"libobjc.A.dylib"},{"name":"AppKit"},{"name":"SwiftUI"},{"name":"Coppice Dev"}],
     "lastExceptionBacktrace":[
       {"imageIndex":0,"symbol":"__exceptionPreprocess"},
       {"imageIndex":1,"symbol":"objc_exception_throw"},
       {"imageIndex":2,"symbol":"-[NSWindow _postWindowNeedsUpdateConstraints]"},
       {"imageIndex":3,"symbol":"NSHostingView.setNeedsUpdate()"},
       {"imageIndex":4,"symbol":"Coppice_main"}
     ]}
    """

    func testParsesExceptionFramesAndTheLikelyFrame() throws {
        let crash = try XCTUnwrap(CrashReports.parse(report, url: url, channel: .dev))
        XCTAssertEqual(crash.kind, "EXC_CRASH · SIGABRT")
        XCTAssertEqual(crash.version, "0.21-dev")
        XCTAssertEqual(crash.frames.count, 5)
        XCTAssertEqual(crash.headline, "-[NSWindow _postWindowNeedsUpdateConstraints]")
        XCTAssertTrue(crash.frames[4].isApp)
    }

    func testLogSuppliesTheExceptionAndWhatHappenedBefore() throws {
        var crash = try XCTUnwrap(CrashReports.parse(report, url: url, channel: .dev))
        let log = CrashReports.entries(in: """
        2026-09-23T21:20:50Z  remove with work checkout-api: 2 untracked files
        2026-09-23T21:20:53Z  removed checkout-api → Trash (10.57 GB)
        2026-09-23T21:20:54Z  CRASH  uncaught NSGenericException: The window has been marked as needing another pass.
        CRASH  Coppice 0.21-dev stopped on SIGABRT.
        """)
        CrashReports.attach(log, to: &crash)
        XCTAssertEqual(crash.kind, "NSGenericException")
        XCTAssertEqual(crash.reason, "The window has been marked as needing another pass.")
        XCTAssertEqual(
            crash.before.map(\.text),
            ["remove with work checkout-api: 2 untracked files", "removed checkout-api → Trash (10.57 GB)"]
        )
    }

    func testSameCauseGroupsTogether() throws {
        let first = try XCTUnwrap(CrashReports.parse(report, url: url, channel: .dev))
        let second = try XCTUnwrap(CrashReports.parse(report, url: URL(fileURLWithPath: "/tmp/Coppice-2026-09-24.ips"), channel: .stable))
        let groups = CrashReports.groups([first, second])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.channels, "Dev 1 · Stable 1")
    }
}
