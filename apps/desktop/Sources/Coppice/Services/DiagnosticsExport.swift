import Foundation

enum DiagnosticsExport {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func bundle(report: String, crashes: [CrashReport]) throws -> URL {
        let files = FileManager.default
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let name = "\(Channel.current.displayName) Diagnostics \(formatter.string(from: Date()))"
        let stage = files.temporaryDirectory.appending(path: name)
        try? files.removeItem(at: stage)
        try files.createDirectory(at: stage.appending(path: "Crash Reports"), withIntermediateDirectories: true)
        defer { try? files.removeItem(at: stage) }

        let log = Log.shared.logFileURL
        for url in [log, log.deletingPathExtension().appendingPathExtension("1.log")] where files.fileExists(atPath: url.path) {
            try files.copyItem(at: url, to: stage.appending(path: url.lastPathComponent))
        }
        for crash in crashes.filter({ $0.channel == .current }).prefix(20) {
            try? files.copyItem(at: crash.url, to: stage.appending(path: "Crash Reports").appending(path: crash.url.lastPathComponent))
        }
        try report.write(to: stage.appending(path: "diagnostics.txt"), atomically: true, encoding: .utf8)

        let zip = files.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appending(path: "\(name).zip")
        try? files.removeItem(at: zip)
        let result = Shell.run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--keepParent", stage.path, zip.path], timeout: 60)
        guard result.succeeded else {
            throw Failure(message: "Could not write the zip: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        Log.shared.write("exported diagnostics → \(zip.path)")
        return zip
    }

    static func issueURL(crash: CrashReport?, environment: String) -> URL? {
        let title = crash.map { "Crash: \($0.kind) in \($0.headline)" } ?? "Bug report"
        var body = "**What happened**\n\n\n**Environment**\n```\n\(environment)\n```\n"
        if let crash {
            body += "\n**Crash**\n```\n\(crash.summary)\n```\n"
        }
        body += "\nThe diagnostics bundle from Settings > Diagnostics has the full log and crash reports."
        var components = URLComponents(string: "https://github.com/\(Updater.repository)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: String(body.prefix(6_000))),
        ]
        return components?.url
    }
}
