import Foundation

/// A git worktree found on this machine, plus everything Coppice needs to decide
/// whether touching it is safe. Value type with no I/O so the verdict logic can
/// be tested against fixtures without a real filesystem.
struct Worktree: Identifiable, Hashable, Sendable {
    /// Absolute, symlink-resolved path. Also the identity: one worktree per path.
    let path: String
    /// The repository this worktree belongs to.
    let repoPath: String
    /// Short branch name, or nil when HEAD is detached.
    let branch: String?
    let head: String
    /// Which agent created it, inferred from where it lives.
    let harness: Harness
    /// True for the repository's own working copy, which is never removable.
    let isMain: Bool
    /// Git says the directory is gone and only stale metadata remains.
    let isPrunable: Bool
    /// `git worktree lock` was used. Someone said hands off.
    let isLocked: Bool
    /// The parent repository no longer exists, so no git command can reach this.
    let isOrphan: Bool

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var repoName: String { (repoPath as NSString).lastPathComponent }
    var displayBranch: String { branch ?? "detached at \(head.prefix(7))" }
}

/// A reason removal is refused outright. Every case names the fix, because a
/// block the user cannot clear is just a dead end.
enum Blocker: Equatable, Hashable, Sendable {
    case mainWorktree
    case liveProcess(command: String, pid: Int32)
    case uncommittedChanges(count: Int)
    case untrackedFiles(count: Int)
    case unpushedCommits(count: Int)
    case aheadOfDefault(count: Int)
    case ignoredConfig(files: [String])
    case locked(reason: String)
    case gitOperationInProgress(operation: String)
    case dirtySubmodule(name: String)
    case outsideScanRoots

    /// One line, shown on the row.
    var summary: String {
        switch self {
        case .mainWorktree:
            return "Main worktree"
        case .liveProcess(let command, let pid):
            return "\(command) is running here (pid \(pid))"
        case .uncommittedChanges(let count):
            return "\(count) uncommitted change\(count == 1 ? "" : "s")"
        case .untrackedFiles(let count):
            return "\(count) untracked file\(count == 1 ? "" : "s")"
        case .unpushedCommits(let count):
            return "\(count) unpushed commit\(count == 1 ? "" : "s")"
        case .aheadOfDefault(let count):
            return "\(count) commit\(count == 1 ? "" : "s") not on the default branch"
        case .ignoredConfig(let files):
            return files.count == 1
                ? "\(files[0]) would be destroyed"
                : "\(files.count) ignored config files would be destroyed"
        case .locked:
            return "Locked"
        case .gitOperationInProgress(let operation):
            return "\(operation) in progress"
        case .dirtySubmodule(let name):
            return "Submodule \(name) has changes"
        case .outsideScanRoots:
            return "Outside the configured scan roots"
        }
    }

    /// What the user does to clear it.
    var remedy: String {
        switch self {
        case .mainWorktree:
            return "The repository's own working copy is never removable."
        case .liveProcess:
            return "Close the session, editor or dev server using this directory."
        case .uncommittedChanges:
            return "Commit, stash or discard the changes."
        case .untrackedFiles:
            return "Commit the files, or delete them if they are not needed."
        case .unpushedCommits:
            return "Push the branch so the commits exist somewhere else."
        case .aheadOfDefault:
            return "Push the branch, or merge it into the default branch."
        case .ignoredConfig:
            return "These are gitignored, so git has no copy. Rescue them first."
        case .locked(let reason):
            return reason.isEmpty
                ? "Run git worktree unlock to release it."
                : "Locked: \(reason). Run git worktree unlock to release it."
        case .gitOperationInProgress:
            return "Finish or abort the operation, then rescan."
        case .dirtySubmodule:
            return "Commit or discard the changes inside the submodule."
        case .outsideScanRoots:
            return "Coppice only removes paths inside your configured roots."
        }
    }

    /// Sweep only ever respects the live-process rule. Build artifacts are not
    /// source, so uncommitted work in the same worktree is irrelevant to them.
    var blocksSweep: Bool {
        if case .liveProcess = self { return true }
        return false
    }
}

/// Worth surfacing, not worth refusing. Nothing here can lose work.
enum Caution: Equatable, Hashable, Sendable {
    case recentSession(hoursAgo: Int)
    case branchNotMerged
    case stashReferences(count: Int)
    case veryNew(minutesOld: Int)

    var summary: String {
        switch self {
        case .recentSession(let hours):
            return hours <= 1 ? "Session active within the hour" : "Session \(hours)h ago"
        case .branchNotMerged:
            return "Branch not merged"
        case .stashReferences(let count):
            return "\(count) stash entr\(count == 1 ? "y" : "ies")"
        case .veryNew(let minutes):
            return "Created \(minutes)m ago"
        }
    }
}

/// The single answer Coppice gives for a worktree. Computed, never guessed.
enum Verdict: Equatable, Hashable, Sendable {
    case safe
    case caution([Caution])
    case blocked(Blocker)
    case prunable
    case orphan

    var canRemove: Bool {
        switch self {
        case .safe, .caution, .prunable, .orphan: return true
        case .blocked: return false
        }
    }

    /// Sweeping artifacts is allowed unless something is actively running here.
    var canSweep: Bool {
        switch self {
        case .blocked(let blocker): return !blocker.blocksSweep
        case .prunable: return false
        default: return true
        }
    }

    var label: String {
        switch self {
        case .safe: return "safe"
        case .caution(let list): return list.first?.summary ?? "check"
        case .blocked(let blocker): return blocker.summary
        case .prunable: return "prunable"
        case .orphan: return "orphan"
        }
    }

    /// Sort weight so the list leads with what the user can act on.
    var order: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .prunable: return 2
        case .orphan: return 3
        case .blocked: return 4
        }
    }
}

/// A worktree joined with its verdict and measured size. This is what the UI binds to.
struct WorktreeReport: Identifiable, Hashable, Sendable {
    let worktree: Worktree
    var verdict: Verdict
    /// Bytes in regenerable build artifacts. Recovered by reinstalling.
    var artifactBytes: Int64
    /// Bytes in everything else. Only recoverable from the Trash.
    var uniqueBytes: Int64
    /// Artifact directories found inside, for the sweep.
    var artifacts: [Artifact]
    /// Set once a size walk has finished, so the UI can show a dash until then.
    var measured: Bool

    var id: String { worktree.path }
    var totalBytes: Int64 { artifactBytes + uniqueBytes }

    init(
        worktree: Worktree,
        verdict: Verdict,
        artifactBytes: Int64 = 0,
        uniqueBytes: Int64 = 0,
        artifacts: [Artifact] = [],
        measured: Bool = false
    ) {
        self.worktree = worktree
        self.verdict = verdict
        self.artifactBytes = artifactBytes
        self.uniqueBytes = uniqueBytes
        self.artifacts = artifacts
        self.measured = measured
    }
}

/// A regenerable build-artifact directory inside a worktree.
struct Artifact: Identifiable, Hashable, Sendable {
    let path: String
    let kind: String
    var bytes: Int64
    var id: String { path }
}
