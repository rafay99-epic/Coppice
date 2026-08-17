import Foundation

/// Finds regenerable build output inside a worktree.
///
/// Everything here can be rebuilt by a command the user already runs, which is
/// what makes sweeping safe even in a worktree with uncommitted source changes.
/// A directory only counts when its manifest sits next to it, so a hand-written
/// `build/` directory in a repo with no `package.json` is left alone.
enum ArtifactScanner {
    /// Directory names that are build output wherever they appear. These have no
    /// plausible use as source, so no manifest is required.
    static let ungatedNames: Set<String> = [
        ".next", ".nuxt", ".turbo", ".parcel-cache", ".gradle", ".svelte-kit",
        ".astro", ".vite", "DerivedData", "__pycache__", ".pytest_cache",
        ".mypy_cache", ".ruff_cache", ".next-env",
    ]

    /// Directory names that are build output only when the matching manifest is
    /// a sibling. `target` beside a `Cargo.toml` is Rust output; `target`
    /// anywhere else might be anything.
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

    /// Every name the scanner recognises, used to prune walks elsewhere.
    static let artifactNames: Set<String> = ungatedNames.union(gatedNames.keys)

    /// Artifact directories inside `worktree`.
    ///
    /// Stops descending as soon as a directory matches: a `node_modules` nested
    /// inside another `node_modules` is already counted by its parent, and
    /// walking into it on a 1.3 GB tree costs seconds for nothing.
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
                    found.append(Artifact(path: full, kind: entry, bytes: 0))
                    continue // do not descend, the parent already covers it
                }
                walk(full, depth: depth + 1)
            }
        }

        walk(worktree, depth: 1)
        return found
    }

    /// Whether a directory name counts as an artifact here, applying the gate.
    static func qualifies(name: String, parent: String, fileManager: FileManager = .default) -> Bool {
        if ungatedNames.contains(name) { return true }
        guard let manifests = gatedNames[name] else { return false }
        return manifests.contains { manifest in
            fileManager.fileExists(atPath: (parent as NSString).appendingPathComponent(manifest))
        }
    }

    /// Bytes actually occupied on disk, summed over a directory tree.
    ///
    /// Uses allocated size rather than logical size. On APFS a cloned worktree
    /// shares blocks with its source, so logical size promises space that
    /// deleting will not return, and a tool that over-promises reclaimed space
    /// reads as broken.
    static func allocatedSize(of path: String, fileManager: FileManager = .default) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]

        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles.subtracting(.skipsHiddenFiles)] // include hidden files
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Measures a worktree, splitting regenerable bytes from everything else.
    /// The split drives the UI: artifact bytes are cheap to lose, unique bytes
    /// are not.
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
