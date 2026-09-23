import Foundation

enum ArtifactScanner {
    static let ungatedNames: Set<String> = [
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".gradle", ".svelte-kit",
        ".astro", ".vite", "DerivedData", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".next-env",
    ]

    static let gatedNames: [String: [String]] = [
        "node_modules": ["package.json"],
        "target": ["Cargo.toml"],
        "Pods": ["Podfile"],
        ".build": ["Package.swift"],
        "Carthage": ["Cartfile"],
        "dist": ["package.json"],
        "build": ["package.json"],
        "out": ["package.json"],
        "vendor": ["composer.json", "Gemfile"],
        ".venv": ["requirements.txt", "pyproject.toml", "setup.py"],
        "venv": ["requirements.txt", "pyproject.toml", "setup.py"],
    ]

    static let artifactNames: Set<String> = ungatedNames.union(gatedNames.keys)

    static func scan(
        worktree: String,
        maxDepth: Int = 6,
        fileManager: FileManager = .default
    ) -> [Artifact] {
        var found: [Artifact] = []

        func walk(_ directory: String, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return }
            for entry in entries {
                if entry == ".git" { continue }
                let full = (directory as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: full, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                if qualifies(name: entry, parent: directory, fileManager: fileManager) {
                    if !isTracked(full, in: worktree) {
                        found.append(Artifact(path: full, kind: entry, bytes: 0))
                    }
                    continue
                }
                walk(full, depth: depth + 1)
            }
        }

        walk(worktree, depth: 1)
        return found
    }

    static func isTracked(_ path: String, in worktree: String) -> Bool {
        let prefix = worktree.hasSuffix("/") ? worktree : worktree + "/"
        let relative = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
        return !Git.run(["ls-files", "--", relative], in: worktree).trimmed.isEmpty
    }

    static func qualifies(name: String, parent: String, fileManager: FileManager = .default) -> Bool {
        if ungatedNames.contains(name) { return true }
        guard let manifests = gatedNames[name] else { return false }
        return manifests.contains { manifest in
            fileManager.fileExists(atPath: (parent as NSString).appendingPathComponent(manifest))
        }
    }

    static func allocatedSize(of path: String, fileManager: FileManager = .default) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func measure(
        worktree: String,
        fileManager: FileManager = .default
    ) -> (artifacts: [Artifact], artifactBytes: Int64, uniqueBytes: Int64) {
        var artifacts = scan(worktree: worktree, fileManager: fileManager)
        var artifactBytes: Int64 = 0
        for index in artifacts.indices {
            let size = allocatedSize(of: artifacts[index].path, fileManager: fileManager)
            artifacts[index].bytes = size
            artifactBytes += size
        }
        let total = allocatedSize(of: worktree, fileManager: fileManager)
        return (artifacts, artifactBytes, max(0, total - artifactBytes))
    }
}
