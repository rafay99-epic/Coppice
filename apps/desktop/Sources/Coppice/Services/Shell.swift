import Foundation

/// Minimal subprocess runner. Coppice shells out to `git` and `lsof` rather than
/// linking libgit2, because both are guaranteed present on macOS and their
/// porcelain output is a stable contract.
enum Shell {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { status == 0 }
        /// stdout with the trailing newline removed, which is what callers want.
        var trimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines: [String] { stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }

    /// Runs `executable` and waits for it. Both pipes are drained on background
    /// queues while the process runs: reading them in sequence deadlocks as soon
    /// as either exceeds the 64 KB pipe buffer, which a `git status` in a large
    /// worktree will do.
    ///
    /// Returns status timedOutStatus if the process outlives `timeout`, after
    /// terminating it, so one wedged git call cannot stall a scan forever.
    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
        timeout: TimeInterval = 20
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        // A git subprocess must never prompt: no credential helper, no pager, no
        // editor. Without this a repo needing auth hangs until the timeout.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.syntaxlabtechnology.coppice.shell", attributes: .concurrent)

        for (pipe, isStdout) in [(outPipe, true), (errPipe, false)] {
            queue.async(group: group) {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isStdout { outData = data } else { errData = data }
                lock.unlock()
            }
        }

        // Terminate rather than hang. SIGTERM first; the pipes then hit EOF and
        // the reader tasks finish, so the group wait below still returns.
        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            process.terminate()
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)

        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        lock.lock()
        let out = String(decoding: outData, as: UTF8.self)
        let err = String(decoding: errData, as: UTF8.self)
        lock.unlock()

        return Result(status: process.terminationStatus, stdout: out, stderr: err)
    }
}

/// Thin, typed wrapper over the git commands Coppice needs. Every call is
/// read-only except `prune` and `deleteBranch`, which are the only two places
/// the app mutates a repository.
enum Git {
    static let executable = "/usr/bin/git"

    static func run(_ arguments: [String], in repo: String, timeout: TimeInterval = 20) -> Shell.Result {
        Shell.run(executable, ["-C", repo] + arguments, timeout: timeout)
    }

    /// `git worktree list --porcelain`, unparsed.
    static func worktreeList(repo: String) -> Shell.Result {
        run(["worktree", "list", "--porcelain"], in: repo)
    }

    /// Modified, staged and untracked entries. Empty output means clean.
    static func status(worktree: String) -> [String] {
        run(["status", "--porcelain", "--untracked-files=normal"], in: worktree).lines
    }

    /// Commits on HEAD that the upstream does not have. Nil when there is no
    /// upstream at all, which the caller handles differently from zero.
    static func unpushedCount(worktree: String) -> Int? {
        let upstream = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: worktree)
        guard upstream.succeeded else { return nil }
        let result = run(["rev-list", "--count", "@{u}..HEAD"], in: worktree)
        guard result.succeeded else { return nil }
        return Int(result.trimmed)
    }

    /// Commits on HEAD that are not reachable from the repository's default
    /// branch. Used when a branch has no upstream, so "is this work saved
    /// anywhere else" still has an answer.
    static func commitsAheadOfDefault(worktree: String, defaultBranch: String) -> Int? {
        let result = run(["rev-list", "--count", "\(defaultBranch)..HEAD"], in: worktree)
        guard result.succeeded else { return nil }
        return Int(result.trimmed)
    }

    /// The repository's default branch, resolved from origin's HEAD with a
    /// fallback to whichever of main/master exists.
    static func defaultBranch(repo: String) -> String? {
        let symbolic = run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: repo)
        if symbolic.succeeded, !symbolic.trimmed.isEmpty { return symbolic.trimmed }
        for candidate in ["main", "master"]
        where run(["rev-parse", "--verify", "--quiet", candidate], in: repo).succeeded {
            return candidate
        }
        return nil
    }

    /// True when the branch is reachable from the default branch, so removing
    /// the worktree loses nothing.
    static func isMerged(branch: String, into target: String, repo: String) -> Bool {
        let result = run(["merge-base", "--is-ancestor", branch, target], in: repo)
        return result.status == 0
    }

    static func stashCount(repo: String, referencing branch: String) -> Int {
        run(["stash", "list"], in: repo).lines.filter { $0.contains(branch) }.count
    }

    /// Submodules reporting any local change. Prefix `+` or `U` in the status
    /// output means modified or conflicted.
    static func dirtySubmodules(worktree: String) -> [String] {
        run(["submodule", "status", "--recursive"], in: worktree).lines.compactMap { line in
            guard let first = line.first, first == "+" || first == "U" else { return nil }
            let parts = line.dropFirst().split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            return String(parts[1])
        }
    }

    /// Clears metadata for worktrees whose directories are gone. Safe by
    /// definition: git only prunes entries it already considers dead.
    static func prune(repo: String) -> Shell.Result {
        run(["worktree", "prune"], in: repo)
    }

    /// Always `-d`, never `-D`. Git refuses to delete an unmerged branch, and
    /// that veto is a feature, not an obstacle to route around.
    static func deleteBranch(_ branch: String, repo: String) -> Shell.Result {
        run(["branch", "-d", branch], in: repo)
    }

    /// The real git directory for a worktree, used to find in-progress
    /// operations. For a linked worktree this points into the parent's
    /// `.git/worktrees/<name>`.
    static func gitDirectory(worktree: String) -> String? {
        let result = run(["rev-parse", "--absolute-git-dir"], in: worktree)
        return result.succeeded ? result.trimmed : nil
    }
}
