import Foundation
import SwiftUI

/// The single source of truth for the UI.
///
/// Scanning happens in two stages so the window is useful immediately: the
/// inventory and verdicts come from git and land in well under a second, then
/// sizes stream in from a background walk. Nothing blocks on measuring 36 GB.
/// What the app is doing right now.
///
/// A single enum rather than a scatter of booleans, so the UI cannot render an
/// impossible combination like "sweeping" and "pruning" at once, and every
/// long operation is forced to say what it is working on.
enum Activity: Equatable {
    case idle
    case scanning
    case sweeping(Sweeper.Progress)
    case pruning(repositories: Int)
    case removing(name: String)

    var isBusy: Bool { self != .idle }

    /// Whether this blocks destructive actions. Scanning is read-only, so it
    /// does not.
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
        case .sweeping: return "Sweeping build artifacts"
        case .pruning(let count): return "Pruning \(count) repositor\(count == 1 ? "y" : "ies")"
        case .removing(let name): return "Removing \(name)"
        }
    }

    /// Detail line under the title, naming the item in flight.
    var detail: String? {
        switch self {
        case .sweeping(let progress):
            guard progress.total > 0 else { return nil }
            let position = "\(min(progress.completed + 1, progress.total)) of \(progress.total)"
            if progress.currentName.isEmpty { return position }
            return "\(position) · \(progress.currentName)"
        default: return nil
        }
    }

    /// Determinate fraction where one is known, nil where the work is a single
    /// indivisible step and a spinner is honest.
    var fraction: Double? {
        if case .sweeping(let progress) = self, progress.total > 0 { return progress.fraction }
        return nil
    }

    var freedSoFar: Int64? {
        if case .sweeping(let progress) = self, progress.freedBytes > 0 { return progress.freedBytes }
        return nil
    }
}

