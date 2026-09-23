import Darwin
import Foundation
import os

private var crashDescriptor: Int32 = -1
private let crashLines = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 32)

private func recordCrash(_ signal: Int32) {
    if crashDescriptor >= 0, signal > 0, signal < 32, let line = crashLines[Int(signal)] {
        _ = Darwin.write(crashDescriptor, line, strlen(line))
    }
    Darwin.signal(signal, SIG_DFL)
    raise(signal)
}

final class Log: @unchecked Sendable {
    static let shared = Log()

    private let logger = Logger(subsystem: "com.syntaxlabtechnology.coppice", category: "activity")
    private let queue = DispatchQueue(label: "com.syntaxlabtechnology.coppice.log", qos: .utility)
    private let fileURL: URL
    private let maxBytes: Int64 = 2 * 1024 * 1024

    private init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Channel.current.displayName)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appending(path: "activity.log")
    }

    var logFileURL: URL { fileURL }

    func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        append(message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("ERROR  \(message)")
    }

    func critical(_ message: String) {
        logger.fault("\(message, privacy: .public)")
        queue.sync { appendNow("CRASH  \(message)") }
    }

    func installCrashHandlers() {
        queue.sync { reopenCrashDescriptor() }
        let signals: [(Int32, String)] = [
            (SIGSEGV, "SIGSEGV"), (SIGBUS, "SIGBUS"), (SIGILL, "SIGILL"),
            (SIGABRT, "SIGABRT"), (SIGFPE, "SIGFPE"), (SIGTRAP, "SIGTRAP"),
        ]
        let version = Updater.currentVersion
        for (number, name) in signals {
            let line = "CRASH  Coppice \(version) stopped on \(name). The full report is in Console, under Crash Reports.\n"
            crashLines[Int(number)] = strdup(line)
            signal(number, recordCrash)
        }
    }

    private func append(_ message: String) {
        queue.async { [self] in appendNow(message) }
    }

    private func appendNow(_ message: String) {
        rotateIfNeeded()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("\(stamp)  \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    private func reopenCrashDescriptor() {
        if crashDescriptor >= 0 { close(crashDescriptor) }
        crashDescriptor = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
    }

    private func rotateIfNeeded() {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int64,
              size > maxBytes else { return }
        let previous = fileURL.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
        if crashDescriptor >= 0 { reopenCrashDescriptor() }
    }
}
