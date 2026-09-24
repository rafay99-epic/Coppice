import Foundation
import SwiftUI

enum Activity: Equatable {
    case idle
    case scanning
    case sweeping(Sweeper.Progress)
    case pruning(repositories: Int)
    case removing(path: String)

    var isBusy: Bool { self != .idle }

    var isMutating: Bool {
        switch self {
        case .idle, .scanning: return false
        case .sweeping, .pruning, .removing: return true
        }
    }

    var title: String {
        switch self {
        case .idle: return ""
        case .scanning: return "Scanning worktrees"
        case .sweeping(let progress): return "Sweeping \(min(progress.completed + 1, progress.total)) of \(progress.total)"
        case .pruning(let count): return "Pruning \(count) repositor\(count == 1 ? "y" : "ies")"
        case .removing(let path): return "Moving \((path as NSString).lastPathComponent) to the Trash"
        }
    }

    var detail: String? {
        guard case .sweeping(let progress) = self, let current = progress.current else { return nil }
        return (current as NSString).lastPathComponent
    }

    var fraction: Double? {
        if case .sweeping(let progress) = self, progress.total > 0 { return progress.fraction }
        return nil
    }

    var freedSoFar: Int64? {
        if case .sweeping(let progress) = self, progress.freedBytes > 0 { return progress.freedBytes }
        return nil
    }
}

struct RowStatus: Equatable {
    var tag: String?
    var dimmed = false
    var progress: Double?
    var freed: Int64 = 0
    var freedInFlight: Int64 = 0
}

struct Receipt: Equatable {
    enum Follow: Equatable {
        case log
        case trash(URL)
    }

    let headline: String
    var detail: String?
    var follow: Follow?
    var freed: [String: Int64] = [:]
}

struct Banner: Identifiable, Equatable {
    enum Kind: Equatable {
        case warning
        case failure

        var symbol: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .failure: return "xmark.octagon.fill"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
    var details: [Sweeper.Item] = []
}

struct RepoGroup {
    let path: String
    let reports: [WorktreeReport]

    var repo: String { (path as NSString).lastPathComponent }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var reports: [WorktreeReport] = []
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var lastScan: Date?
    @Published private(set) var detectedHarnesses: [Harness] = []
    @Published var banner: Banner?
    @Published private(set) var receipt: Receipt?
    @Published var selection: String?
    @Published var confirmingSweep = false
    @Published var settingsPane: SettingsPane?
    @Published private(set) var unreadableRoots: [String] = []
    @Published private(set) var scanFailures: [Sweeper.Item] = []

    var isScanning: Bool { activity == .scanning }
    var isWorking: Bool { activity.isMutating }
    @Published private(set) var isMeasuring = false
    @Published private(set) var isCheckingPullRequests = false
    let canCheckPullRequests = GitHub.isInstalled

    private let settings: AppSettings
    private var watcher: DirectoryWatcher?
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?
    private var measureTask: Task<Void, Never>?
    private var scheduler = ScanScheduler()
    private var pullRequestTask: Task<Void, Never>?
    private var receiptTask: Task<Void, Never>?
    private var lastPullRequestFetch: Date?
    private var pullRequestRepos: Set<String> = []
    private static let pullRequestRefreshInterval: TimeInterval = 600

