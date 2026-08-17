import Foundation

/// Discovers git worktrees and decides what may be done with each one.
///
/// Every path this uses is injected, so the whole engine runs against a fixture
/// repository in tests with no reference to the real home directory.
/// `@unchecked` because `FileManager` carries no Sendable annotation. Every use
/// here is a stateless query against an injected instance, so crossing an actor
/// boundary is safe.
struct WorktreeScanner: @unchecked Sendable {
    let home: URL
    /// Directories that may contain repositories (`~/Code` and friends).
    let codeRoots: [URL]
    /// How recently an agent session counts as "recent" for the soft warning.
    let recentSessionWindow: TimeInterval
    let fileManager: FileManager

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        codeRoots: [URL],
        recentSessionWindow: TimeInterval = 24 * 3600,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.codeRoots = codeRoots
        self.recentSessionWindow = recentSessionWindow
        self.fileManager = fileManager
    }

    // MARK: - Discovery

    /// Every repository worth asking about worktrees.
    ///
    /// Two sources. Repositories under the user's code roots, found by looking
    /// for `.git` one and two levels down, and the agent worktree roots under
    /// home, which are the reason this app exists and are never inside a code
    /// root. Both are needed: a worktree in `~/.t3/worktrees` is only reachable
    /// through its parent repository, and an orphan is only reachable directly.
    func discoverRepositories() -> [String] {
        var found: Set<String> = []

        for root in codeRoots {
            for candidate in children(of: root) {
                if isRepository(candidate) {
                    found.insert(candidate.resolvingSymlinksInPath().path)
                    continue
                }
                // One level deeper catches ~/Code/org/repo layouts.
                for nested in children(of: candidate) where isRepository(nested) {
                    found.insert(nested.resolvingSymlinksInPath().path)
                }
            }
        }
        return found.sorted()
    }

    /// Agent worktree directories present on this machine, with the harness that
    /// owns each. These are scanned directly so orphans still appear.
    func agentWorktreeRoots() -> [(harness: Harness, root: URL)] {
        Harness.allCases.flatMap { harness in
            harness.globalWorktreeRoots(home: home)
                .filter { fileManager.fileExists(atPath: $0.path) }
                .map { (harness, $0) }
        }
    }

    private func children(of directory: URL) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }
        return entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func isRepository(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appending(path: ".git").path)
    }

    // MARK: - Inventory

    /// Every worktree across every discovered repository, plus any orphan found
    /// under an agent root whose parent repository has vanished.
    func inventory() -> [Worktree] {
        var byPath: [String: Worktree] = [:]

        for repo in discoverRepositories() {
            for worktree in worktrees(inRepository: repo) {
                byPath[worktree.path] = worktree
            }
        }

        // Anything under an agent root that no repository claimed is an orphan:
        // its parent repo is gone, so no `git worktree list` will ever mention it.
        for (harness, root) in agentWorktreeRoots() {
            for candidate in orphanCandidates(under: root) where byPath[candidate] == nil {
                byPath[candidate] = Worktree(
                    path: candidate,
                    repoPath: root.path,
                    branch: nil,
                    head: "",
                    harness: harness,
                    isMain: false,
                    isPrunable: false,
                    isLocked: false,
                    isOrphan: true
                )
            }
        }

        return byPath.values.sorted { $0.path < $1.path }
    }

    /// Agent roots nest one directory per repository, so a worktree is either a
    /// direct child or a grandchild. Both shapes are checked.
    private func orphanCandidates(under root: URL) -> [String] {
        var candidates: [String] = []
        for child in children(of: root) {
            if hasGitPointer(child) {
                candidates.append(child.resolvingSymlinksInPath().path)
            } else {
                for grandchild in children(of: child) where hasGitPointer(grandchild) {
                    candidates.append(grandchild.resolvingSymlinksInPath().path)
                }
            }
        }
        return candidates
    }

    /// A linked worktree has a `.git` *file* pointing at the parent repository,
    /// not a `.git` directory.
    private func hasGitPointer(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.appending(path: ".git").path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    func worktrees(inRepository repo: String) -> [Worktree] {
        let result = Git.worktreeList(repo: repo)
        guard result.succeeded else { return [] }
        return Self.parseWorktreeList(result.stdout, repoPath: repo, home: home)
    }

    /// Parses `git worktree list --porcelain`.
    ///
    /// Records are separated by blank lines. The first record is always the
    /// repository's own working copy. `prunable` and `locked` are the two flags
    /// that change what Coppice is allowed to do.
    static func parseWorktreeList(_ output: String, repoPath: String, home: URL) -> [Worktree] {
        var worktrees: [Worktree] = []
        var path: String?
        var head = ""
        var branch: String?
        var prunable = false
        var locked = false
        var isFirst = true

        func flush() {
            defer {
                path = nil; head = ""; branch = nil; prunable = false; locked = false
            }
            guard let path else { return }
            worktrees.append(
                Worktree(
                    path: path,
                    repoPath: repoPath,
                    branch: branch,
                    head: head,
                    harness: Harness.owning(path: path, home: home),
                    isMain: isFirst,
                    isPrunable: prunable,
                    isLocked: locked,
                    isOrphan: false
                )
            )
            isFirst = false
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("worktree ") {
                path = String(line.dropFirst("worktree ".count))
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "prunable" || line.hasPrefix("prunable ") {
                prunable = true
            } else if line == "locked" || line.hasPrefix("locked ") {
                locked = true
            }
        }
        flush()
        return worktrees
    }

    // MARK: - Verdict

    /// The one answer Coppice gives for a worktree.
    ///
    /// Rules are evaluated in order and the first match wins, so the reason shown
    /// is the most actionable one. `liveProcess` is checked before any git state
    /// because it is the only rule that also blocks a sweep: if a worktree is
    /// both dirty and busy, reporting "dirty" would wrongly allow the sweep.
    func verdict(for worktree: Worktree, holders: [ProcessProbe.Holder], now: Date = Date()) -> Verdict {
        if worktree.isMain { return .blocked(.mainWorktree) }
        if worktree.isPrunable { return .prunable }

        if let holder = ProcessProbe.holder(of: worktree.path, among: holders) {
            return .blocked(.liveProcess(command: holder.command, pid: holder.pid))
        }

        if worktree.isOrphan {
            // No repository can reclaim an orphan, so git state is unknowable.
            // Ignored config is still checked: it is the only thing here that
            // cannot be recovered from anywhere else.
            let ignored = ignoredConfigFiles(in: worktree.path)
            return ignored.isEmpty ? .orphan : .blocked(.ignoredConfig(files: ignored))
        }

        guard isInsideAllowedRoot(worktree.path) else { return .blocked(.outsideScanRoots) }
        if worktree.isLocked { return .blocked(.locked(reason: lockReason(worktree))) }

        if let operation = gitOperationInProgress(worktree) {
            return .blocked(.gitOperationInProgress(operation: operation))
        }

        let status = Git.status(worktree: worktree.path)
        let untracked = status.filter { $0.hasPrefix("??") }.count
        let modified = status.count - untracked
        if modified > 0 { return .blocked(.uncommittedChanges(count: modified)) }
        if untracked > 0 { return .blocked(.untrackedFiles(count: untracked)) }

        let defaultBranch = Git.defaultBranch(repo: worktree.repoPath)
        if let unpushed = Git.unpushedCount(worktree: worktree.path) {
            if unpushed > 0 { return .blocked(.unpushedCommits(count: unpushed)) }
        } else if let defaultBranch,
                  let ahead = Git.commitsAheadOfDefault(worktree: worktree.path, defaultBranch: defaultBranch),
                  ahead > 0 {
            // No upstream at all. The commits exist only here.
            return .blocked(.aheadOfDefault(count: ahead))
        }

        // Git reports clean at this point. That is exactly when gitignored
        // config is most dangerous: it is invisible to every check above and has
        // no copy in the repository or on the remote.
        let ignored = ignoredConfigFiles(in: worktree.path)
        if !ignored.isEmpty { return .blocked(.ignoredConfig(files: ignored)) }

        if let submodule = Git.dirtySubmodules(worktree: worktree.path).first {
            return .blocked(.dirtySubmodule(name: submodule))
        }

        return cautions(for: worktree, defaultBranch: defaultBranch, now: now)
    }

    private func cautions(for worktree: Worktree, defaultBranch: String?, now: Date) -> Verdict {
        var cautions: [Caution] = []

        if let last = SessionHistory.lastActivity(forWorktreeAt: worktree.path, home: home, fileManager: fileManager) {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < recentSessionWindow {
                cautions.append(.recentSession(hoursAgo: max(1, Int(elapsed / 3600))))
            }
        }

        if let branch = worktree.branch, let defaultBranch,
           !Git.isMerged(branch: branch, into: defaultBranch, repo: worktree.repoPath) {
            cautions.append(.branchNotMerged)
        }

        if let branch = worktree.branch {
            let stashes = Git.stashCount(repo: worktree.repoPath, referencing: branch)
            if stashes > 0 { cautions.append(.stashReferences(count: stashes)) }
        }

        if let created = try? fileManager.attributesOfItem(atPath: worktree.path)[.creationDate] as? Date {
            let age = now.timeIntervalSince(created)
            if age < 3600 { cautions.append(.veryNew(minutesOld: max(1, Int(age / 60)))) }
        }

        return cautions.isEmpty ? .safe : .caution(cautions)
    }

    private func lockReason(_ worktree: Worktree) -> String {
        let result = Git.run(["worktree", "list", "--porcelain"], in: worktree.repoPath)
        for line in result.lines where line.hasPrefix("locked ") {
            return String(line.dropFirst("locked ".count))
        }
        return ""
    }

    /// Rebase, merge, cherry-pick or bisect left half-finished. Removing the
    /// worktree mid-operation loses whatever the operation was holding.
    private func gitOperationInProgress(_ worktree: Worktree) -> String? {
        guard let gitDir = Git.gitDirectory(worktree: worktree.path) else { return nil }
        let markers: [(file: String, name: String)] = [
            ("MERGE_HEAD", "Merge"),
            ("REBASE_HEAD", "Rebase"),
            ("rebase-merge", "Rebase"),
            ("rebase-apply", "Rebase"),
            ("CHERRY_PICK_HEAD", "Cherry-pick"),
            ("REVERT_HEAD", "Revert"),
            ("BISECT_LOG", "Bisect"),
        ]
        for marker in markers
        where fileManager.fileExists(atPath: (gitDir as NSString).appendingPathComponent(marker.file)) {
            return marker.name
        }
        return nil
    }

    /// Removal is confined to the configured roots and the agent worktree
    /// directories. A path reached through a symlink resolves first, so a link
    /// pointing outside cannot smuggle a deletion past this check.
    func isInsideAllowedRoot(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let allowed = codeRoots.map { $0.resolvingSymlinksInPath().path }
            + agentWorktreeRoots().map { $0.root.resolvingSymlinksInPath().path }
        return allowed.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
    }

    // MARK: - Ignored config

    /// Filenames that hold real, unrecoverable local configuration.
    static let configPrefixes = [".env"]
    static let configSuffixes = [".local"]
    static let configExact = [".dev.vars", ".envrc", ".secrets"]
    /// Templates are committed and carry no secrets, so they never block.
    static let configExclusions = [".env.example", ".env.sample", ".env.template", ".env.defaults"]

    /// Gitignored config files inside a worktree.
    ///
    /// Two steps, because either alone is wrong. A filename match alone flags
    /// `.env.example`, which is committed and harmless. Asking git alone
    /// (`status --ignored`) enumerates every file in node_modules. So: match
    /// names shallowly, then let `git check-ignore` decide which are genuinely
    /// ignored. Tracked files fail check-ignore and drop out.
    func ignoredConfigFiles(in worktreePath: String) -> [String] {
        let candidates = configCandidates(in: worktreePath)
        guard !candidates.isEmpty else { return [] }

        let relative = candidates.map { path -> String in
            let prefix = worktreePath.hasSuffix("/") ? worktreePath : worktreePath + "/"
            return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Git.executable)
        process.arguments = ["-C", worktreePath, "check-ignore", "--stdin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            // Without git's answer, assume the worst and treat every candidate
            // as ignored. Over-blocking is recoverable; over-deleting is not.
            return relative.sorted()
        }
        input.fileHandleForWriting.write(Data(relative.joined(separator: "\n").utf8))
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .sorted()
    }

    /// Config-shaped filenames within three levels, skipping artifact directories.
    private func configCandidates(in root: String, maxDepth: Int = 3) -> [String] {
        var results: [String] = []

        func walk(_ directory: String, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
            for entry in entries {
                if entry == ".git" || ArtifactScanner.artifactNames.contains(entry) { continue }
                let full = (directory as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: full, isDirectory: &isDirectory) else { continue }
                if isDirectory.boolValue {
                    walk(full, depth: depth + 1)
                } else if Self.looksLikeConfig(entry) {
                    results.append(full)
                }
            }
        }

        walk(root, depth: 1)
        return results
    }

    static func looksLikeConfig(_ filename: String) -> Bool {
        if configExclusions.contains(filename) { return false }
        if configExact.contains(filename) { return true }
        if configPrefixes.contains(where: { filename.hasPrefix($0) }) { return true }
        if configSuffixes.contains(where: { filename.hasSuffix($0) }) { return true }
        return false
    }
}
