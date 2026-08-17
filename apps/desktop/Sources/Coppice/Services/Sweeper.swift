import Foundation

/// Performs the two destructive operations, and refuses them whenever the world
/// has moved since the verdict was computed.
///
/// The re-verification is the point of this type. Coppice scans in the
/// background, so a verdict can be minutes old by the time a button is pressed,
/// and in those minutes an agent may have opened the very worktree that was
/// about to be deleted.
enum Sweeper {
    struct Outcome: Sendable {
        var freedBytes: Int64 = 0
        var removedPaths: [String] = []
        var skipped: [(path: String, reason: String)] = []
        var failures: [(path: String, error: String)] = []

        var didAnything: Bool { !removedPaths.isEmpty }
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
        log: (String) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        let holders = ProcessProbe.currentHolders()

        for report in reports {
            let worktree = report.worktree

            // Re-check liveness now, not when the list was built.
            if let holder = ProcessProbe.holder(of: worktree.path, among: holders) {
                outcome.skipped.append((worktree.path, "\(holder.command) started working here"))
                log("sweep skipped \(worktree.path): held by \(holder.command) (\(holder.pid))")
                continue
            }
            guard scanner.isInsideAllowedRoot(worktree.path) else {
                outcome.skipped.append((worktree.path, "outside the configured roots"))
                continue
            }

            // Rescan artifacts rather than trusting the cached list, so a folder
            // deleted since the scan is not deleted twice and a new one is caught.
            for artifact in ArtifactScanner.scan(worktree: worktree.path, fileManager: fileManager) {
                guard isContained(artifact.path, within: worktree.path) else {
                    outcome.skipped.append((artifact.path, "resolved outside its worktree"))
                    continue
                }
                let size = ArtifactScanner.allocatedSize(of: artifact.path, fileManager: fileManager)
                do {
                    try fileManager.removeItem(atPath: artifact.path)
                    outcome.freedBytes += size
                    outcome.removedPaths.append(artifact.path)
                    log("swept \(artifact.path) (\(Format.bytes(size)))")
                } catch {
                    outcome.failures.append((artifact.path, error.localizedDescription))
                    log("sweep failed \(artifact.path): \(error.localizedDescription)")
                }
            }
        }
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
                outcome.failures.append((repo, result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
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
    static func remove(
        report: WorktreeReport,
        scanner: WorktreeScanner,
        deleteBranch: Bool,
        rescueDirectory: URL?,
        fileManager: FileManager = .default,
        log: (String) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        let worktree = report.worktree

        // 1. Recompute from scratch. A cached verdict is never trusted here.
        let holders = ProcessProbe.currentHolders()
        let current = scanner.verdict(for: worktree, holders: holders)
        guard current.canRemove else {
            outcome.skipped.append((worktree.path, current.label))
            log("remove refused \(worktree.path): \(current.label)")
            return outcome
        }
        guard scanner.isInsideAllowedRoot(worktree.path) else {
            outcome.skipped.append((worktree.path, "outside the configured roots"))
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

        let size = ArtifactScanner.allocatedSize(of: worktree.path, fileManager: fileManager)

        // 3. Trash, not remove. Unique content has no other undo.
        do {
            try fileManager.trashItem(at: URL(fileURLWithPath: worktree.path), resultingItemURL: nil)
            outcome.freedBytes += size
            outcome.removedPaths.append(worktree.path)
            log("removed \(worktree.path) → Trash (\(Format.bytes(size)))")
        } catch {
            outcome.failures.append((worktree.path, error.localizedDescription))
            log("remove failed \(worktree.path): \(error.localizedDescription)")
            return outcome // never continue past a failed step
        }

        // 4. Only now is it safe to clear the metadata.
        let pruneResult = Git.prune(repo: worktree.repoPath)
        if !pruneResult.succeeded {
            outcome.failures.append((worktree.repoPath, "prune failed: \(pruneResult.stderr)"))
            return outcome
        }

        // 5. Opt-in, and `-d` so git keeps its veto over unmerged work.
        if deleteBranch, let branch = worktree.branch {
            let result = Git.deleteBranch(branch, repo: worktree.repoPath)
            if result.succeeded {
                log("deleted branch \(branch)")
            } else {
                outcome.skipped.append((branch, "git kept the branch: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"))
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

/// Shared formatting so sizes read the same in the menu bar, the list and the log.
enum Format {
    static func bytes(_ value: Int64) -> String {
        guard value > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: value)
    }
}