    init(settings: AppSettings) {
        self.settings = settings
        self.detectedHarnesses = Harness.detected(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    var visibleReports: [WorktreeReport] {
        reports.filter { settings.enabledHarnesses.contains($0.worktree.harness) }
    }

    var reclaimableBytes: Int64 {
        visibleReports.filter { $0.verdict.canSweep }.reduce(0) { $0 + $1.artifactBytes }
    }

    var totalBytes: Int64 { visibleReports.reduce(0) { $0 + $1.totalBytes } }
    var sweepCandidates: [WorktreeReport] { visibleReports.filter { $0.verdict.canSweep && $0.artifactBytes > 0 } }
    var prunableReports: [WorktreeReport] { visibleReports.filter { $0.verdict == .prunable } }
    var hasWorkCount: Int { visibleReports.filter { $0.verdict.status == .hasWork }.count }

    var presentHarnesses: [Harness] {
        let found = Set(visibleReports.map(\.worktree.harness))
        return Harness.allCases.filter(found.contains)
    }
    var selectedReport: WorktreeReport? { visibleReports.first { $0.id == selection } }

    func rowStatus(_ report: WorktreeReport) -> RowStatus {
        switch activity {
        case .sweeping(let progress):
            guard let index = progress.paths.firstIndex(of: report.id) else { return RowStatus() }
            let freed = progress.freed[report.id] ?? 0
            if index > progress.completed { return RowStatus(tag: "queued") }
            if index < progress.completed { return RowStatus(freed: freed, freedInFlight: freed) }
            let fraction = report.artifactBytes > 0 ? min(Double(freed) / Double(report.artifactBytes), 1) : 0
            return RowStatus(tag: "sweeping", dimmed: true, progress: fraction, freedInFlight: freed)
        case .removing(let path) where path == report.id:
            return RowStatus(tag: "moving to Trash", dimmed: true)
        default:
            return RowStatus(freed: receipt?.freed[report.id] ?? 0)
        }
    }

    var groups: [RepoGroup] {
        let grouped = Dictionary(grouping: visibleReports) { $0.worktree.repoPath }
        return grouped.map { path, items in
            let sorted = items.sorted {
                $0.verdict.order == $1.verdict.order
                    ? $0.totalBytes > $1.totalBytes
                    : $0.verdict.order < $1.verdict.order
            }
            return RepoGroup(path: path, reports: sorted)
        }
        .sorted { lhs, rhs in
            let left = lhs.reports.reduce(0) { $0 + $1.totalBytes }
            let right = rhs.reports.reduce(0) { $0 + $1.totalBytes }
            return left == right ? lhs.path < rhs.path : left > right
        }
    }

    private var scanner: WorktreeScanner {
        WorktreeScanner(
            codeRoots: settings.codeRoots,
            recentSessionWindow: settings.recentSessionHours * 3600
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        rescan()
        restartWatcher()
    }

    private func restartWatcher() {
        watcher?.stop()
        let scanner = self.scanner
        var paths = scanner.agentWorktreeRoots().map(\.root.path)
        paths += settings.codeRoots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        let agentRoots = scanner.agentWorktreeRoots().map(\.root.path)
        let isRelevant: @Sendable (String) -> Bool = { ScanScheduler.isWorktreeChange($0, agentRoots: agentRoots) }
        watcher = DirectoryWatcher(paths: paths, isRelevant: isRelevant) { [weak self] in
            Task { @MainActor in self?.requestScan(automatic: true) }
        }
        watcher?.start()
    }

    func rescan() {
        requestScan(automatic: false)
    }

    private func requestScan(automatic: Bool) {
        guard !activity.isMutating else { return }
        switch scheduler.request(automatic: automatic, now: Date()) {
        case .wait:
            return
        case .deferred(let delay):
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                self.scheduler.deferredFired()
                self.requestScan(automatic: true)
            }
        case .scanNow:
            performScan()
        }
    }

    private func performScan() {
        scanTask?.cancel()
        measureTask?.cancel()
        activity = .scanning

        let scanner = self.scanner
        let merged = Set(reports.filter(\.mergedAtHead).map(\.id))
        scanTask = Task { [weak self] in
            let (fresh, unreadable, failures) = await Task.detached(priority: .utility) {
                () -> ([WorktreeReport], [String], [Sweeper.Item]) in
                guard FileManager.default.isExecutableFile(atPath: Git.executable) else {
                    Log.shared.error("git not found at \(Git.executable)")
                    return ([], [], [Sweeper.Item(path: Git.executable, reason: "Install the Xcode Command Line Tools")])
                }
                let files = FileManager.default
                let unreadable = (scanner.codeRoots.map(\.path) + scanner.agentWorktreeRoots().map(\.root.path))
                    .filter { files.fileExists(atPath: $0) && (try? files.contentsOfDirectory(atPath: $0)) == nil }
                let holders = ProcessProbe.currentHolders()
                let inventory = scanner.scan()
                let reports = inventory.worktrees.map { worktree in
                    WorktreeReport(
                        worktree: worktree,
                        verdict: scanner.verdict(
                            for: worktree,
                            holders: holders,
                            prMerged: merged.contains(worktree.path)
                        )
                    )
                }
                return (reports, unreadable, inventory.failures)
            }.value

            guard !Task.isCancelled, let self else { return }
            self.unreadableRoots = unreadable
            self.scanFailures = failures
            let previous = Dictionary(uniqueKeysWithValues: self.reports.map { ($0.id, $0) })
            self.reports = fresh.map { report in
                guard let old = previous[report.id] else { return report }
                var merged = report
                merged.pullRequest = old.pullRequest
                guard old.measured else { return merged }
                merged.artifactBytes = old.artifactBytes
                merged.uniqueBytes = old.uniqueBytes
                merged.artifacts = old.artifacts
                merged.measured = true
                return merged
            }
            self.lastScan = Date()
            self.activity = .idle
            if self.scheduler.finished(now: Date()) {
                self.requestScan(automatic: false)
                return
            }
            Log.shared.write(
                "scan: \(self.visibleReports.count) worktrees, "
                + "\(self.hasWorkCount) with work, \(self.groups.count) repos"
            )
            self.measureSizes()
            let repos = Set(self.reports.map(\.worktree.repoPath))
            let isStale = self.lastPullRequestFetch.map {
                Date().timeIntervalSince($0) > Self.pullRequestRefreshInterval
            } ?? true
            if isStale || !repos.isSubset(of: self.pullRequestRepos) { self.fetchPullRequests() }
        }
    }

    func fetchPullRequests() {
        guard canCheckPullRequests, settings.checkPullRequests else { return }
        pullRequestTask?.cancel()

        let repoSet = Set(reports.filter { !$0.worktree.isOrphan }.map(\.worktree.repoPath))
        guard !repoSet.isEmpty else { return }
        let repos = Array(repoSet)
        isCheckingPullRequests = true
        lastPullRequestFetch = Date()
        pullRequestRepos = repoSet

        pullRequestTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.isCheckingPullRequests = false } }
            for repo in repos {
                if Task.isCancelled { return }
                let byBranch = await Task.detached(priority: .utility) {
                    GitHub.pullRequests(repo: repo)
                }.value
                guard !Task.isCancelled, let self, !byBranch.isEmpty else { continue }
                for index in self.reports.indices
                where self.reports[index].worktree.repoPath == repo {
                    guard let branch = self.reports[index].worktree.branch else { continue }
                    self.reports[index].pullRequest = byBranch[branch]
                }
            }
            guard !Task.isCancelled else { return }
            await self?.recheckMergedBranches()
        }
    }

