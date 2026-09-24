import SwiftUI
import AppKit

struct Diagnostics: Sendable {
    struct Problem: Sendable, Hashable {
        let date: Date?
        let kind: String
        let message: String

        var caption: String {
            let when = date?.formatted(date: .abbreviated, time: .shortened) ?? "unknown time"
            return "\(kind == "CRASH" ? "Crash" : "Error") · \(when)"
        }
    }

    var logBytes: Int64 = 0
    var problems: [Problem] = []
    var git = "Checking…"
    var gitHub = "Checking…"

    static func collect(logURL: URL) -> Diagnostics {
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int64) ?? 0
        let git = Shell.run(Git.executable, ["--version"], timeout: 5)
        let gitHub = GitHub.executable.map { Shell.run($0, ["--version"], timeout: 5) }
        return Diagnostics(
            logBytes: size,
            problems: problems(in: tail(of: logURL)),
            git: git.succeeded ? git.trimmed.replacingOccurrences(of: "git version ", with: "") : "Not found",
            gitHub: gitHub.flatMap { $0.lines.first?.split(separator: " ").dropFirst(2).first.map(String.init) } ?? "Not installed"
        )
    }

    static func problems(in log: String, limit: Int = 6) -> [Problem] {
        let parser = ISO8601DateFormatter()
        let found = log.split(separator: "\n").compactMap { line -> Problem? in
            let parts = line.components(separatedBy: "  ")
            guard parts.count >= 3, ["ERROR", "CRASH"].contains(parts[1]) else { return nil }
            return Problem(date: parser.date(from: parts[0]), kind: parts[1], message: parts[2...].joined(separator: "  "))
        }
        return Array(found.suffix(limit).reversed())
    }

    private static func tail(of url: URL, bytes: UInt64 = 256 * 1024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > bytes ? end - bytes : 0)
        return String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
    }

    var report: String {
        var lines = [
            "\(Channel.current.displayName) \(Updater.currentVersion)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "git \(git)",
            "gh \(gitHub)",
        ]
        lines += problems.map { "\($0.kind) \($0.date?.formatted() ?? "") \($0.message)" }
        return lines.joined(separator: "\n")
    }
}

struct DiagnosticsSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var diagnostics = Diagnostics()
    @State private var copied = false

    private let logURL = Log.shared.logFileURL

    var body: some View {
        SettingsForm {
            SettingsSection(title: "Activity log", footer: "Every scan, sweep and removal is written here, along with any crash.") {
                LabeledContent("File") {
                    HStack(spacing: Space.m) {
                        Text("\(logURL.lastPathComponent) · \(Format.bytes(diagnostics.logBytes))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button("Open") { NSWorkspace.shared.open(logURL) }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                    }
                }
            }

            SettingsSection(title: "Recent problems") {
                if diagnostics.problems.isEmpty {
                    Text("None recorded")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(diagnostics.problems, id: \.self) { problem in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(problem.message)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Text(problem.caption)
                                .font(.uiCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            SettingsSection(title: "Environment") {
                LabeledContent("Coppice", value: "\(Channel.current.displayName) \(Updater.currentVersion)")
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("git", value: diagnostics.git)
                LabeledContent("GitHub CLI", value: diagnostics.gitHub)
                LabeledContent("Full Disk Access", value: model.unreadableRoots.isEmpty ? "Not needed" : "Missing")
                LabeledContent("Report") {
                    Button(copied ? "Copied" : "Copy diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(diagnostics.report, forType: .string)
                        copied = true
                    }
                }
            }
        }
        .task {
            let url = logURL
            diagnostics = await Task.detached { Diagnostics.collect(logURL: url) }.value
        }
    }
}
