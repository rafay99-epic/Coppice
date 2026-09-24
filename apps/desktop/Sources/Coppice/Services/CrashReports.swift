import Foundation

struct LogEntry: Hashable, Sendable {
    let date: Date
    let text: String
}

struct CrashReport: Identifiable, Hashable, Sendable {
    struct Frame: Hashable, Sendable {
        let library: String
        let symbol: String
        let isApp: Bool
        var symbolicated = true
    }

    let url: URL
    let channel: Channel
    let date: Date
    let version: String
    let exception: String
    var kind: String
    var reason: String?
    let frames: [Frame]
    let likely: Int?
    var before: [LogEntry] = []

    var id: String { url.path }
    var headline: String {
        if let likely { return frames[likely].symbol }
        return frames.contains { $0.symbol.contains("CFRunLoopRun") } ? "Main thread idle in the event loop" : exception
    }

    var signature: String { "\(exception)|\(headline)" }

    var summary: String {
        var lines = ["\(kind) · \(channel.displayName) \(version) · \(date.formatted(date: .abbreviated, time: .standard))"]
        if let reason { lines.append(reason) }
        if !before.isEmpty {
            lines.append("Right before:")
            lines += before.map { "  \($0.date.formatted(date: .omitted, time: .standard))  \($0.text)" }
        }
        lines.append("Backtrace:")
        lines += frames.prefix(16).enumerated().map { "  \($0.offset)  \($0.element.library)  \($0.element.symbol)" }
        return lines.joined(separator: "\n")
    }
}

struct CrashGroup: Identifiable, Hashable, Sendable {
    let reports: [CrashReport]

    var id: String { latest.signature }
    var latest: CrashReport { reports[0] }

    var channels: String {
        Dictionary(grouping: reports, by: \.channel)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue.capitalized) \($0.value.count)" }
            .joined(separator: " · ")
    }
}

enum CrashReports {
    static let directory = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")

    private static let machinery = ["libsystem_", "libc++", "libobjc", "CoreFoundation", "libdispatch", "libswiftCore", "dyld", "HIToolbox"]
    private static let noise = [
        "xception", "abort", "terminate", "pthread_kill", "raise",
        "EventMatching", "_DPS", "runApp", "NSApplication run", "NSApplicationMain",
    ]