    private func recheckMergedBranches() async {
        let targets = reports
            .filter { $0.mergedAtHead && Self.dependsOnMerge($0.verdict) }
            .map(\.worktree)
        guard !targets.isEmpty else { return }

        let scanner = self.scanner
        let fresh = await Task.detached(priority: .utility) {
            let holders = ProcessProbe.currentHolders()
            return targets.map { ($0.path, scanner.verdict(for: $0, holders: holders, prMerged: true)) }
        }.value
        for (path, verdict) in fresh {
            guard let index = reports.firstIndex(where: { $0.id == path }) else { continue }
            reports[index].verdict = verdict
        }
    }

    private static func dependsOnMerge(_ verdict: Verdict) -> Bool {
        switch verdict {
        case .blocked(.aheadOfDefault): return true
        case .caution(let list): return list.contains(.branchNotMerged)
        default: return false
        }
    }

    func allBlockers(for report: WorktreeReport) async -> [Blocker] {
        let scanner = self.scanner
        let prMerged = report.mergedAtHead
        return await Task.detached(priority: .userInitiated) {
            scanner.blockers(for: report.worktree, holders: ProcessProbe.currentHolders(), prMerged: prMerged)
        }.value
    }

    private func measureSizes() {
        measureTask?.cancel()
        let targets = reports.filter { !$0.measured }.map(\.worktree.path)
        guard !targets.isEmpty else { isMeasuring = false; return }

        isMeasuring = true
        measureTask = Task { [weak self] in
            defer { if !Task.isCancelled { self?.isMeasuring = false } }
            for path in targets {
                if Task.isCancelled { return }
                let measurement = await Task.detached(priority: .background) {
                    ArtifactScanner.measure(worktree: path)
                }.value
                guard !Task.isCancelled, let self else { return }
                guard let index = self.reports.firstIndex(where: { $0.worktree.path == path }) else { continue }
                self.reports[index].artifacts = measurement.artifacts
                self.reports[index].artifactBytes = measurement.artifactBytes
                self.reports[index].uniqueBytes = measurement.uniqueBytes
                self.reports[index].measured = true
            }
        }
    }

    private func interruptScan() -> Bool {
        guard !activity.isMutating else { return false }
        if activity == .scanning {
            scanTask?.cancel()
            scheduler.interrupted()
            activity = .idle
        }
        return true
    }

    func sweep(_ targets: [WorktreeReport]) async {
        guard !targets.isEmpty, interruptScan() else { return }
        banner = nil
        show(nil)
        activity = .sweeping(Sweeper.Progress(paths: targets.map(\.id)))

        let scanner = self.scanner
        let outcome = await Task.detached(priority: .userInitiated) { [weak self] in
            Sweeper.sweep(
                reports: targets,
                scanner: scanner,
                log: { Log.shared.write($0) },
                onProgress: { progress in
                    Task { @MainActor in
                        guard let self, case .sweeping = self.activity else { return }
                        self.activity = .sweeping(progress)
                    }
                }
            )
        }.value

        apply(outcome)
        banner = Banner.sweep(outcome)
        show(Receipt.sweep(outcome))
        activity = .idle
        rescan()
    }

