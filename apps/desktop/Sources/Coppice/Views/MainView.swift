import SwiftUI

/// What the sidebar is filtering the list down to.
enum Scope: Hashable {
    case all
    case sweepable
    case needsAttention
    case stale
    case harness(Harness)

    var title: String {
        switch self {
        case .all: return "All Worktrees"
        case .sweepable: return "Safe to Sweep"
        case .needsAttention: return "Needs Attention"
        case .stale: return "Stale"
        case .harness(let harness): return harness.displayName
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .sweepable: return "scissors"
        case .needsAttention: return "lock"
        case .stale: return "clock.arrow.circlepath"
        case .harness(let harness): return harness.symbol
        }
    }
}

/// The main window: source list, worktree list, inspector.
///
/// The standard three-pane Mac shape (Mail, Finder, Xcode) rather than a bespoke
/// layout, so the window behaves the way the rest of the system does. Sidebar
/// collapsing, inspector toggling, selection, search and keyboard navigation all
/// come from the framework instead of being reinvented.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var scope: Scope = .all
    @State private var showInspector = true
    @State private var search = ""
    @State private var confirmingSweep = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Coppice")
        .navigationSubtitle(subtitle)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $scope) {
            Section {
                sidebarRow(.all, count: model.visibleReports.count)
                sidebarRow(.sweepable, count: model.sweepCandidates.count)
                sidebarRow(.needsAttention, count: model.protectedCount)
                sidebarRow(.stale, count: model.prunableReports.count)
            }

            Section("Created By") {
                ForEach(model.presentHarnesses, id: \.self) { harness in
                    sidebarRow(
                        .harness(harness),
                        count: model.visibleReports.filter { $0.worktree.harness == harness }.count
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
    }

    private func sidebarRow(_ scope: Scope, count: Int) -> some View {
        Label(scope.title, systemImage: scope.symbol)
            .badge(count)
            .tag(scope)
    }

    // MARK: Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if let banner = model.banner {
                BannerView(banner: banner) {
                    withAnimation { model.banner = nil }
                }
                Divider()
            }

            if model.activity.isBusy {
                ActivityBar(activity: model.activity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                Divider()
            }

            if filteredGroups.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                worktreeList
            }
        }
        .animation(.default, value: model.banner)
        .animation(.default, value: model.activity.isBusy)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter worktrees")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 270, ideal: 310, max: 400)
        }
        .confirmationDialog(
            "Sweep build artifacts in \(model.sweepCandidates.count) worktrees?",
            isPresented: $confirmingSweep,
            titleVisibility: .visible
        ) {
            Button("Sweep \(Format.bytes(model.reclaimableBytes))") {
                Task { await model.sweep(model.sweepCandidates) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Source, git history and local config are untouched. An install command rebuilds everything this removes.")
        }
    }

    private var worktreeList: some View {
        List(selection: $model.selection) {
            ForEach(filteredGroups, id: \.repo) { group in
                Section {
                    ForEach(group.reports) { report in
                        WorktreeRow(report: report).tag(report.id)
                    }
                } header: {
                    HStack {
                        Text(group.repo)
                        Spacer()
                        Text(Format.compactBytes(group.reports.reduce(0) { $0 + $1.totalBytes }))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.isScanning ? "Scanning" : "No Worktrees",
                systemImage: model.isScanning ? "arrow.triangle.2.circlepath" : "square.stack.3d.up.slash"
            )
        } description: {
            if model.isScanning {
                Text("Reading git metadata across your scan folders.")
            } else if !search.isEmpty {
                Text("Nothing matches that filter.")
            } else {
                Text("Coppice looks in your code folders and in the agent worktree directories.")
            }
        } actions: {
            if !model.isScanning, search.isEmpty {
                SettingsLink { Text("Open Settings…") }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { model.rescan() } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(model.isScanning)
            .help("Rescan every worktree (⌘R)")
        }

        ToolbarItem(placement: .status) {
            // Sizing runs after the list is already usable, so it gets a quiet
            // indicator rather than blocking the window behind a spinner.
            if model.isScanning || model.isMeasuring {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(model.isScanning ? "Scanning" : "Sizing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                confirmingSweep = true
            } label: {
                Label(
                    model.reclaimableBytes > 0 ? "Sweep \(Format.compactBytes(model.reclaimableBytes))" : "Sweep",
                    systemImage: "scissors"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.sweepCandidates.isEmpty || model.isWorking)
            .help("Delete regenerable build output. Reversible by reinstalling.")
        }

        ToolbarItem(placement: .primaryAction) {
            // Settings belong in the window too, not only behind the menu bar
            // item. Someone working in the window should not have to go hunting
            // in the status bar to change a scan folder.
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Coppice Settings (⌘,)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button { showInspector.toggle() } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector")
        }
    }

    // MARK: Data

    private var subtitle: String {
        if model.isScanning, model.visibleReports.isEmpty { return "Scanning…" }
        let count = model.visibleReports.count
        let measured = model.visibleReports.filter(\.measured).count
        let sizing = measured < count ? " · sizing \(measured) of \(count)" : ""
        return "\(count) worktrees · \(Format.bytes(model.totalBytes))\(sizing)"
    }

    /// Groups after the sidebar scope and the search field have both been applied.
    private var filteredGroups: [(repo: String, harness: Harness, reports: [WorktreeReport])] {
        model.groups.compactMap { group in
            let matching = group.reports.filter { matchesScope($0) && matchesSearch($0) }
            guard !matching.isEmpty else { return nil }
            return (group.repo, group.harness, matching)
        }
    }

    private func matchesScope(_ report: WorktreeReport) -> Bool {
        switch scope {
        case .all: return true
        case .sweepable: return report.verdict.canSweep && report.artifactBytes > 0
        case .needsAttention: return !report.verdict.canRemove
        case .stale: return report.verdict == .prunable || report.verdict == .orphan
        case .harness(let harness): return report.worktree.harness == harness
        }
    }

    private func matchesSearch(_ report: WorktreeReport) -> Bool {
        guard !search.isEmpty else { return true }
        let needle = search.lowercased()
        return report.worktree.name.lowercased().contains(needle)
            || report.worktree.displayBranch.lowercased().contains(needle)
            || report.worktree.repoName.lowercased().contains(needle)
    }
}

/// One worktree. Name and branch lead, size and verdict trail.
struct WorktreeRow: View {
    let report: WorktreeReport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: report.verdict.symbol)
                .foregroundStyle(report.verdict.tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(report.worktree.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(report.worktree.displayBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if report.artifactBytes > 0 {
                Text(Format.compactBytes(report.artifactBytes))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.green)
                    .help("Regenerable build output — this is what a sweep frees")
            }

            Text(report.measured ? Format.compactBytes(report.totalBytes) : "—")
                .monospacedDigit()
                .foregroundStyle(report.measured ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 66, alignment: .trailing)

            VerdictBadge(verdict: report.verdict)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
