import Foundation

enum Harness: String, CaseIterable, Codable, Sendable {
    case claudeCode
    case codex
    case t3Code
    case cursor
    case gemini
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

    func globalWorktreeRoots(home: URL) -> [URL] {
        switch self {
        case .t3Code: return [home.appending(path: ".t3/worktrees")]
        case .codex: return [home.appending(path: ".codex/worktrees")]
        case .claudeCode: return [home.appending(path: ".claude/worktrees")]
        case .cursor: return [home.appending(path: ".cursor/worktrees")]
        case .gemini, .manual: return []
        }
    }

    var inRepoWorktreeDirectory: String? {
        switch self {
        case .claudeCode: return ".claude/worktrees"
        case .codex: return ".codex/worktrees"
        case .cursor: return ".cursor/worktrees"
        case .t3Code, .gemini, .manual: return nil
        }
    }

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

    static func detected(home: URL, fileManager: FileManager = .default) -> [Harness] {
        allCases.filter { harness in
            guard let dir = harness.detectDirectory(home: home) else { return false }
            return fileManager.fileExists(atPath: dir.path)
        }
    }
}

enum SessionHistory {
    static func slug(for path: String) -> String {
        String(path.map { char in
            (char == "/" || char == "." || char == "_") ? "-" : char
        })
    }

    static func lastActivity(forWorktreeAt path: String, home: URL) -> Date? {
        let dir = home
            .appending(path: ".claude/projects")
            .appending(path: slug(for: path))
        guard let values = try? dir.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}
