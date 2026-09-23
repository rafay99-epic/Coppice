import Foundation

struct Worktree: Identifiable, Hashable, Sendable {
    let path: String
    let repoPath: String
    let branch: String?
    let head: String
    let harness: Harness
    let isMain: Bool
    let isPrunable: Bool
    let isLocked: Bool
    let isOrphan: Bool
    var lockReason: String = ""

    var id: String { path }
    var name: String { (path as NSString).lastPathComponent }
    var repoName: String { (repoPath as NSString).lastPathComponent }
    var displayBranch: String { branch ?? "detached at \(head.prefix(7))" }
}

enum Severity: Equatable, Hashable, Sendable {
    case absolute
    case overridable
}

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
                ? "\(files[0]) is not in git"
                : "\(files.count) local config files are not in git"
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

    var severity: Severity {
        switch self {
        case .mainWorktree, .liveProcess, .outsideScanRoots: return .absolute
        default: return .overridable
        }
    }

    var removalNote: String? {
        func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }
        switch self {
        case .uncommittedChanges(let count):
            return "\(plural(count, "uncommitted change")), kept in the Trash"
        case .untrackedFiles(let count):
            return "\(plural(count, "untracked file")), kept in the Trash"
        case .unpushedCommits(let count):
            return "\(plural(count, "unpushed commit")), kept on the branch"
        case .aheadOfDefault(let count):
            return "\(plural(count, "commit")) not on the default branch, kept on the branch"
        case .dirtySubmodule(let name):
            return "Changes in submodule \(name), kept in the Trash"
        case .gitOperationInProgress(let operation):
            return "The \(operation.lowercased()) in progress is abandoned"
        case .locked:
            return "The worktree lock is released"
        case .ignoredConfig, .mainWorktree, .liveProcess, .outsideScanRoots:
            return nil
        }
    }

    var holdsCommits: Bool {
        switch self {
        case .unpushedCommits, .aheadOfDefault: return true
        default: return false
        }
    }

    var blocksSweep: Bool {
        if case .liveProcess = self { return true }
        return false
    }
}

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

enum Verdict: Equatable, Hashable, Sendable {
    case safe
    case caution([Caution])
    case blocked(Blocker)
    case prunable
    case orphan

    enum Status: Equatable {
        case ready
        case hasWork
        case inUse
        case protected
        case stale
    }

    var status: Status {
        switch self {
        case .safe, .caution, .orphan: return .ready
        case .prunable: return .stale
        case .blocked(.liveProcess): return .inUse
        case .blocked(let blocker): return blocker.severity == .absolute ? .protected : .hasWork
        }
    }

    var canRemove: Bool {
        if case .blocked(let blocker) = self { return blocker.severity == .overridable }
        return true
    }

    var blocker: Blocker? {
        if case .blocked(let blocker) = self { return blocker }
        return nil
    }

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

    var order: Int {
        switch status {
        case .ready: return 0
        case .hasWork: return 1
        case .stale: return 2
        case .inUse: return 3
        case .protected: return 4
        }
    }
}

struct WorktreeReport: Identifiable, Hashable, Sendable {
    let worktree: Worktree
    var verdict: Verdict
    var artifactBytes: Int64
    var uniqueBytes: Int64
    var artifacts: [Artifact]
    var measured: Bool
    var pullRequest: PullRequest?

    var isLikelyDisposable: Bool { pullRequest?.isSettled == true }

    var id: String { worktree.path }
    var totalBytes: Int64 { artifactBytes + uniqueBytes }

    init(
        worktree: Worktree,
        verdict: Verdict,
        artifactBytes: Int64 = 0,
        uniqueBytes: Int64 = 0,
        artifacts: [Artifact] = [],
        measured: Bool = false,
        pullRequest: PullRequest? = nil
    ) {
        self.worktree = worktree
        self.verdict = verdict
        self.artifactBytes = artifactBytes
        self.uniqueBytes = uniqueBytes
        self.artifacts = artifacts
        self.measured = measured
        self.pullRequest = pullRequest
    }
}

struct Artifact: Identifiable, Hashable, Sendable {
    let path: String
    let kind: String
    var bytes: Int64
    var id: String { path }
}
