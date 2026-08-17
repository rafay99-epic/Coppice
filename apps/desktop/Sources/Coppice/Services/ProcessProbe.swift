import Foundation

/// Finds processes whose working directory sits inside a worktree. This is the
/// one rule that blocks a sweep, and the one that makes background scanning safe
/// to act on: an agent, editor or dev server working in a directory is the
/// difference between "regenerable junk" and "someone's live session".
enum ProcessProbe {
    struct Holder: Equatable, Sendable {
        let pid: Int32
        let command: String
        let cwd: String
    }

    /// Every process owned by the current user, with its working directory.
    ///
    /// One `lsof` call for the whole machine rather than one per worktree. With
    /// 30 worktrees the per-directory form (`lsof +D`) would walk every file in
    /// every tree, which on 22 GB of node_modules takes minutes. This returns in
    /// roughly 200 ms regardless of how many worktrees exist.
    static func currentHolders(timeout: TimeInterval = 10) -> [Holder] {
        let user = NSUserName()
        // -a AND the selectors, -d cwd restricts to working directories,
        // -F pcn emits machine-readable pid / command / name records.
        let result = Shell.run(
            "/usr/sbin/lsof",
            ["-a", "-u", user, "-d", "cwd", "-F", "pcn"],
            timeout: timeout
        )
        // lsof exits non-zero when some paths were unreadable, which is normal
        // and does not invalidate the records it did emit. Parse regardless.
        return parse(result.stdout)
    }

    /// Parses lsof's `-F` field output. Records arrive as a `p` line (pid), a `c`
    /// line (command), then one or more file blocks whose `n` line is the path.
    static func parse(_ output: String) -> [Holder] {
        var holders: [Holder] = []
        var pid: Int32?
        var command = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, !value.isEmpty else { continue }
                holders.append(Holder(pid: pid, command: command, cwd: value))
            default:
                continue
            }
        }
        return holders
    }

    /// The first process working inside `path`, or nil when nothing holds it.
    ///
    /// Compares against `path + "/"` as well as equality so a worktree named
    /// `feature` never matches a sibling named `feature-2`.
    static func holder(of path: String, among holders: [Holder]) -> Holder? {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return holders.first { $0.cwd == path || $0.cwd.hasPrefix(prefix) }
    }
}
