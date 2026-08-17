import Foundation
import SwiftUI

/// The single source of truth for the UI.
///
/// Scanning happens in two stages so the window is useful immediately: the
/// inventory and verdicts come from git and land in well under a second, then
/// sizes stream in from a background walk. Nothing blocks on measuring 36 GB.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var reports: [WorktreeReport] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isWorking = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var detectedHarnesses: [Harness] = []
    @Published private(set) var statusMessage: String?
    @Published var selection: String?

    private let settings: AppSettings
    private var watcher: DirectoryWatcher?
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?
    private var measureTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
        self.detectedHarnesses = Harness.detected(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    // MARK: - Derived state

    /// Reports for the harnesses the user chose to see.
    ///
    /// Every derived figure is computed from this rather than from `reports`, so
    /// the headline count can never disagree with the list underneath it. When
    /// the filter and the totals read from different collections, the UI claims
    /// "53 worktrees" above a list showing five, which reads as a broken scan.
    var visibleReports: [WorktreeReport] {
        reports.filter { settings.enabledHarnesses.contains($0.worktree.harness) }
    }

    /// Bytes a sweep would free right now. This is the number the menu bar shows.
    var reclaimableBytes: Int64 {
        visibleReports.filter { $0.verdict.canSweep }.reduce(0) { $0 + $1.artifactBytes }
    }

    var totalBytes: Int64 { visibleReports.reduce(0) { $0 + $1.totalBytes } }
    var sweepCandidates: [WorktreeReport] { visibleReports.filter { $0.verdict.canSweep && $0.artifactBytes > 0 } }
    var prunableReports: [WorktreeReport] { visibleReports.filter { $0.verdict == .prunable } }
    var protectedCount: Int { visibleReports.filter { !$0.verdict.canRemove }.count }
    var selectedReport: WorktreeReport? { reports.first { $0.id == selection } }

    /// Worktrees grouped by repository, ordered by how much they hold.
    var groups: [(repo: String, harness: Harness, reports: [WorktreeReport])] {
        let grouped = Dictionary(grouping: visibleReports) { $0.worktree.repoName }
        return grouped.map { name, items in
            let sorted = items.sorted {
                $0.verdict.order == $1.verdict.order
                    ? $0.totalBytes > $1.totalBytes
                    : $0.verdict.order < $1.verdict.order
            }
            return (name, sorted.first?.worktree.harness ?? .manual, sorted)
        }
        .sorted { lhs, rhs in
            let left = lhs.reports.reduce(0) { $0 + $1.totalBytes }
            let right = rhs.reports.reduce(0) { $0 + $1.totalBytes }
            return left == right ? lhs.repo < rhs.repo : left > right
        }
    }

    private var scanner: WorktreeScanner {
        WorktreeScanner(
            codeRoots: settings.codeRoots,
            recentSessionWindow: settings.recentSessionHours * 3600
        )
    }

    // MARK: - Lifecycle

    /// Starts watching the worktree roots and runs one scan.
    ///
    /// After this the app is event-driven: it sits at zero CPU until FSEvents
    /// says a watched directory changed. There is no timer anywhere.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        rescan()
        restartWatcher()
    }

    func stop() {
        watcher?.stop()
        watcher = nil
        scanTask?.cancel()
        measureTask?.cancel()
    }

    private func restartWatcher() {
        watcher?.stop()
        let scanner = self.scanner
        var paths = scanner.agentWorktreeRoots().map(\.root.path)
        paths += settings.codeRoots.map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return }

        watcher = DirectoryWatcher(paths: paths) { [weak self] in
            Task { @MainActor in self?.rescan() }
        }
        watcher?.start()
    }

    // MARK: - Scanning

    func rescan() {
        guard !isScanning else { return }
        scanTask?.cancel()
        measureTask?.cancel()
        isScanning = true

        let scanner = self.scanner
        scanTask = Task { [weak self] in
            // Stage one: inventory and verdicts. Fast, so the list appears now.
            let fresh = await Task.detached(priority: .utility) { () -> [WorktreeReport] in
                let holders = ProcessProbe.currentHolders()
                return scanner.inventory().map { worktree in
                    WorktreeReport(worktree: worktree, verdict: scanner.verdict(for: worktree, holders: holders))
                }
            }.value

            guard !Task.isCancelled, let self else { return }
            // Carry over sizes already measured so rows do not flash back to a dash.
            let previous = Dictionary(uniqueKeysWithValues: self.reports.map { ($0.id, $0) })
            self.reports = fresh.map { report in
                guard let old = previous[report.id], old.measured else { return report }
                var merged = report
                merged.artifactBytes = old.artifactBytes
                merged.uniqueBytes = old.uniqueBytes
                merged.artifacts = old.artifacts
                merged.measured = true
                return merged
            }
            self.lastScan = Date()
            self.isScanning = false
            Log.shared.write(
                "scan: \(self.visibleReports.count) worktrees, "
                + "\(self.protectedCount) protected, \(self.groups.count) repos"
            )
            self.measureSizes()
        }
    }

    /// Stage two: walk each worktree for its size, one at a time at low priority,
    /// publishing as each finishes. Sequential on purpose. Ten concurrent walks
    /// over node_modules trees would saturate the disk queue and make the
    /// foreground feel slow, which is a bad trade for a background utility.
    private func measureSizes() {
        measureTask?.cancel()
        let targets = reports.filter { !$0.measured }.map(\.worktree.path)
        guard !targets.isEmpty else { return }

        measureTask = Task { [weak self] in
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

    // MARK: - Actions

    func sweep(_ targets: [WorktreeReport]) async {
        guard !targets.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let scanner = self.scanner
        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.sweep(reports: targets, scanner: scanner) { Log.shared.write($0) }
        }.value

        statusMessage = summary(for: outcome, verb: "Swept")
        markUnmeasured(targets.map(\.worktree.path))
        rescan()
    }

    func prune() async {
        let repos = prunableReports.map(\.worktree.repoPath)
        guard !repos.isEmpty, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.prune(repositories: repos) { Log.shared.write($0) }
        }.value

        statusMessage = outcome.failures.isEmpty
            ? "Pruned \(outcome.removedPaths.count) repositor\(outcome.removedPaths.count == 1 ? "y" : "ies")."
            : "Pruned with \(outcome.failures.count) error(s)."
        rescan()
    }

    func remove(_ report: WorktreeReport, deleteBranch: Bool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

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

        if let skipped = outcome.skipped.first, outcome.removedPaths.isEmpty {
            statusMessage = "Kept \(report.worktree.name): \(skipped.reason)"
        } else {
            statusMessage = summary(for: outcome, verb: "Removed")
        }
        selection = nil
        rescan()
    }

    private func markUnmeasured(_ paths: [String]) {
        for path in paths {
            guard let index = reports.firstIndex(where: { $0.worktree.path == path }) else { continue }
            reports[index].measured = false
        }
    }

    private func summary(for outcome: Sweeper.Outcome, verb: String) -> String {
        var parts = ["\(verb) \(Format.bytes(outcome.freedBytes))"]
        if !outcome.skipped.isEmpty { parts.append("\(outcome.skipped.count) skipped") }
        if !outcome.failures.isEmpty { parts.append("\(outcome.failures.count) failed") }
        return parts.joined(separator: ", ") + "."
    }

    /// Called when roots or harness selection change, so the watcher follows.
    func settingsChanged() {
        restartWatcher()
        detectedHarnesses = Harness.detected(home: FileManager.default.homeDirectoryForCurrentUser)
        rescan()
    }
}
