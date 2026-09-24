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
    var hangs: [Problem] = []
    var crashes: [CrashReport] = []
    var git = "Checking…"
    var gitHub = "Checking…"

    var groups: [CrashGroup] { CrashReports.groups(crashes) }

    static func collect(logURL: URL) -> Diagnostics {
        let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? Int64) ?? 0
        let git = Shell.run(Git.executable, ["--version"], timeout: 5)
        let gitHub = GitHub.executable.map { Shell.run($0, ["--version"], timeout: 5) }
        let log = tail(of: logURL)
        return Diagnostics(
            logBytes: size,
            problems: problems(in: log),
            hangs: problems(in: log, kinds: ["HANG"], limit: 50),
            crashes: CrashReports.load(),
            git: git.succeeded ? git.trimmed.replacingOccurrences(of: "git version ", with: "") : "Not found",
            gitHub: gitHub.flatMap { $0.lines.first?.split(separator: " ").dropFirst(2).first.map(String.init) } ?? "Not installed"
        )
    }

    static func problems(in log: String, kinds: Set<String> = ["ERROR", "CRASH"], limit: Int = 6) -> [Problem] {
        let parser = ISO8601DateFormatter()
        let found = log.split(separator: "\n").compactMap { line -> Problem? in
            let parts = line.components(separatedBy: "  ")
            guard parts.count >= 3, kinds.contains(parts[1]) else { return nil }
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

    var environment: String {
        [
            "\(Channel.current.displayName) \(Updater.currentVersion)",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "git \(git)",
            "gh \(gitHub)",
        ].joined(separator: "\n")
    }

    func report(telemetry: Telemetry.Snapshot, usage: Telemetry.Usage, settings: [String]) -> String {
        var lines = [environment, ""]
        let uptime = Format.duration(Date().timeIntervalSince(Telemetry.shared.launchedAt))
        lines.append("Up \(uptime) · \(Format.bytes(usage.memory)) · \(usage.threads) threads")
        lines += ["", "Settings"] + settings.map { "  \($0)" }
        if let scan = telemetry.lastScan {
            lines += ["", "Last scan \(Telemetry.format(scan.seconds)), \(scan.commands) commands"]
            lines += scan.phases.map { "  \($0.name)  \(Telemetry.format($0.seconds))\($0.background ? " (background)" : "")" }
        }
        lines += ["", "Slowest commands"] + telemetry.slowest.map { "  \($0.label)  \(Telemetry.format($0.seconds))  exit \($0.status)" }
        lines += ["", "Hangs"] + hangs.map { "  \($0.date?.formatted() ?? "")  \($0.message)" }
        lines += ["", "Problems"] + problems.map { "  \($0.kind) \($0.date?.formatted() ?? "")  \($0.message)" }
        lines += ["", "Crashes"] + crashes.prefix(10).map {
            "  \($0.date.formatted())  \($0.channel.rawValue) \($0.version)  \($0.kind)  \($0.headline)"
        }
        return lines.joined(separator: "\n")
    }
}

struct DiagnosticsSettings: View {
    enum Export: Equatable {
        case idle, working
        case saved(URL)
        case failed(String)
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater
    @State private var diagnostics = Diagnostics()
    @State private var telemetry = Telemetry.shared.snapshot()
    @State private var usage = Telemetry.usage()
    @State private var cpu = 0.0
    @State private var export = Export.idle
    @State private var copied = false

    private let logURL = Log.shared.logFileURL

    var body: some View {
        SettingsForm {
            VitalsCharts(
                samples: telemetry.samples,
                usage: usage,
                cpu: cpu,
                uptime: Date().timeIntervalSince(Telemetry.shared.launchedAt)
            )
            .containerValue(\.spansSettingsColumns, true)

            SettingsSection(title: "Last scan", footer: scanSummary) {
                if let scan = telemetry.lastScan {
                    let total = max(scan.phases.map { $0.start + $0.seconds }.max() ?? 0, 0.001)
                    ForEach(scan.phases, id: \.self) { PhaseRow(phase: $0, total: total) }
                } else {
                    Text("No scan yet").foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: "Background") {
                ForEach(jobs) { JobRow(job: $0) }
            }

            SettingsSection(title: "Slowest commands") {
                if telemetry.slowest.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                } else {
                    ForEach(telemetry.slowest.prefix(5), id: \.self) { CommandRow(command: $0) }
                }
            }

            problemsSection
            toolsSection
            environmentSection
        }
        .task { await load() }
        .task { await pulse() }
        .sheet(isPresented: $model.showingCrashes) {
            CrashesSheet(groups: diagnostics.groups, hangs: diagnostics.hangs, environment: diagnostics.environment)
        }
    }

    private var scanSummary: String? {
        guard let scan = telemetry.lastScan else { return nil }
        return "\(Telemetry.format(scan.seconds)) · \(scan.commands) commands · finished \(Format.relative(scan.date))"
    }

    private var problemsSection: some View {
        SettingsSection(title: "Problems") {
            LabeledContent("Crashes") {
                HStack(spacing: Space.m) {
                    Text(crashSummary)
                    Button("View") { model.showingCrashes = true }
                        .disabled(diagnostics.crashes.isEmpty && diagnostics.hangs.isEmpty)
                }
            }
            LabeledContent("Hangs") { Text(hangSummary) }
            LabeledContent("Errors") {
                Text(diagnostics.problems.first { $0.kind == "ERROR" }?.message ?? "None recorded")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var crashSummary: String {
        let crashes = diagnostics.crashes
        guard !crashes.isEmpty else { return "None in 30 days" }
        let today = crashes.filter { Calendar.current.isDateInToday($0.date) }.count
        return "\(today) today · \(crashes.count) in 30 days"
    }

    private var hangSummary: String {
        let today = diagnostics.hangs.filter { $0.date.map(Calendar.current.isDateInToday) ?? false }
        guard !today.isEmpty else { return diagnostics.hangs.isEmpty ? "None recorded" : "None today" }
        return "\(today.count) today"
    }

    private var toolsSection: some View {
        SettingsSection(title: "Tools", footer: "The bundle zips the log, crash reports, settings and environment into Downloads.") {
            LabeledContent("Diagnostics bundle") {
                HStack(spacing: Space.m) {
                    switch export {
                    case .saved: Text("Saved to Downloads")
                    case .failed(let message): Text(message).lineLimit(1)
                    case .idle, .working: EmptyView()
                    }
                    Button(exportTitle) { exportBundle() }
                        .disabled(export == .working)
                }
            }
            LabeledContent("Record every command") {
                HStack(spacing: Space.m) {
                    if let until = telemetry.recordingUntil {
                        Text("until \(until.formatted(date: .omitted, time: .shortened))")
                        Button("Stop") { record(nil) }
                    } else {
                        Button("Record 10 min") { record(600) }
                    }
                }
            }
            LabeledContent("Report an issue") {
                Button("Open GitHub") {
                    let latest = diagnostics.crashes.first { $0.channel == .current && Date().timeIntervalSince($0.date) < 7 * 86_400 }
                    if let url = DiagnosticsExport.issueURL(crash: latest, environment: diagnostics.environment) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            LabeledContent("Activity log") {
                HStack(spacing: Space.m) {
                    Text("\(logURL.lastPathComponent) · \(Format.bytes(diagnostics.logBytes))").monospacedDigit()
                    Button("Open") { NSWorkspace.shared.open(logURL) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }
                }
            }
        }
    }

    private var exportTitle: String {
        switch export {
        case .idle: return "Export"
        case .working: return "Exporting…"
        case .saved: return "Show zip"
        case .failed: return "Try again"
        }
    }

    private var environmentSection: some View {
        SettingsSection(title: "Environment") {
            LabeledContent("Coppice", value: "\(Channel.current.displayName) \(Updater.currentVersion)")
            LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
            LabeledContent("git", value: diagnostics.git)
            LabeledContent("GitHub CLI", value: diagnostics.gitHub)
            LabeledContent("Full Disk Access", value: model.unreadableRoots.isEmpty ? "Not needed" : "Missing")
            LabeledContent("Report") {
                Button(copied ? "Copied" : "Copy diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullReport, forType: .string)
                    copied = true
                }
            }
        }
    }

    private var fullReport: String {
        diagnostics.report(telemetry: telemetry, usage: usage, settings: settingsSummary)
    }

    private var settingsSummary: [String] {
        [
            "Code folders: \(settings.codeRoots.map { ($0.path as NSString).abbreviatingWithTildeInPath }.joined(separator: ", "))",
            "Agents: \(settings.enabledHarnesses.map(\.displayName).sorted().joined(separator: ", "))",
            "Pull request checks: \(settings.checkPullRequests ? "on" : "off")",
            "Automatic updates: \(settings.autoUpdateCheck ? "on" : "off")",
            "Save .env files: \(settings.rescueIgnoredConfig ? "on" : "off")",
        ]
    }

    private func load() async {
        let url = logURL
        diagnostics = await Task.detached(priority: .utility) { Diagnostics.collect(logURL: url) }.value
    }

    private func pulse() async {
        while !Task.isCancelled {
            if Self.windowIsOnScreen {
                let next = Telemetry.usage()
                telemetry = Telemetry.shared.snapshot()
                cpu = next.date.timeIntervalSince(usage.date) >= 2
                    ? next.cpuPercent(since: usage)
                    : telemetry.samples.last?.cpu ?? 0
                usage = next
            }
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private static var windowIsOnScreen: Bool {
        NSApp.windows.contains {
            $0.frameAutosaveName == WindowID.main && $0.isVisible && $0.occlusionState.contains(.visible)
        }
    }

    private func record(_ duration: TimeInterval?) {
        Telemetry.shared.record(for: duration)
        telemetry = Telemetry.shared.snapshot()
    }

    private func exportBundle() {
        if case .saved(let url) = export {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        export = .working
        let report = fullReport
        let crashes = diagnostics.crashes
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DiagnosticsExport.bundle(report: report, crashes: crashes) }
            }.value
            switch result {
            case .success(let url):
                export = .saved(url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                export = .failed(error.localizedDescription)
            }
        }
    }
}

extension DiagnosticsSettings {
    var jobs: [Job] {
        [watcherJob, scanJob, sizingJob, pullRequestJob, updatesJob]
    }

    private var watcherJob: Job {
        let watcher = telemetry.watcher
        guard watcher.folders > 0 else { return Job(name: "Folder watcher", state: .off, detail: "nothing to watch") }
        let last = watcher.lastChange.map { "last \(Format.relative($0))" } ?? "no changes yet"
        let changes = "\(watcher.changes) change\(watcher.changes == 1 ? "" : "s")"
        return Job(name: "Folder watcher", state: .running, detail: "\(watcher.folders) folders · \(changes) · \(last)")
    }

    private var scanJob: Job {
        if model.isScanning { return Job(name: "Scans", state: .running, detail: "scanning now") }
        if let next = model.nextAutomaticScan, next > Date() {
            return Job(name: "Scans", state: .waiting, detail: "next automatic scan allowed \(Format.relative(next))")
        }
        let last = model.lastScan.map { " · last \(Format.relative($0))" } ?? ""
        return Job(name: "Scans", state: .idle, detail: "waits for a change\(last)")
    }

    private var sizingJob: Job {
        let reports = model.visibleReports
        let measured = reports.filter(\.measured).count
        return Job(name: "Sizing", state: model.isMeasuring ? .running : .idle, detail: "\(measured) of \(reports.count) measured")
    }

    private var pullRequestJob: Job {
        let name = "Pull requests"
        guard model.canCheckPullRequests else { return Job(name: name, state: .off, detail: "needs the GitHub CLI") }
        guard settings.checkPullRequests else { return Job(name: name, state: .off, detail: "turned off") }
        if model.isCheckingPullRequests { return Job(name: name, state: .running, detail: "checking") }
        guard let next = model.nextPullRequestCheck else { return Job(name: name, state: .idle, detail: "after the next scan") }
        let detail = next > Date() ? "refresh due \(Format.relative(next))" : "refreshes on the next scan"
        return Job(name: name, state: .waiting, detail: detail)
    }

    private var updatesJob: Job {
        let name = "Updates"
        guard Channel.current.updatesEnabled else {
            return Job(name: name, state: .off, detail: "not on the \(Channel.current.rawValue) channel")
        }
        guard settings.autoUpdateCheck else { return Job(name: name, state: .off, detail: "automatic checks off") }
        if updater.isBusy { return Job(name: name, state: .running, detail: updater.statusText) }
        return Job(name: name, state: .waiting, detail: updater.nextCheck.map { "next check \(Format.relative($0))" } ?? updater.statusText)
    }
}
