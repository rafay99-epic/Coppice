import Foundation

/// Performs the two destructive operations, and refuses them whenever the world
/// has moved since the verdict was computed.
///
/// The re-verification is the point of this type. Coppice scans in the
/// background, so a verdict can be minutes old by the time a button is pressed,
/// and in those minutes an agent may have opened the very worktree that was
/// about to be deleted.
enum Sweeper {
    /// One thing that did not happen, and why. A struct rather than a tuple so
    /// the UI can list these, and so a reason never gets lost on the way out.
    struct Item: Sendable, Hashable, Identifiable {
        let path: String
        let reason: String
        var id: String { path + reason }
        var name: String { (path as NSString).lastPathComponent }
    }

    struct Outcome: Sendable {
        var freedBytes: Int64 = 0
        var removedPaths: [String] = []
        var skipped: [Item] = []
        var failures: [Item] = []

        var didAnything: Bool { !removedPaths.isEmpty }
        var hasProblems: Bool { !skipped.isEmpty || !failures.isEmpty }
    }

    /// Where a long operation has got to. Reported per item so the UI can show a
    /// determinate bar and name what is being worked on, rather than an
    /// indeterminate spinner that tells the user nothing.
    struct Progress: Sendable, Equatable {
        var completed: Int
        var total: Int
        var currentName: String
        var freedBytes: Int64

        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    // MARK: - Sweep

    /// Deletes regenerable build artifacts inside the given worktrees.
    ///
    /// Uses `removeItem`, not the Trash, on purpose. A 1.3 GB `node_modules` is
    /// 100k+ files; moving that to the Trash takes minutes and leaves the Trash
    /// unusable, and the undo is `bun install`, not a restore.
    static func sweep(
        reports: [WorktreeReport],
        scanner: WorktreeScanner,
        fileManager: FileManager = .default,
        log: (String) -> Void = { _ in },
        onProgress: (Progress) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        let holders = ProcessProbe.currentHolders()
        let total = reports.count
        var completed = 0

        for report in reports {
            onProgress(
                Progress(
                    completed: completed,
                    total: total,
                    currentName: report.worktree.name,
                    freedBytes: outcome.freedBytes
                )
            )
            defer { completed += 1 }

            let worktree = report.worktree

            // Re-check liveness now, not when the list was built.
            if let holder = ProcessProbe.holder(of: worktree.path, among: holders) {
                outcome.skipped.append(Item(path: worktree.path, reason: "\(holder.command) started working here"))
                log("sweep skipped \(worktree.path): held by \(holder.command) (\(holder.pid))")
                continue
            }
            guard scanner.isInsideAllowedRoot(worktree.path) else {
                outcome.skipped.append(Item(path: worktree.path, reason: "outside the configured roots"))
                continue
            }

            // Rescan artifacts rather than trusting the cached list, so a folder
            // deleted since the scan is not deleted twice and a new one is caught.
            for artifact in ArtifactScanner.scan(worktree: worktree.path, fileManager: fileManager) {
                guard isContained(artifact.path, within: worktree.path) else {
                    outcome.skipped.append(Item(path: artifact.path, reason: "resolved outside its worktree"))
                    continue
                }
                let size = ArtifactScanner.allocatedSize(of: artifact.path, fileManager: fileManager)
                do {
                    try fileManager.removeItem(atPath: artifact.path)
                    outcome.freedBytes += size
                    outcome.removedPaths.append(artifact.path)
                    log("swept \(artifact.path) (\(Format.bytes(size)))")
                } catch {
                    outcome.failures.append(Item(path: artifact.path, reason: error.localizedDescription))
                    log("sweep failed \(artifact.path): \(error.localizedDescription)")
                }
            }
        }
        onProgress(Progress(completed: total, total: total, currentName: "", freedBytes: outcome.freedBytes))
        return outcome
    }

    // MARK: - Prune