/// The outcome of the last operation, shown until dismissed or superseded.
struct Banner: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case warning
        case failure

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
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

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var reports: [WorktreeReport] = []
    @Published private(set) var activity: Activity = .idle
    @Published private(set) var lastScan: Date?
    @Published private(set) var detectedHarnesses: [Harness] = []
    @Published var banner: Banner?
    @Published var selection: String?

    var isScanning: Bool { activity == .scanning }
    /// True while something is being deleted. Read-only scanning does not count,
    /// or the whole UI would disable itself every time FSEvents fired.
    var isWorking: Bool { activity.isMutating }
    /// The background size walk. Not an `Activity` because it runs alongside a
    /// perfectly usable list and must never disable anything.
    @Published private(set) var isMeasuring = false
    /// True while pull request state is being looked up.
    @Published private(set) var isCheckingPullRequests = false
    /// Whether the GitHub CLI is present at all. Drives whether the UI offers
    /// PR context or quietly omits it.
    let canCheckPullRequests = GitHub.isInstalled

    private let settings: AppSettings
    private var watcher: DirectoryWatcher?
    private var hasStarted = false
    private var scanTask: Task<Void, Never>?
    private var measureTask: Task<Void, Never>?
    private var pullRequestTask: Task<Void, Never>?

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

    /// Harnesses that actually produced a worktree here. The sidebar lists these
    /// rather than every case, so a tool the user does not run never appears.
    var presentHarnesses: [Harness] {
        let found = Set(visibleReports.map(\.worktree.harness))
        return Harness.allCases.filter(found.contains)
    }
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
        guard !activity.isBusy else { return }
        scanTask?.cancel()
        measureTask?.cancel()
        activity = .scanning

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
            self.activity = .idle
            Log.shared.write(
                "scan: \(self.visibleReports.count) worktrees, "
                + "\(self.protectedCount) protected, \(self.groups.count) repos"
            )
            self.measureSizes()
            self.fetchPullRequests()
        }
    }

    /// Looks up pull request state for every repository, one call each.
    ///
    /// Runs after the list is already on screen, because it is a network call
    /// and the app must stay usable without it. A worktree whose PR is merged
    /// or closed is the clearest signal that its uncommitted leftovers are
    /// debris rather than work, which is what makes overriding a block a
    /// reasonable thing to offer.
    func fetchPullRequests() {
        guard canCheckPullRequests, settings.checkPullRequests else { return }
        pullRequestTask?.cancel()

        let repos = Array(Set(reports.map(\.worktree.repoPath)))
        guard !repos.isEmpty else { return }
        isCheckingPullRequests = true

        pullRequestTask = Task { [weak self] in
            defer { Task { @MainActor in self?.isCheckingPullRequests = false } }
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
        }
    }

    /// Stage two: walk each worktree for its size, one at a time at low priority,
    /// publishing as each finishes. Sequential on purpose. Ten concurrent walks
    /// over node_modules trees would saturate the disk queue and make the
    /// foreground feel slow, which is a bad trade for a background utility.
    private func measureSizes() {
        measureTask?.cancel()
        let targets = reports.filter { !$0.measured }.map(\.worktree.path)
        guard !targets.isEmpty else { isMeasuring = false; return }

        isMeasuring = true
        measureTask = Task { [weak self] in
            defer { Task { @MainActor in self?.isMeasuring = false } }
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

    /// Sweeps build artifacts, reporting progress per worktree so the UI can show
    /// a determinate bar and name what is in flight.
    func sweep(_ targets: [WorktreeReport]) async {
        guard !targets.isEmpty, !activity.isBusy else { return }
        banner = nil
        activity = .sweeping(
            Sweeper.Progress(completed: 0, total: targets.count, currentName: "", freedBytes: 0)
        )
        defer { activity = .idle }

        let scanner = self.scanner
        // The callback fires on the worker; hop back to the main actor to publish.
        let outcome = await Task.detached(priority: .userInitiated) { [weak self] in
            Sweeper.sweep(
                reports: targets,
                scanner: scanner,
                log: { Log.shared.write($0) },
                onProgress: { progress in
                    Task { @MainActor in self?.activity = .sweeping(progress) }
                }
            )
        }.value

        banner = Self.banner(for: outcome, verb: "Swept", noun: "build artifacts")
        markUnmeasured(targets.map(\.worktree.path))
        rescan()
    }

    func prune() async {
        let repos = Array(Set(prunableReports.map(\.worktree.repoPath)))
        guard !repos.isEmpty, !activity.isBusy else { return }
        banner = nil
        activity = .pruning(repositories: repos.count)
        defer { activity = .idle }

        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.prune(repositories: repos) { Log.shared.write($0) }
        }.value

        if outcome.failures.isEmpty {
            let count = outcome.removedPaths.count
            banner = Banner(
                kind: .success,
                title: "Pruned stale worktrees",
                message: "Cleared metadata in \(count) repositor\(count == 1 ? "y" : "ies"). Nothing on disk was touched."
            )
        } else {
            banner = Banner(
                kind: .failure,
                title: "Prune failed",
                message: "\(outcome.failures.count) repositor\(outcome.failures.count == 1 ? "y" : "ies") could not be pruned.",
                details: outcome.failures
            )
        }
        rescan()
    }

    func remove(_ report: WorktreeReport, deleteBranch: Bool, force: Bool = false) async {
        guard !activity.isBusy else { return }
        banner = nil
        activity = .removing(name: report.worktree.name)
        defer { activity = .idle }

        let scanner = self.scanner
        // Rescue local config even on a forced removal. The user chose to
        // discard their *work*; that is not the same as choosing to lose the
        // API keys that happened to sit in the same directory.
        let rescue = settings.rescueIgnoredConfig ? settings.rescueDirectory : nil
        let outcome = await Task.detached(priority: .userInitiated) {
            Sweeper.remove(
                report: report,
                scanner: scanner,
                deleteBranch: deleteBranch,
                rescueDirectory: rescue,
                force: force
            ) { Log.shared.write($0) }
        }.value

        if outcome.removedPaths.isEmpty {
            // Refused rather than failed: the verdict changed between the scan
            // and the click, which is the case this whole design exists for.
            let reason = outcome.skipped.first?.reason ?? outcome.failures.first?.reason ?? "the verdict changed"
            banner = Banner(
                kind: outcome.failures.isEmpty ? .warning : .failure,
                title: "Kept \(report.worktree.name)",
                message: "Removal was refused because \(reason).",
                details: outcome.failures
            )
        } else {
            let discarded = force ? " Uncommitted work was discarded." : ""
            banner = Banner(
                kind: outcome.failures.isEmpty ? .success : .warning,
                title: "Removed \(report.worktree.name)",
                message: "Freed \(Format.bytes(outcome.freedBytes)).\(discarded) "
                    + "The directory is in the Trash if you need it back.",
                details: outcome.failures + outcome.skipped
            )
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

    /// Turns an outcome into the one message the user sees.
    ///
    /// Freeing nothing is not a success, and freeing something while failing on
    /// three paths is not either — those are the two cases a bare "Done" hides.
    static func banner(for outcome: Sweeper.Outcome, verb: String, noun: String) -> Banner {
        if !outcome.failures.isEmpty && !outcome.didAnything {
            return Banner(
                kind: .failure,
                title: "Could not \(verb.lowercased()) \(noun)",
                message: "\(outcome.failures.count) item\(outcome.failures.count == 1 ? "" : "s") could not be deleted.",
                details: outcome.failures
            )
        }
        if outcome.hasProblems {
            var parts: [String] = []
            if !outcome.skipped.isEmpty { parts.append("\(outcome.skipped.count) skipped") }
            if !outcome.failures.isEmpty { parts.append("\(outcome.failures.count) failed") }
            return Banner(
                kind: .warning,
                title: "\(verb) \(Format.bytes(outcome.freedBytes))",
                message: parts.joined(separator: ", ") + ". Everything else was removed.",
                details: outcome.failures + outcome.skipped
            )
        }
        if !outcome.didAnything {
            return Banner(
                kind: .success,
                title: "Nothing to \(verb.lowercased())",
                message: "No \(noun) were found to remove."
            )
        }
        return Banner(
            kind: .success,
            title: "\(verb) \(Format.bytes(outcome.freedBytes))",
            message: "Removed \(outcome.removedPaths.count) folder"
                + "\(outcome.removedPaths.count == 1 ? "" : "s"). Reinstall to bring them back."
        )
    }

    /// Called when roots or harness selection change, so the watcher follows.
    func settingsChanged() {
        restartWatcher()
        detectedHarnesses = Harness.detected(home: FileManager.default.homeDirectoryForCurrentUser)
        rescan()
    }
}