    static func load(since: Date = Date().addingTimeInterval(-30 * 86_400), limit: Int = 60) -> [CrashReport] {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: directory.path) else { return [] }
        var logs: [Channel: [LogEntry]] = [:]
        let found = names.compactMap { name -> (URL, Channel)? in
            guard name.hasSuffix(".ips"),
                  let channel = Channel.allCases.first(where: { name.hasPrefix("\($0.displayName)-") }) else { return nil }
            return (directory.appending(path: name), channel)
        }
        let recent = found.filter { url, _ in
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (modified ?? .distantPast) >= since
        }
        let reports = recent.compactMap { url, channel -> CrashReport? in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  var report = parse(text, url: url, channel: channel) else { return nil }
            if logs[channel] == nil { logs[channel] = entries(in: logText(for: channel)) }
            attach(logs[channel] ?? [], to: &report)
            return report
        }
        return Array(reports.sorted { $0.date > $1.date }.prefix(limit))
    }

    static func groups(_ reports: [CrashReport]) -> [CrashGroup] {
        Dictionary(grouping: reports, by: \.signature).values
            .map { CrashGroup(reports: $0.sorted { $0.date > $1.date }) }
            .sorted { $0.latest.date > $1.latest.date }
    }

    static func parse(_ text: String, url: URL, channel: Channel) -> CrashReport? {
        guard let newline = text.firstIndex(of: "\n") else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let header = try? decoder.decode(Header.self, from: Data(text[..<newline].utf8)),
              let body = try? decoder.decode(Body.self, from: Data(text[text.index(after: newline)...].utf8)) else { return nil }

        let images = body.usedImages?.map { $0.name ?? "?" } ?? []
        let frames = (body.lastExceptionBacktrace ?? body.crashedFrames ?? []).prefix(40).map { entry -> CrashReport.Frame in
            let library = entry.imageIndex.flatMap { images.indices.contains($0) ? images[$0] : nil } ?? "?"
            return CrashReport.Frame(
                library: library,
                symbol: entry.symbol ?? "\(library) + \(entry.imageOffset ?? 0)",
                isApp: library == channel.displayName,
                symbolicated: entry.symbol != nil
            )
        }
        let exception = [body.exception?.type, body.exception?.signal].compactMap { $0 }.joined(separator: " · ")
        return CrashReport(
            url: url,
            channel: channel,
            date: header.date ?? url.modificationDate,
            version: header.appVersion ?? "?",
            exception: exception.isEmpty ? "Crash" : exception,
            kind: exception.isEmpty ? "Crash" : exception,
            reason: nil,
            frames: Array(frames),
            likely: likelyFrame(in: Array(frames))
        )
    }

    static func likelyFrame(in frames: [CrashReport.Frame]) -> Int? {
        let isEntryPoint: (CrashReport.Frame) -> Bool = {
            $0.symbol.hasSuffix("main") || $0.symbol.contains("main(") || $0.symbol == "start"
        }
        let candidates = frames.indices.filter { frames[$0].symbolicated && !isEntryPoint(frames[$0]) }
        return candidates.first { frames[$0].isApp }
            ?? candidates.first { index in
                !machinery.contains { frames[index].library.hasPrefix($0) }
                    && !noise.contains { frames[index].symbol.contains($0) }
            }
    }

    static func attach(_ log: [LogEntry], to report: inout CrashReport) {
        let window = report.date.addingTimeInterval(-15)...report.date.addingTimeInterval(2)
        let crashLine = log.lastIndex { $0.text.hasPrefix("CRASH  uncaught ") && window.contains($0.date) }
        if let crashLine {
            let detail = log[crashLine].text.dropFirst("CRASH  uncaught ".count)
            let parts = detail.split(separator: ":", maxSplits: 1)
            report.kind = String(parts[0])
            report.reason = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
        }
        let end = crashLine ?? log.lastIndex { $0.date <= report.date }.map { $0 + 1 } ?? 0
        report.before = log[..<end].filter { !$0.text.hasPrefix("CRASH") }.suffix(4).map {
            LogEntry(date: $0.date, text: $0.text.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
        }
    }

    static func entries(in log: String) -> [LogEntry] {
        let parser = ISO8601DateFormatter()
        return log.split(separator: "\n").compactMap { line in
            guard let gap = line.range(of: "  "), let date = parser.date(from: String(line[..<gap.lowerBound])) else { return nil }
            return LogEntry(date: date, text: String(line[gap.upperBound...]))
        }
    }

    static func logURL(for channel: Channel) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: channel.displayName)
            .appending(path: "activity.log")
    }

    private static func logText(for channel: Channel) -> String {
        let current = logURL(for: channel)
        let previous = current.deletingPathExtension().appendingPathExtension("1.log")
        return [previous, current].compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private struct Header: Decodable {
        let timestamp: String?
        let appVersion: String?

        var date: Date? {
            guard let timestamp else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS Z"
            return formatter.date(from: timestamp)
        }
    }

    private struct Body: Decodable {
        struct Exception: Decodable {
            let type: String?
            let signal: String?
        }

        struct Entry: Decodable {
            let imageIndex: Int?
            let imageOffset: Int?
            let symbol: String?
        }

        struct Thread: Decodable {
            let frames: [Entry]?
            let triggered: Bool?
        }

        struct Image: Decodable {
            let name: String?
        }

        let exception: Exception?
        let lastExceptionBacktrace: [Entry]?
        let threads: [Thread]?
        let faultingThread: Int?
        let usedImages: [Image]?

        var crashedFrames: [Entry]? {
            guard let threads else { return nil }
            if let faultingThread, threads.indices.contains(faultingThread) { return threads[faultingThread].frames }
            return threads.first { $0.triggered == true }?.frames
        }
    }
}

enum LaunchRecord {
    private static var url: URL { Log.shared.logFileURL.deletingLastPathComponent().appending(path: "session") }

    static func begin() -> Date? {
        let formatter = ISO8601DateFormatter()
        let previous = (try? String(contentsOf: url, encoding: .utf8))
            .flatMap { formatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        try? formatter.string(from: Date()).write(to: url, atomically: true, encoding: .utf8)
        return previous
    }

    static func end() {
        try? FileManager.default.removeItem(at: url)
    }
}

private extension URL {
    var modificationDate: Date {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
    }
}
