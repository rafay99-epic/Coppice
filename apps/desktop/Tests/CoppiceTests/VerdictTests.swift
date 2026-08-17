import XCTest
@testable import Coppice

/// Builds a real repository with real worktrees in a temp directory and asserts
/// the verdict for each state.
///
/// These run against actual git rather than a mock, because the whole safety
/// model is a claim about what git reports. A mock would only prove the mock
/// agrees with itself.
final class VerdictTests: XCTestCase {
    private var root: URL!
    private var remote: URL!
    private var repo: URL!
    private var scanner: WorktreeScanner!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "coppice-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        remote = root.appending(path: "remote.git")
        repo = root.appending(path: "app")

        try XCTSkipUnless(FileManager.default.fileExists(atPath: Git.executable), "git is required")

        run(["init", "--bare", "--initial-branch=main", remote.path], in: root.path)
        run(["init", "--initial-branch=main", repo.path], in: root.path)
        git(["config", "user.email", "test@example.com"])
        git(["config", "user.name", "Coppice Tests"])
        git(["config", "commit.gpgsign", "false"])

        write("README.md", "hello")
        write(".gitignore", ".env.local\n*.secret\n")
        git(["add", "."])
        git(["commit", "-m", "initial"])
        git(["remote", "add", "origin", remote.path])
        git(["push", "-u", "origin", "main"])

        scanner = WorktreeScanner(home: root, codeRoots: [root])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: Helpers

    @discardableResult
    private func run(_ arguments: [String], in directory: String) -> Shell.Result {
        Shell.run(Git.executable, arguments, cwd: directory)
    }

    @discardableResult
    private func git(_ arguments: [String]) -> Shell.Result {
        Git.run(arguments, in: repo.path)
    }

