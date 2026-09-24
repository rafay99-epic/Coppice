import Foundation

enum Sweeper {
    struct Item: Sendable, Hashable, Identifiable {
        let path: String
        let reason: String
        var id: String { path + reason }
        var name: String { (path as NSString).lastPathComponent }
    }

    struct Outcome: Sendable {
        var freed: [String: Int64] = [:]
        var removedPaths: [String] = []
        var skipped: [Item] = []
        var failures: [Item] = []
        var trashed: URL?

        var freedBytes: Int64 { freed.values.reduce(0, +) }
        var didAnything: Bool { !removedPaths.isEmpty }
        var hasProblems: Bool { !skipped.isEmpty || !failures.isEmpty }
    }

    struct Progress: Sendable, Equatable {
        let paths: [String]
        var completed = 0
        var freed: [String: Int64] = [:]

        var total: Int { paths.count }
        var current: String? { paths.indices.contains(completed) ? paths[completed] : nil }
        var freedBytes: Int64 { freed.values.reduce(0, +) }
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    static func sweep(
        reports: [WorktreeReport],
        scanner: WorktreeScanner,
        fileManager: FileManager = .default,
        log: (String) -> Void = { _ in },
        onProgress: (Progress) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome()
        let holders = ProcessProbe.currentHolders()
        var progress = Progress(paths: reports.map(\.id))
        let knownSizes = Dictionary(
            reports.flatMap(\.artifacts).map { ($0.path, $0.bytes) },
            uniquingKeysWith: { first, _ in first }
        )

        for report in reports {
            onProgress(progress)
            defer { progress.completed += 1 }

            let worktree = report.worktree

            if let holder = ProcessProbe.holder(of: worktree.path, among: holders) {
                outcome.skipped.append(Item(path: worktree.path, reason: "\(holder.command) started working here"))
                log("sweep skipped \(worktree.path): held by \(holder.command) (\(holder.pid))")
                continue
            }
            guard scanner.isInsideAllowedRoot(worktree.path) else {
                outcome.skipped.append(Item(path: worktree.path, reason: "outside the configured roots"))
                continue
            }

            for artifact in ArtifactScanner.scan(worktree: worktree.path, fileManager: fileManager) {
                guard isContained(artifact.path, within: worktree.path) else {
                    outcome.skipped.append(Item(path: artifact.path, reason: "resolved outside its worktree"))
                    continue
                }
                let size = knownSizes[artifact.path]
                    ?? ArtifactScanner.allocatedSize(of: artifact.path, fileManager: fileManager)
                do {
                    try fileManager.removeItem(atPath: artifact.path)
                    outcome.freed[worktree.path, default: 0] += size
                    outcome.removedPaths.append(artifact.path)
                    log("swept \(artifact.path) (\(Format.bytes(size)))")
                    progress.freed = outcome.freed
                    onProgress(progress)
                } catch {
                    outcome.failures.append(Item(path: artifact.path, reason: error.localizedDescription))
                    log("sweep failed \(artifact.path): \(error.localizedDescription)")
                }
            }
        }
        onProgress(progress)
        return outcome
    }

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

        let holders = ProcessProbe.currentHolders()
        let current = scanner.verdict(
            for: worktree,
            holders: holders,
            prMerged: report.mergedAtHead
        )
        guard current.canRemove else {
            outcome.skipped.append(Item(path: worktree.path, reason: current.label))
            log("remove refused \(worktree.path): \(current.label)")
            return outcome
        }
        if let blocker = current.blocker {
            log("remove with work \(worktree.path): \(blocker.summary)")
        }
        guard scanner.isInsideAllowedRoot(worktree.path) else {
            outcome.skipped.append(Item(path: worktree.path, reason: "outside the configured roots"))
            return outcome
        }

        if let rescueDirectory {
            rescueIgnoredConfig(
                worktree: worktree,
                scanner: scanner,
                into: rescueDirectory,
                fileManager: fileManager,
                log: log
            )
        }

        if worktree.isLocked {
            let unlock = Git.run(["worktree", "unlock", worktree.path], in: worktree.repoPath)
            log(unlock.succeeded ? "unlocked \(worktree.path)" : "unlock failed: \(unlock.stderr)")
        }

        let size = ArtifactScanner.allocatedSize(of: worktree.path, fileManager: fileManager)

        do {
            var trashed: NSURL?
            try fileManager.trashItem(at: URL(fileURLWithPath: worktree.path), resultingItemURL: &trashed)
            outcome.freed[worktree.path] = size
            outcome.trashed = trashed as URL?
            outcome.removedPaths.append(worktree.path)
            log("removed \(worktree.path) → Trash (\(Format.bytes(size)))")
        } catch {
            outcome.failures.append(Item(path: worktree.path, reason: error.localizedDescription))
            log("remove failed \(worktree.path): \(error.localizedDescription)")
            if worktree.isLocked {
                let relock = Git.run(["worktree", "lock", "--reason", worktree.lockReason, worktree.path], in: worktree.repoPath)
                if !relock.succeeded { log("relock failed \(worktree.path): \(relock.stderr)") }
            }
            return outcome
        }

        if worktree.isOrphan { return outcome }
        let pruneResult = Git.prune(repo: worktree.repoPath)
        if !pruneResult.succeeded {
            outcome.failures.append(Item(path: worktree.repoPath, reason: "prune failed: \(pruneResult.stderr)"))
            return outcome
        }

        if deleteBranch, let branch = worktree.branch {
            let result = report.mergedAtHead
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

    static func rescueIgnoredConfig(
        worktree: Worktree,
        scanner: WorktreeScanner,
        into rescueRoot: URL,
        fileManager: FileManager,
        log: (String) -> Void
    ) {
        let files = scanner.ignoredConfigFiles(in: worktree.path)
        guard !files.isEmpty else { return }

        let stamp = Date.now.formatted(.iso8601.timeSeparator(.omitted))
        let destination = rescueRoot
            .appending(path: worktree.repoName)
            .appending(path: "\(worktree.name) \(stamp)")
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

    private static func isContained(_ path: String, within root: String) -> Bool {
        let resolvedRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return resolved.hasPrefix(resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/")
    }
}
