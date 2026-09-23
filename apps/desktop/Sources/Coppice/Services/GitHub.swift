import Foundation

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

enum GitHub {
    private static let executables = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
    ]

    static var executable: String? {
        executables.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executable != nil }

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
