import Foundation

enum ProcessProbe {
    struct Holder: Equatable, Sendable {
        let pid: Int32
        let command: String
        let cwd: String
    }

    static func currentHolders(timeout: TimeInterval = 10) -> [Holder] {
        let user = NSUserName()
        let result = Shell.run(
            "/usr/sbin/lsof",
            ["-a", "-u", user, "-d", "cwd", "-F", "pcn"],
            timeout: timeout
        )
        return parse(result.stdout).filter { $0.command != "git" }
    }

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

    static func holder(of path: String, among holders: [Holder]) -> Holder? {
        let prefix = path.hasSuffix("/") ? path : path + "/"
        return holders.first { $0.cwd == path || $0.cwd.hasPrefix(prefix) }
    }
}