    func prune(only repository: String? = nil) async {
        let repos = Array(Set(prunableReports.map(\.worktree.repoPath)))
            .filter { repository == nil || $0 == repository }
        guard !repos.isEmpty, interruptScan() else { return }
        banner = nil
        show(nil)
        activity = .pruning(repositories: repos.count)

        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.prune(repositories: repos) { Log.shared.write($0) }
        }.value

        if outcome.failures.isEmpty {
            let count = outcome.removedPaths.count
            show(Receipt(headline: "Pruned \(count) repositor\(count == 1 ? "y" : "ies")", detail: "· nothing on disk was touched"))
        } else {
            banner = Banner(
                kind: .failure,
                title: "Prune failed",
                message: "\(outcome.failures.count) repositor\(outcome.failures.count == 1 ? "y" : "ies") could not be pruned.",
                details: outcome.failures
            )
        }
        activity = .idle
        rescan()
    }

    func remove(_ report: WorktreeReport, deleteBranch: Bool) async {
        guard interruptScan() else { return }
        banner = nil
        show(nil)
        activity = .removing(path: report.id)

        let scanner = self.scanner
        let rescue = settings.rescueIgnoredConfig ? settings.rescueDirectory : nil
        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.remove(
                report: report,
                scanner: scanner,
                deleteBranch: deleteBranch,
                rescueDirectory: rescue
            ) { Log.shared.write($0) }
        }.value

        if outcome.removedPaths.isEmpty {
            let reason = outcome.skipped.first?.reason ?? outcome.failures.first?.reason ?? "the verdict changed"
            banner = Banner(
                kind: outcome.failures.isEmpty ? .warning : .failure,
                title: "Kept \(report.worktree.name)",
                message: "Not removed: \(reason).",
                details: outcome.failures
            )
        } else {
            reports.removeAll { $0.id == report.id }
            show(Receipt(headline: "Freed \(Format.bytes(outcome.freedBytes))", follow: outcome.trashed.map(Receipt.Follow.trash)))
            if outcome.hasProblems {
                let count = outcome.failures.count + outcome.skipped.count
                banner = Banner(
                    kind: .warning,
                    title: "Moved \(report.worktree.name) to the Trash",
                    message: "\(count) follow-up step\(count == 1 ? "" : "s") did not finish.",
                    details: outcome.failures + outcome.skipped
                )
            }
        }
        selection = nil
        activity = .idle
        rescan()
    }

    private func apply(_ outcome: Sweeper.Outcome) {
        let removed = Set(outcome.removedPaths)
        for index in reports.indices {
            guard let freed = outcome.freed[reports[index].id] else { continue }
            reports[index].artifactBytes = max(0, reports[index].artifactBytes - freed)
            reports[index].artifacts.removeAll { removed.contains($0.path) }
        }
    }

    private func show(_ next: Receipt?) {
        receiptTask?.cancel()
        receipt = next
        guard next != nil else { return }
        receiptTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.receipt = nil
        }
    }

    func openSettings(_ pane: SettingsPane = .general) {
        settingsPane = pane
        NotificationCenter.default.post(name: AppDelegate.showWindow, object: nil)
    }

    func settingsChanged() {
        restartWatcher()
        detectedHarnesses = Harness.detected(home: FileManager.default.homeDirectoryForCurrentUser)
        rescan()
    }
}

extension Receipt {
    static func sweep(_ outcome: Sweeper.Outcome) -> Receipt? {
        if outcome.didAnything {
            let count = outcome.freed.count
            return Receipt(
                headline: "Freed \(Format.bytes(outcome.freedBytes))",
                detail: "from \(count) worktree\(count == 1 ? "" : "s")",
                follow: .log,
                freed: outcome.freed
            )
        }
        return outcome.hasProblems ? nil : Receipt(headline: "Nothing to sweep", detail: "no build output was found")
    }
}

extension Banner {
    static func sweep(_ outcome: Sweeper.Outcome) -> Banner? {
        if !outcome.failures.isEmpty && !outcome.didAnything {
            return Banner(
                kind: .failure,
                title: "Could not sweep build artifacts",
                message: "\(outcome.failures.count) item\(outcome.failures.count == 1 ? "" : "s") could not be deleted.",
                details: outcome.failures
            )
        }
        guard outcome.hasProblems else { return nil }
        var parts: [String] = []
        if !outcome.skipped.isEmpty { parts.append("\(outcome.skipped.count) skipped") }
        if !outcome.failures.isEmpty { parts.append("\(outcome.failures.count) failed") }
        return Banner(
            kind: .warning,
            title: "Not everything was swept",
            message: parts.joined(separator: ", ") + (outcome.didAnything ? ". Everything else was removed." : "."),
            details: outcome.failures + outcome.skipped
        )
    }
}
