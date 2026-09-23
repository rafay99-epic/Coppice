import Foundation
import os

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
        queue.async { [self] in
            rotateIfNeeded()
            let stamp = ISO8601DateFormatter().string(from: Date())
            let line = "\(stamp)  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: fileURL.path)[.size] as? Int64,
              size > maxBytes else { return }
        let previous = fileURL.deletingPathExtension().appendingPathExtension("1.log")
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: fileURL, to: previous)
    }

    func recentLines(limit: Int = 200) -> [String] {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return Array(contents.split(separator: "\n").map(String.init).suffix(limit))
    }
}
