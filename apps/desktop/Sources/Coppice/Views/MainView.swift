import SwiftUI

enum Scope: Hashable {
    case all
    case sweepable
    case hasWork
    case stale
    case harness(Harness)

    var title: String {
        switch self {
        case .all: return "All Worktrees"
        case .sweepable: return "Safe to Sweep"
        case .hasWork: return "Has Work"
        case .stale: return "Stale"
        case .harness(let harness): return harness.displayName
        }
    }

    func contains(_ report: WorktreeReport) -> Bool {
        switch self {
        case .all: return true
        case .sweepable: return report.verdict.canSweep && report.artifactBytes > 0
        case .hasWork: return report.verdict.status == .hasWork
        case .stale: return report.verdict == .prunable || report.verdict == .orphan
        case .harness(let harness): return report.worktree.harness == harness
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .sweepable: return "scissors"
        case .hasWork: return "pencil.circle"
        case .stale: return "clock.arrow.circlepath"
        case .harness(let harness): return harness.symbol
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var scope: Scope = .all
    @State private var showInspector = true
    @State private var search = ""
    @State private var confirmingSweep = false
    @AppStorage("dismissedDiskAccess") private var dismissedDiskAccess = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Coppice")
        .navigationSubtitle(subtitle)
    }

    private var sidebar: some View {
        List(selection: $scope) {
            Section {
                sidebarRow(.all, count: model.visibleReports.count)
                sidebarRow(.sweepable, count: model.sweepCandidates.count)
                sidebarRow(.hasWork, count: model.hasWorkCount)
                sidebarRow(.stale, count: model.visibleReports.filter { Scope.stale.contains($0) }.count)
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

    private var detail: some View {
        VStack(spacing: 0) {
            if !model.unreadableRoots.isEmpty, !dismissedDiskAccess {
                diskAccessBanner
                Divider()
            }

            if let banner = model.banner {
                BannerView(banner: banner) {
                    withAnimation { model.banner = nil }
                }
                Divider()
            }

            if model.activity.isMutating {
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
        .background(.black)
        .animation(.smooth, value: model.banner)
        .animation(.smooth, value: model.activity.isMutating)
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

    private var diskAccessBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text("Coppice can't read \(model.unreadableRoots.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")). Allow Full Disk Access to include it.")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
            Button {
                dismissedDiskAccess = true
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(12)
    }

    private var worktreeList: some View {
        List(selection: $model.selection) {
            ForEach(filteredGroups, id: \.path) { group in
                Section {
                    ForEach(group.reports) { report in
                        WorktreeRow(report: report).tag(report.id)
                    }
                } header: {
                    HStack {
                        Text(group.repo)
                        Spacer()
                        Text(
                            group.reports.contains(where: \.measured)
                                ? Format.compactBytes(group.reports.reduce(0) { $0 + $1.totalBytes })
                                : "—"
                        )
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(.black)
        .animation(.smooth, value: filteredGroups.flatMap { $0.reports.map(\.id) })
    }

    private var foundNothing: Bool {
        !model.isScanning && search.isEmpty && model.visibleReports.isEmpty
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.isScanning ? "Scanning" : foundNothing ? "No Worktrees" : "Nothing in \(scope.title)",
                systemImage: model.isScanning ? "arrow.triangle.2.circlepath" : "square.stack.3d.up.slash"
            )
        } description: {
            if model.isScanning {
                Text("Reading git metadata across your scan folders.")
            } else if !search.isEmpty {
                Text("Nothing matches that filter.")
            } else if foundNothing {
                Text("Coppice looks in your code folders and in the agent worktree directories.")
            }
        } actions: {
            if foundNothing {
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
            .buttonStyle(.mono)
            .contentTransition(.numericText())
            .animation(.smooth, value: model.reclaimableBytes)
            .disabled(model.sweepCandidates.isEmpty || model.isWorking)
            .help("Delete regenerable build output. Reversible by reinstalling.")
        }

        ToolbarItem(placement: .primaryAction) {
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

    private var subtitle: String {
        if model.isScanning, model.visibleReports.isEmpty { return "Scanning…" }
        let count = model.visibleReports.count
        let measured = model.visibleReports.filter(\.measured).count
        let sizing = measured < count ? " · sizing \(measured) of \(count)" : ""
        return "\(count) worktrees · \(Format.bytes(model.totalBytes))\(sizing)"
    }

    private var filteredGroups: [(repo: String, path: String, harness: Harness, reports: [WorktreeReport])] {
        model.groups.compactMap { group in
            let matching = group.reports.filter { scope.contains($0) && matchesSearch($0) }
            guard !matching.isEmpty else { return nil }
            return (group.repo, group.path, group.harness, matching)
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

struct WorktreeRow: View {
    let report: WorktreeReport

    var body: some View {
        HStack(spacing: 10) {
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
                    .foregroundStyle(.secondary)
                    .numeric(report.artifactBytes)
                    .help("Build output a sweep frees")
            }

            Text(report.measured ? Format.compactBytes(report.totalBytes) : "—")
                .monospacedDigit()
                .numeric(report.totalBytes)
                .foregroundStyle(report.measured ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 66, alignment: .trailing)

            VerdictBadge(verdict: report.verdict)
                .frame(width: 100, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
