import XCTest
@testable import Coppice

/// Pure parsing and classification. No filesystem, no git.
final class ParsingTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    // MARK: git worktree list --porcelain

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

    // MARK: Harness attribution

    func testHarnessOwnershipByPath() {
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.t3/worktrees/app/x", home: home), .t3Code)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/.codex/worktrees/x", home: home), .codex)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/Code/app/.claude/worktrees/x", home: home), .claudeCode)
        XCTAssertEqual(Harness.owning(path: "/Users/tester/Code/app/plain", home: home), .manual)
    }

    /// The slug scheme is Claude Code's, verified against a real session directory.
    func testSessionSlugReplacesSlashesDotsAndUnderscores() {
        XCTAssertEqual(
            SessionHistory.slug(for: "/Users/prometheus/.t3/worktrees/ENV_Connect/t3code-0dd49d63"),
            "-Users-prometheus--t3-worktrees-ENV-Connect-t3code-0dd49d63"
        )
    }

    // MARK: lsof

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

    /// `.manual` has no directory to find, so detection can never report it.
    /// Onboarding therefore has to add it explicitly — without that, saving the
    /// detected set hides every hand-made worktree and every ordinary
    /// repository's own working copy, while the totals still count them.
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

        // What onboarding saves must still cover manual worktrees.
        let saved = Set(detected).union([.manual])
        XCTAssertTrue(saved.contains(.manual))
    }

    // MARK: Override severity

    /// Worktrees are scratch space. Refusing forever would make the app useless
    /// on exactly the ones the user most wants gone, so everything that is
    /// merely *the user's own work* has to be overridable.
    func testOnlyCorruptingBlockersAreAbsolute() {
        let absolute: [Blocker] = [
            .mainWorktree,
            .liveProcess(command: "node", pid: 1),
            .outsideScanRoots,
        ]
        for blocker in absolute {
            XCTAssertEqual(blocker.severity, .absolute, "\(blocker) must never be overridable")
            XCTAssertNil(blocker.lossIfForced, "an absolute blocker has no override to describe")
            XCTAssertFalse(Verdict.blocked(blocker).canForceRemove)
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
            XCTAssertNotNil(blocker.lossIfForced, "an override must state what it destroys")
            XCTAssertTrue(Verdict.blocked(blocker).canForceRemove)
            XCTAssertFalse(Verdict.blocked(blocker).canRemove, "still blocked without an explicit override")
        }
    }

    // MARK: Pull requests

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

    /// A branch reused across several PRs should report the open one, not
    /// whichever the API listed first.
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

    // MARK: Config classification

    /// The rule that protects secrets must not fire on committed templates.
    func testConfigClassification() {
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".env"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".env.local"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig("settings.local"))
        XCTAssertTrue(WorktreeScanner.looksLikeConfig(".dev.vars"))

        XCTAssertFalse(WorktreeScanner.looksLikeConfig(".env.example"))
        XCTAssertFalse(WorktreeScanner.looksLikeConfig(".env.sample"))
        XCTAssertFalse(WorktreeScanner.looksLikeConfig("README.md"))
    }

    // MARK: Version ordering

    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("0.42", than: "0.41"))
        XCTAssertFalse(Updater.isNewer("0.41", than: "0.42"))
        XCTAssertFalse(Updater.isNewer("0.42", than: "0.42"))
        XCTAssertTrue(Updater.isNewer("0.100", than: "0.99"), "components compare numerically, not as strings")
        XCTAssertFalse(Updater.isNewer("0.42-nightly", than: "0.42"), "the channel suffix is not a version bump")
    }

    // MARK: Verdict semantics

    func testSweepIsOnlyBlockedByALiveProcess() {
        let dirty = Verdict.blocked(.uncommittedChanges(count: 3))
        XCTAssertTrue(dirty.canSweep, "node_modules is not source, so a dirty worktree still sweeps")
        XCTAssertFalse(dirty.canRemove, "but it is never removable")

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

        // No package.json next to it, so `build` is not treated as output.
        XCTAssertFalse(ArtifactScanner.qualifies(name: "build", parent: base.path))
        // .next needs no gate, it is never source.
        XCTAssertTrue(ArtifactScanner.qualifies(name: ".next", parent: base.path))

        FileManager.default.createFile(atPath: base.appending(path: "package.json").path, contents: Data("{}".utf8))
        XCTAssertTrue(ArtifactScanner.qualifies(name: "build", parent: base.path))
        XCTAssertTrue(ArtifactScanner.qualifies(name: "node_modules", parent: base.path))
        XCTAssertFalse(ArtifactScanner.qualifies(name: "target", parent: base.path),
                       "target needs a Cargo.toml, not a package.json")
    }
}