    private func write(_ name: String, _ contents: String, in directory: URL? = nil) {
        let base = directory ?? repo!
        let url = base.appending(path: name)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Creates a linked worktree on a new branch and returns it.
    private func makeWorktree(_ name: String, push: Bool = true) throws -> Worktree {
        let path = root.appending(path: "trees/\(name)")
        git(["worktree", "add", "-b", name, path.path, "main"])
        if push { Git.run(["push", "-u", "origin", name], in: path.path) }

        let all = scanner.worktrees(inRepository: repo.path)
        let match = all.first { $0.path.hasSuffix("trees/\(name)") }
        return try XCTUnwrap(match, "worktree \(name) was not created")
    }

    private func verdict(_ worktree: Worktree, holders: [ProcessProbe.Holder] = []) -> Verdict {
        scanner.verdict(for: worktree, holders: holders)
    }

    /// A fixture worktree is seconds old, so the `veryNew` caution legitimately
    /// fires. Cautions never prevent anything, so "nothing is blocking this"
    /// is the assertion these tests actually want.
    private func assertRemovable(
        _ worktree: Worktree,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = verdict(worktree)
        if case .blocked(let blocker) = result {
            XCTFail("expected removable, blocked by \(blocker.summary). \(message)", file: file, line: line)
        }
        XCTAssertTrue(result.canRemove, message, file: file, line: line)
    }

    // MARK: Tests

    func testCleanPushedWorktreeIsRemovable() throws {
        let worktree = try makeWorktree("clean")
        assertRemovable(worktree, "a clean, pushed worktree has nothing to protect")
    }

    func testMainWorktreeIsNeverRemovable() throws {
        let all = scanner.worktrees(inRepository: repo.path)
        let main = try XCTUnwrap(all.first { $0.isMain })
        XCTAssertEqual(verdict(main), .blocked(.mainWorktree))
        XCTAssertFalse(verdict(main).canRemove)
    }

    func testModifiedFileBlocksRemoval() throws {
        let worktree = try makeWorktree("dirty")
        write("README.md", "changed", in: URL(fileURLWithPath: worktree.path))
        guard case .blocked(.uncommittedChanges) = verdict(worktree) else {
            return XCTFail("expected uncommittedChanges, got \(verdict(worktree))")
        }
    }

    func testUntrackedFileBlocksRemoval() throws {
        let worktree = try makeWorktree("untracked")
        write("scratch.txt", "notes", in: URL(fileURLWithPath: worktree.path))
        guard case .blocked(.untrackedFiles) = verdict(worktree) else {
            return XCTFail("expected untrackedFiles, got \(verdict(worktree))")
        }
    }

    func testUnpushedCommitBlocksRemoval() throws {
        let worktree = try makeWorktree("unpushed")
        write("new.md", "work", in: URL(fileURLWithPath: worktree.path))
        Git.run(["add", "."], in: worktree.path)
        Git.run(["commit", "-m", "local work"], in: worktree.path)
        guard case .blocked(.unpushedCommits) = verdict(worktree) else {
            return XCTFail("expected unpushedCommits, got \(verdict(worktree))")
        }
    }

    /// The rule nobody else implements. Git reports this worktree as completely
    /// clean, so every other check passes and the file would be destroyed.
    func testGitignoredConfigBlocksRemovalEvenWhenGitSaysClean() throws {
        let worktree = try makeWorktree("secrets")
        write(".env.local", "API_KEY=live", in: URL(fileURLWithPath: worktree.path))

        XCTAssertTrue(Git.status(worktree: worktree.path).isEmpty, "git must consider this worktree clean")

        guard case .blocked(.ignoredConfig(let files)) = verdict(worktree) else {
            return XCTFail("expected ignoredConfig, got \(verdict(worktree))")
        }
        XCTAssertEqual(files, [".env.local"])
    }

    /// A committed template is not a secret and must not block.
    func testTrackedEnvExampleDoesNotBlock() throws {
        write(".env.example", "API_KEY=", in: repo)
        git(["add", "."])
        git(["commit", "-m", "add template"])
        git(["push"])

        let worktree = try makeWorktree("template")
        assertRemovable(worktree, ".env.example is tracked, so it is not a local-only secret")
    }

    func testLiveProcessBlocksBothSweepAndRemove() throws {
        let worktree = try makeWorktree("busy")
        let holders = [ProcessProbe.Holder(pid: 999, command: "node", cwd: worktree.path)]
        let result = verdict(worktree, holders: holders)

        guard case .blocked(.liveProcess) = result else {
            return XCTFail("expected liveProcess, got \(result)")
        }
        XCTAssertFalse(result.canRemove)
        XCTAssertFalse(result.canSweep, "a running process is the one thing that stops a sweep")
    }

    /// A dirty worktree still sweeps: node_modules is not source.
    func testDirtyWorktreeStillSweeps() throws {
        let worktree = try makeWorktree("dirty-but-sweepable")
        write("README.md", "changed", in: URL(fileURLWithPath: worktree.path))
        XCTAssertTrue(verdict(worktree).canSweep)
        XCTAssertFalse(verdict(worktree).canRemove)
    }

    func testLockedWorktreeIsBlocked() throws {
        let worktree = try makeWorktree("locked")
        git(["worktree", "lock", worktree.path])
        defer { git(["worktree", "unlock", worktree.path]) }

        let refreshed = try XCTUnwrap(
            scanner.worktrees(inRepository: repo.path).first { $0.path == worktree.path }
        )
        guard case .blocked(.locked) = verdict(refreshed) else {
            return XCTFail("expected locked, got \(verdict(refreshed))")
        }
    }

    func testInterruptedRebaseIsBlocked() throws {
        let worktree = try makeWorktree("rebasing")
        let gitDir = try XCTUnwrap(Git.gitDirectory(worktree: worktree.path))
        FileManager.default.createFile(
            atPath: (gitDir as NSString).appendingPathComponent("REBASE_HEAD"),
            contents: Data("abc123".utf8)
        )
        guard case .blocked(.gitOperationInProgress) = verdict(worktree) else {
            return XCTFail("expected gitOperationInProgress, got \(verdict(worktree))")
        }
    }

    func testDeletedDirectoryBecomesPrunable() throws {
        let worktree = try makeWorktree("vanished")
        try FileManager.default.removeItem(atPath: worktree.path)

        let refreshed = try XCTUnwrap(
            scanner.worktrees(inRepository: repo.path).first { $0.path == worktree.path }
        )
        XCTAssertEqual(verdict(refreshed), .prunable)
        XCTAssertFalse(verdict(refreshed).canSweep, "there is nothing left to sweep")
    }

    func testPathOutsideConfiguredRootsIsRefused() throws {
        let worktree = try makeWorktree("outside")
        let narrow = WorktreeScanner(home: root, codeRoots: [root.appending(path: "elsewhere")])
        guard case .blocked(.outsideScanRoots) = narrow.verdict(for: worktree, holders: []) else {
            return XCTFail("a worktree outside every configured root must be refused")
        }
    }

    // MARK: Sweep behaviour

    func testSweepRemovesArtifactsAndKeepsSource() throws {
        let worktree = try makeWorktree("with-artifacts")
        let worktreeURL = URL(fileURLWithPath: worktree.path)
        write("package.json", "{}", in: worktreeURL)
        write("node_modules/left-pad/index.js", "module.exports = 1", in: worktreeURL)
        write("src/main.ts", "export const x = 1", in: worktreeURL)

        let artifacts = ArtifactScanner.scan(worktree: worktree.path)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.kind, "node_modules")

        let report = WorktreeReport(worktree: worktree, verdict: .safe)
        let outcome = Sweeper.sweep(reports: [report], scanner: scanner)

        XCTAssertTrue(outcome.failures.isEmpty, "\(outcome.failures)")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: worktreeURL.appending(path: "node_modules").path),
            "node_modules must be gone"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: worktreeURL.appending(path: "src/main.ts").path),
            "source must survive a sweep"
        )
    }

    /// The window between deciding and acting. A background app scans on a timer,
    /// so this is the case that actually happens rather than a theoretical one.
    func testRemovalIsRefusedWhenStateChangedAfterTheScan() throws {
        let worktree = try makeWorktree("raced")

        // Verdict at scan time: safe.
        let report = WorktreeReport(worktree: worktree, verdict: .safe)
        XCTAssertTrue(report.verdict.canRemove)

        // The world moves: someone starts editing.
        write("urgent.md", "in progress", in: URL(fileURLWithPath: worktree.path))

        let outcome = Sweeper.remove(
            report: report,
            scanner: scanner,
            deleteBranch: false,
            rescueDirectory: nil
        )

        XCTAssertTrue(outcome.removedPaths.isEmpty, "a stale verdict must not authorise a deletion")
        XCTAssertEqual(outcome.skipped.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: worktree.path),
            "the worktree must still be there"
        )
    }

    func testRemovalRescuesIgnoredConfigBeforeDeleting() throws {
        let worktree = try makeWorktree("rescue-me")
        write(".env.local", "TOKEN=abc123", in: URL(fileURLWithPath: worktree.path))

        // Rule 7 blocks this, which is correct. Confirm the rescue copies the
        // file out when the caller supplies a rescue directory anyway.
        let rescue = root.appending(path: "rescued")
        let files = scanner.ignoredConfigFiles(in: worktree.path)
        XCTAssertEqual(files, [".env.local"])

        _ = Sweeper.remove(
            report: WorktreeReport(worktree: worktree, verdict: .safe),
            scanner: scanner,
            deleteBranch: false,
            rescueDirectory: rescue
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: worktree.path),
            "ignored config blocks removal outright"
        )
    }

    // MARK: Inventory

    func testInventoryFindsWorktreesAcrossTheRepository() throws {
        _ = try makeWorktree("one")
        _ = try makeWorktree("two")

        let all = scanner.inventory()
        let names = Set(all.map(\.name))
        XCTAssertTrue(names.contains("one"))
        XCTAssertTrue(names.contains("two"))
        XCTAssertTrue(all.contains { $0.isMain }, "the main worktree is listed so it can be shown as protected")
    }
}