    /// Clears metadata for worktrees git already considers dead. Nothing on disk
    /// is touched, because by definition the directories are already gone.
    static func prune(
        repositories: [String],
        log: (String) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        for repo in Set(repositories) {
            let result = Git.prune(repo: repo)
            if result.succeeded {
                outcome.removedPaths.append(repo)
                log("pruned \(repo)")
            } else {
                outcome.failures.append(
                    Item(path: repo, reason: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                )
            }
        }
        return outcome
    }

    // MARK: - Remove

    /// Deletes a worktree directory, then its git metadata, then optionally its
    /// branch.
    ///
    /// Order matters and is not negotiable. Removing the directory before
    /// pruning leaves git believing the worktree exists; pruning first while the
    /// directory is live orphans it. Any failed step aborts the rest.
    /// - Parameter force: proceed despite an overridable blocker. Absolute
    ///   blockers still refuse: no confirmation makes it safe to delete a
    ///   directory a process is writing to, or to remove a repository's own
    ///   working copy.
    static func remove(
        report: WorktreeReport,
        scanner: WorktreeScanner,
        deleteBranch: Bool,
        rescueDirectory: URL?,
        force: Bool = false,
        fileManager: FileManager = .default,
        log: (String) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        let worktree = report.worktree

        // 1. Recompute from scratch. A cached verdict is never trusted here,
        //    and that applies to a forced removal too: the check that changes
        //    is which blockers are fatal, never whether the check runs.
        let holders = ProcessProbe.currentHolders()
        let current = scanner.verdict(for: worktree, holders: holders)
        if !current.canRemove {
            guard force, current.canForceRemove else {
                let reason = current.blocker?.severity == .absolute
                    ? "\(current.label) — this cannot be overridden"
                    : current.label
                outcome.skipped.append(Item(path: worktree.path, reason: reason))
                log("remove refused \(worktree.path): \(reason)")
                return outcome
            }
            // Record what the user chose to discard. If they later wonder where
            // that branch went, the log is the only place that can answer.
            log("remove FORCED \(worktree.path): overriding \(current.label)")
        }
        guard scanner.isInsideAllowedRoot(worktree.path) else {
            outcome.skipped.append(Item(path: worktree.path, reason: "outside the configured roots"))
            return outcome
        }

        // 2. Copy out anything git has no record of, before anything is destroyed.
        if let rescueDirectory {
            rescueIgnoredConfig(
                worktree: worktree,
                scanner: scanner,
                into: rescueDirectory,
                fileManager: fileManager,
                log: log
            )
        }

        // A locked worktree has to be released before git will prune it, so
        // unlock as part of the override rather than leaving stale metadata.
        if worktree.isLocked {
            let unlock = Git.run(["worktree", "unlock", worktree.path], in: worktree.repoPath)
            log(unlock.succeeded ? "unlocked \(worktree.path)" : "unlock failed: \(unlock.stderr)")
        }

        let size = ArtifactScanner.allocatedSize(of: worktree.path, fileManager: fileManager)

        // 3. Trash, not remove. Unique content has no other undo.
        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: worktree.path), resultingItemURL: nil)
            outcome.freedBytes += size
            outcome.removedPaths.append(worktree.path)
            log("removed \(worktree.path) → Trash (\(Format.bytes(size)))")
        } catch {
            outcome.failures.append(Item(path: worktree.path, reason: error.localizedDescription))
            log("remove failed \(worktree.path): \(error.localizedDescription)")
            return outcome // never continue past a failed step
        }

        // 4. Only now is it safe to clear the metadata.
        let pruneResult = Git.prune(repo: worktree.repoPath)
        if !pruneResult.succeeded {
            outcome.failures.append(Item(path: worktree.repoPath, reason: "prune failed: \(pruneResult.stderr)"))
            return outcome
        }

        // 5. Opt-in, and `-d` so git keeps its veto over unmerged work.
        if deleteBranch, let branch = worktree.branch {
            // `-d` normally, `-D` only when the user already chose to discard
            // unmerged work — otherwise git's veto would silently keep a branch
            // the user explicitly asked to delete.
            let result = force
                ? Git.run(["branch", "-D", branch], in: worktree.repoPath)
                : Git.deleteBranch(branch, repo: worktree.repoPath)
            if result.succeeded {
                log("deleted branch \(branch)")
            } else {
                outcome.skipped.append(
                    Item(
                        path: branch,
                        reason: "git kept the branch: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                    )
                )
            }
        }

        return outcome
    }

    /// Copies gitignored config out to a rescue folder. These files are the only
    /// thing in a worktree that exists nowhere else, so they are saved even
    /// though the removal itself goes to the Trash.
    private static func rescueIgnoredConfig(
        worktree: Worktree,
        scanner: WorktreeScanner,
        into rescueRoot: URL,
        fileManager: FileManager,
        log: (String) -> Void
    ) {
        let files = scanner.ignoredConfigFiles(in: worktree.path)
        guard !files.isEmpty else { return }

        let destination = rescueRoot
            .appending(path: worktree.repoName)
            .appending(path: worktree.name)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            log("rescue directory failed: \(error.localizedDescription)")
            return
        }

        for relative in files {
            let source = URL(fileURLWithPath: (worktree.path as NSString).appendingPathComponent(relative))
            let target = destination.appending(path: relative)
            do {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.copyItem(at: source, to: target)
                log("rescued \(relative) → \(target.path)")
            } catch {
                log("rescue failed for \(relative): \(error.localizedDescription)")
            }
        }
    }

    /// Guards against a symlink inside a worktree resolving to somewhere else on
    /// disk. String prefixes alone are not enough, because the string can lie.
    private static func isContained(_ path: String, within root: String) -> Bool {
        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return resolved.hasPrefix(resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/")
    }
}
