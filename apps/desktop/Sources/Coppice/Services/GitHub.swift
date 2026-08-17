import Foundation

/// The pull request a worktree's branch belongs to, when there is one.
///
/// This is the strongest available signal about whether a worktree still
/// matters. A branch whose PR is merged or closed is finished work, and
/// uncommitted scratch edits left in it are almost always debris rather than
/// something to protect.
struct PullRequest: Sendable, Hashable {
    enum State: String, Sendable {
        case open = "OPEN"
        case closed = "CLOSED"
        case merged = "MERGED"
    }

    let number: Int
    let state: State
    let title: String
    let url: String
    let isDraft: Bool

    /// Whether the PR being in this state means the branch is done with.
    var isSettled: Bool { state == .merged || state == .closed }

    var summary: String {
        switch state {
        case .open: return isDraft ? "Draft PR #\(number)" : "PR #\(number) open"
        case .merged: return "PR #\(number) merged"
        case .closed: return "PR #\(number) closed"
        }
    }

    var symbol: String {
        switch state {
        case .open: return isDraft ? "circle.dashed" : "arrow.trianglehead.branch"
        case .merged: return "arrow.triangle.merge"
        case .closed: return "xmark.circle"
        }
    }
}

/// Reads pull request state through the GitHub CLI.
///
/// `gh` rather than the REST API on purpose: it already holds the user's
/// credentials, handles enterprise hosts and SSH remotes, and needs no token
/// management inside Coppice. If it is missing or signed out, every lookup
/// returns nothing and the app carries on without the extra context.
enum GitHub {
    /// Candidate install locations. `gh` is not on the PATH a GUI app inherits,
    /// which is why this is a list of absolute paths rather than a bare name.
    private static let executables = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    static var executable: String? {
        executables.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executable != nil }

    /// Every pull request in a repository, keyed by branch name.
    ///
    /// One call per repository rather than one per worktree. A machine with 53
    /// worktrees across 23 repositories makes 23 network calls this way instead
    /// of 53, and the result covers worktrees whose branches share a PR.
    ///
    /// Returns an empty map on any failure: no `gh`, not signed in, no remote,
    /// not a GitHub repository, or a network problem. Missing PR context is a
    /// missing hint, never an error the user has to deal with.
    static func pullRequests(repo: String, limit: Int = 200) -> [String: PullRequest] {
        guard let executable else { return [:] }

        let result = Shell.run(
            executable,
            [
                "pr", "list",
                "--state", "all",
                "--limit", String(limit),
                "--json", "number,state,title,url,isDraft,headRefName",
            ],
            cwd: repo,
            timeout: 25
        )
        guard result.succeeded, let data = result.stdout.data(using: .utf8) else { return [:] }
        return parse(data)
    }

    static func parse(_ data: Data) -> [String: PullRequest] {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return [:] }

        var byBranch: [String: PullRequest] = [:]
        for row in rows {
            guard let state = PullRequest.State(rawValue: row.state) else { continue }
            let pullRequest = PullRequest(
                number: row.number,
                state: state,
                title: row.title,
                url: row.url,
                isDraft: row.isDraft
            )
            // A branch can carry several PRs over its life. Prefer the open one,
            // then the highest number, so the entry reflects its current state
            // rather than whichever the API happened to list first.
            if let existing = byBranch[row.headRefName] {
                let replaces = (pullRequest.state == .open && existing.state != .open)
                    || (pullRequest.state == .open) == (existing.state == .open)
                    && pullRequest.number > existing.number
                if !replaces { continue }
            }
            byBranch[row.headRefName] = pullRequest
        }
        return byBranch
    }

    private struct Row: Decodable {
        let number: Int
        let state: String
        let title: String
        let url: String
        let isDraft: Bool
        let headRefName: String
    }
}
