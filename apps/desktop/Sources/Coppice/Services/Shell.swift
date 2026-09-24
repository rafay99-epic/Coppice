import Foundation

enum Shell {
    struct Result: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
        var succeeded: Bool { status == 0 }
        var trimmed: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
        var lines: [String] { stdout.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) }
    }

    @discardableResult
    static func run(
        _ executable: String,
        _ arguments: [String],
        cwd: String? = nil,
        timeout: TimeInterval = 20
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        environment["LC_ALL"] = "C"
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let started = DispatchTime.now()
        do {
            try process.run()
        } catch {
            Log.shared.error("could not launch \(executable): \(error.localizedDescription)")
            return Result(status: -1, stdout: "", stderr: "\(error)")
        }

        let lock = NSLock()
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.syntaxlabtechnology.coppice.shell", attributes: .concurrent)

        for (pipe, isStdout) in [(outPipe, true), (errPipe, false)] {
            queue.async(group: group) {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock()
                if isStdout { outData = data } else { errData = data }
                lock.unlock()
            }
        }

        let deadline = DispatchWorkItem {
            guard process.isRunning else { return }
            Log.shared.error("timed out after \(Int(timeout))s: \(executable) \(arguments.joined(separator: " "))")
            process.terminate()
        }
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)

        process.waitUntilExit()
        deadline.cancel()
        group.wait()

        lock.lock()
        let out = String(decoding: outData, as: UTF8.self)
        let err = String(decoding: errData, as: UTF8.self)
        lock.unlock()

        Telemetry.shared.record(
            command: Telemetry.label(executable, arguments, cwd: cwd),
            seconds: Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000_000,
            status: process.terminationStatus
        )
        return Result(status: process.terminationStatus, stdout: out, stderr: err)
    }
}

enum Git {
    static let executable = "/usr/bin/git"

    static func run(_ arguments: [String], in repo: String, timeout: TimeInterval = 20) -> Shell.Result {
        Shell.run(executable, ["-C", repo] + arguments, timeout: timeout)
    }

    static func worktreeList(repo: String) -> Shell.Result {
        run(["worktree", "list", "--porcelain"], in: repo)
    }

    static func status(worktree: String) -> [String] {
        run(["status", "--porcelain", "--untracked-files=normal"], in: worktree).lines
    }

    static func unpushedCount(worktree: String) -> Int? {
        let upstream = run(["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], in: worktree)
        guard upstream.succeeded else { return nil }
        let result = run(["rev-list", "--count", "@{u}..HEAD"], in: worktree)
        guard result.succeeded else { return nil }
        return Int(result.trimmed)
    }

    static func commitsAheadOfDefault(worktree: String, defaultBranch: String) -> Int? {
        let result = run(["rev-list", "--count", "\(defaultBranch)..HEAD"], in: worktree)
        guard result.succeeded else { return nil }
        return Int(result.trimmed)
    }

    static func defaultBranch(repo: String) -> String? {
        let symbolic = run(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], in: repo)
        if symbolic.succeeded, !symbolic.trimmed.isEmpty { return symbolic.trimmed }
        for candidate in ["main", "master"]
        where run(["rev-parse", "--verify", "--quiet", candidate], in: repo).succeeded {
            return candidate
        }
        return nil
    }

    static func isMerged(branch: String, into target: String, repo: String) -> Bool {
        let result = run(["merge-base", "--is-ancestor", branch, target], in: repo)
        return result.status == 0
    }

    static func stashCount(repo: String, referencing branch: String) -> Int {
        run(["stash", "list"], in: repo).lines.filter { $0.contains(branch) }.count
    }

    static func dirtySubmodules(worktree: String) -> [String] {
        parseDirtySubmodules(run(["status", "--porcelain=v2", "--ignore-submodules=none"], in: worktree).stdout)
    }

    static func parseDirtySubmodules(_ porcelain: String) -> [String] {
        let fieldsBeforePath = ["1": 8, "2": 9, "u": 10]
        return porcelain.split(separator: "\n").compactMap { line in
            let kind = String(line.prefix(1))
            guard let pathIndex = fieldsBeforePath[kind] else { return nil }
            let fields = line.split(separator: " ", maxSplits: pathIndex, omittingEmptySubsequences: false)
            guard fields.count > pathIndex else { return nil }
            let submodule = fields[2]
            guard submodule.hasPrefix("S"), submodule != "S..." else { return nil }
            return String(fields[pathIndex].split(separator: "\t").first ?? fields[pathIndex])
        }
    }

    static func prune(repo: String) -> Shell.Result {
        run(["worktree", "prune"], in: repo)
    }

    static func deleteBranch(_ branch: String, repo: String) -> Shell.Result {
        run(["branch", "-d", branch], in: repo)
    }

    static func gitDirectory(worktree: String) -> String? {
        let result = run(["rev-parse", "--absolute-git-dir"], in: worktree)
        return result.succeeded ? result.trimmed : nil
    }
}
