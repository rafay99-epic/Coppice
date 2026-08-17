import Foundation

/// A coding agent that creates git worktrees. Coppice groups by harness so you
/// can see what each tool left behind, and so a tool you do not use never shows.
enum Harness: String, CaseIterable, Codable, Sendable {
    case claudeCode
    case codex
    case t3Code
    case cursor
    case gemini
    /// A worktree that matches no known agent layout. Created by hand, most likely.
    case manual

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .t3Code: return "T3 Code"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .manual: return "Manual"
        }
    }

    /// SF Symbol shown next to the group header.
    var symbol: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .t3Code: return "bolt.fill"
        case .cursor: return "cursorarrow.rays"
        case .gemini: return "diamond.fill"
        case .manual: return "hand.raised.fill"
        }
    }

    /// The directory whose existence proves this tool has run on this machine.
    /// `manual` has none, so it is never "detected", only inferred from a path.
    func detectDirectory(home: URL) -> URL? {
        switch self {
        case .claudeCode: return home.appending(path: ".claude")
        case .codex: return home.appending(path: ".codex")
        case .t3Code: return home.appending(path: ".t3")
        case .cursor: return home.appending(path: ".cursor")
        case .gemini: return home.appending(path: ".gemini")
        case .manual: return nil
        }
    }

    /// Worktree parents that live under the home directory rather than inside a
    /// repository. Each contains one directory per repo, or per worktree.
    func globalWorktreeRoots(home: URL) -> [URL] {
        switch self {
        case .t3Code: return [home.appending(path: ".t3/worktrees")]
        case .codex: return [home.appending(path: ".codex/worktrees")]
        case .claudeCode: return [home.appending(path: ".claude/worktrees")]
        case .cursor: return [home.appending(path: ".cursor/worktrees")]
        case .gemini, .manual: return []
        }
    }

    /// Worktree parents that live inside the repository itself, relative to its root.
    var inRepoWorktreeDirectory: String? {
        switch self {
        case .claudeCode: return ".claude/worktrees"
        case .codex: return ".codex/worktrees"
        case .cursor: return ".cursor/worktrees"
        case .t3Code, .gemini, .manual: return nil
        }
    }

    /// Which harness owns a path, decided by prefix. Order matters only in that
    /// the in-repo directories are distinctive enough not to collide.
    static func owning(path: String, home: URL) -> Harness {
        for harness in allCases where harness != .manual {
            for root in harness.globalWorktreeRoots(home: home)
            where path.hasPrefix(root.path + "/") {
                return harness
            }
            if let dir = harness.inRepoWorktreeDirectory, path.contains("/\(dir)/") {
                return harness
            }
        }
        return .manual
    }

    /// Every harness with its detect directory present.
    static func detected(home: URL, fileManager: FileManager = .default) -> [Harness] {
        allCases.filter { harness in
            guard let dir = harness.detectDirectory(home: home) else { return false }
            return fileManager.fileExists(atPath: dir.path)
        }
    }
}

/// Claude Code stores per-project session state in `~/.claude/projects/<slug>`,
/// where the slug is the absolute path with `/`, `.` and `_` all replaced by `-`.
/// The directory's modification date is a free, accurate "when did an agent last
/// work here" signal that costs one stat call.
enum SessionHistory {
    static func slug(for path: String) -> String {
        String(path.map { char in
            (char == "/" || char == "." || char == "_") ? "-" : char
        })
    }

    /// When an agent last touched this worktree, or nil if it never did.
    static func lastActivity(
        forWorktreeAt path: String,
        home: URL,
        fileManager: FileManager = .default
    ) -> Date? {
        let dir = home
            .appending(path: ".claude/projects")
            .appending(path: slug(for: path))
        guard let values = try? dir.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        _ = fileManager
        return values.contentModificationDate
    }
}
