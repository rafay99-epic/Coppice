import Foundation

struct WorktreeScanner: @unchecked Sendable {
    let home: URL
    let codeRoots: [URL]
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

    func discoverRepositories() -> [String] {
        var found: Set<String> = []

        for root in codeRoots {
            for candidate in children(of: root) {
                if isRepository(candidate) {
                    found.insert(candidate.resolvingSymlinksInPath().path)
                    continue
                }
                for nested in children(of: candidate) where isRepository(nested) {
                    found.insert(nested.resolvingSymlinksInPath().path)
                }
            }
        }
        for (_, root) in agentWorktreeRoots() {
            for candidate in orphanCandidates(under: root) {
                if let repo = parentRepository(ofWorktree: candidate) { found.insert(repo) }
            }
        }
        return found.sorted()
    }

    func parentRepository(ofWorktree path: String) -> String? {
        let result = Git.run(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: path)
        guard result.succeeded, !result.trimmed.isEmpty else { return nil }
        let common = URL(fileURLWithPath: result.trimmed).resolvingSymlinksInPath()
        let repo = common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
        return fileManager.fileExists(atPath: repo.path) ? repo.path : nil
    }

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

    func inventory() -> [Worktree] {
        var byPath: [String: Worktree] = [:]

        for repo in discoverRepositories() {
            for worktree in worktrees(inRepository: repo) {
                byPath[worktree.path] = worktree
            }
        }

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

        return byPath.values.filter { !$0.isMain }.sorted { $0.path < $1.path }
    }

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

    static func parseWorktreeList(_ output: String, repoPath: String, home: URL) -> [Worktree] {
        var worktrees: [Worktree] = []
        var path: String?
        var head = ""
        var branch: String?
        var prunable = false
        var locked = false
        var lockReason = ""
        var isFirst = true

        func flush() {
            defer {
                path = nil; head = ""; branch = nil; prunable = false; locked = false; lockReason = ""
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
                    isOrphan: false,
                    lockReason: lockReason
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
                lockReason = String(line.dropFirst("locked".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        flush()
        return worktrees
    }

    func verdict(
        for worktree: Worktree,
        holders: [ProcessProbe.Holder],
        prMerged: Bool = false,
        now: Date = Date()
    ) -> Verdict {
        if !worktree.isMain, worktree.isPrunable { return .prunable }
        if let first = blockers(for: worktree, holders: holders, prMerged: prMerged, firstOnly: true).first {
            return .blocked(first)
        }
        if worktree.isOrphan { return .orphan }
        return cautions(for: worktree, prMerged: prMerged, now: now)
    }

    func blockers(
        for worktree: Worktree,
        holders: [ProcessProbe.Holder],
        prMerged: Bool = false,
        firstOnly: Bool = false
    ) -> [Blocker] {
        var found: [Blocker] = []
        func hit(_ blocker: Blocker) -> Bool {
            found.append(blocker)
            return firstOnly
        }

        if worktree.isMain, hit(.mainWorktree) { return found }

        if let holder = ProcessProbe.holder(of: worktree.path, among: holders),
           hit(.liveProcess(command: holder.command, pid: holder.pid)) {
            return found
        }

        if worktree.isOrphan {
            let ignored = ignoredConfigFiles(in: worktree.path)
            if !ignored.isEmpty { _ = hit(.ignoredConfig(files: ignored)) }
            return found
        }

        if !isInsideAllowedRoot(worktree.path), hit(.outsideScanRoots) { return found }
        if worktree.isLocked, hit(.locked(reason: worktree.lockReason)) { return found }

        if let operation = gitOperationInProgress(worktree),
           hit(.gitOperationInProgress(operation: operation)) {
            return found
        }

        let status = Git.status(worktree: worktree.path)
        let untracked = status.filter { $0.hasPrefix("??") }.count
        let modified = status.count - untracked
        if modified > 0, hit(.uncommittedChanges(count: modified)) { return found }
        if untracked > 0, hit(.untrackedFiles(count: untracked)) { return found }

        if let unpushed = Git.unpushedCount(worktree: worktree.path) {
            if unpushed > 0, hit(.unpushedCommits(count: unpushed)) { return found }
        } else if !prMerged,
                  let defaultBranch = Git.defaultBranch(repo: worktree.repoPath),
                  let ahead = Git.commitsAheadOfDefault(worktree: worktree.path, defaultBranch: defaultBranch),
                  ahead > 0,
                  hit(.aheadOfDefault(count: ahead)) {
            return found
        }

        let ignored = ignoredConfigFiles(in: worktree.path)
        if !ignored.isEmpty, hit(.ignoredConfig(files: ignored)) { return found }

        if let submodule = Git.dirtySubmodules(worktree: worktree.path).first,
           hit(.dirtySubmodule(name: submodule)) {
            return found
        }
        return found
    }

    private func cautions(for worktree: Worktree, prMerged: Bool, now: Date) -> Verdict {
        var cautions: [Caution] = []

        if let last = SessionHistory.lastActivity(forWorktreeAt: worktree.path, home: home) {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < recentSessionWindow {
                cautions.append(.recentSession(hoursAgo: max(1, Int(elapsed / 3600))))
            }
        }

        if !prMerged, let branch = worktree.branch,
           let defaultBranch = Git.defaultBranch(repo: worktree.repoPath),
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

    func isInsideAllowedRoot(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let allowed = codeRoots.map { $0.resolvingSymlinksInPath().path }
            + agentWorktreeRoots().map { $0.root.resolvingSymlinksInPath().path }
        return allowed.contains { resolved == $0 || resolved.hasPrefix($0 + "/") }
    }

    static let configPrefixes = [".env"]
    static let configSuffixes = [".local"]
    static let configExact = [".dev.vars", ".envrc", ".secrets"]
    static let configExclusions = [".env.example", ".env.sample", ".env.template", ".env.defaults"]

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
