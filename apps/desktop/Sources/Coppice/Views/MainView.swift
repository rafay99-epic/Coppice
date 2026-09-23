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
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var search = ""
    @AppStorage("dismissedDiskAccess") private var dismissedDiskAccess = false
    @FocusState private var listFocused: Bool
    @FocusState var searchFocused: Bool
    @State private var dismissedFailures: Set<String> = []

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
        }
        .navigationTitle("Coppice")
        .toolbar(removing: .title)
        .font(.ui)
        .animation(.smooth(duration: 0.35), value: model.settingsPane)
    }

    private var sidebar: some View {
        ZStack {
            if let pane = model.settingsPane {
                settingsSidebar(selected: pane)
                    .transition(.move(edge: .trailing))
            } else {
                scopeSidebar
                    .transition(.move(edge: .leading))
            }
        }
        .clipped()
        .background(.black)
        .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 320)
    }

    private var scopeSidebar: some View {
        List {
            Section {
                sidebarRow(.all, count: model.visibleReports.count)
                sidebarRow(.sweepable, count: model.sweepCandidates.count)
                sidebarRow(.hasWork, count: model.hasWorkCount)
                sidebarRow(.stale, count: model.visibleReports.filter { Scope.stale.contains($0) }.count)
            }

            Section {
                ForEach(model.presentHarnesses, id: \.self) { harness in
                    sidebarRow(
                        .harness(harness),
                        count: model.visibleReports.filter { $0.worktree.harness == harness }.count
                    )
                }
            } header: {
                SectionLabel("Created by")
                    .padding(.top, Space.l)
                    .padding(.leading, Space.s)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarRow(title: "Settings", symbol: "gearshape", selected: false) {
                model.settingsPane = .general
            }
            .padding(.horizontal, Space.m + Space.xs)
            .padding(.vertical, Space.s)
            .background(.black)
        }
    }

    private func sidebarRow(_ row: Scope, count: Int) -> some View {
        SidebarRow(title: row.title, symbol: row.symbol, selected: scope == row, count: count) {
            scope = row
        }
        .accessibilityValue("\(count) worktrees")
        .listRowInsets(EdgeInsets(top: 1, leading: Space.s, bottom: 1, trailing: Space.s))
    }

    private var detail: some View {
        ZStack {
            if let pane = model.settingsPane {
                settingsDetail(pane)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                worktreeDetail
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(.black)
        .toolbar { toolbar }
        .inspector(isPresented: inspectorVisible) {
            InspectorView()
                .inspectorColumnWidth(min: 290, ideal: 330, max: 420)
        }
        .confirmationDialog(
            "Sweep build artifacts in \(model.sweepCandidates.count) worktrees?",
            isPresented: $model.confirmingSweep,
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

    private var inspectorVisible: Binding<Bool> {
        Binding(
            get: { showInspector && model.settingsPane == nil },
            set: { showInspector = $0 }
        )
    }

    private var worktreeDetail: some View {
        VStack(spacing: 0) {
            if !model.unreadableRoots.isEmpty, !dismissedDiskAccess {
                diskAccessBanner
                Divider()
            }

            if let failures = visibleFailures {
                BannerView(banner: failures) {
                    withAnimation { dismissedFailures.formUnion(model.scanFailures.map(\.id)) }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.m)
            }

            if let banner = model.banner {
                BannerView(banner: banner) {
                    withAnimation { model.banner = nil }
                }
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.m)
            }

            if model.activity.isMutating {
                ActivityBar(activity: model.activity)
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.m)
                Divider()
            }

            header

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
    }

    private var visibleFailures: Banner? {
        let fresh = model.scanFailures.filter { !dismissedFailures.contains($0.id) }
        guard !fresh.isEmpty else { return nil }
        let count = fresh.count
        return Banner(
            kind: .warning,
            title: "Couldn't read \(count) repositor\(count == 1 ? "y" : "ies")",
            message: "They were skipped in this scan. The log has the git error.",
            details: fresh
        )
    }

    private var unreadableList: String {
        model.unreadableRoots.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", ")
    }

    private var diskAccessBanner: some View {
        HStack(spacing: Space.m) {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
            Text("Coppice can't read \(unreadableList). Allow Full Disk Access to include it.")
                .font(.uiCallout)
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
            .accessibilityLabel("Dismiss")
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.m) {
                Text(scope.title)
                    .font(.display(30))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: scope)
                Spacer(minLength: Space.m)
                headerActions
            }
            HStack(spacing: Space.m) {
                Text(subtitle)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .numeric(subtitle)
                Spacer(minLength: Space.m)
                activityStatus
                    .opacity(model.isScanning || model.isMeasuring ? 1 : 0)
                    .animation(.smooth, value: model.isScanning || model.isMeasuring)
                    .frame(width: 130, alignment: .trailing)
                filterField
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private var worktreeList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredGroups, id: \.path) { group in
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.repo)
                            .font(.heading(15, italic: true))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            group.reports.contains(where: \.measured)
                                ? Format.compactBytes(group.reports.reduce(0) { $0 + $1.totalBytes })
                                : "…"
                        )
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    }
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xs)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: Space.xl, bottom: 0, trailing: Space.xl))
                    ForEach(group.reports) { report in
                        let selected = model.selection == report.id
                        WorktreeRow(report: report)
                            .id(report.id)
                            .contentShape(.rect)
                            .onTapGesture { select(report.id) }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(report.accessibilitySummary)
                            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { select(report.id) }
                            .listRowInsets(EdgeInsets(top: 0, leading: Space.xl, bottom: 0, trailing: Space.xl))
                            .listRowSeparatorTint(.white.opacity(0.06))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.white.opacity(selected ? 0.1 : 0))
                                    .padding(.horizontal, Space.s)
                                    .animation(.snappy(duration: 0.2), value: selected)
                            )
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(.black)
            .focusable()
            .focused($listFocused)
            .defaultFocus($listFocused, true)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { moveSelection(by: -1) }
            .onKeyPress(.downArrow) { moveSelection(by: 1) }
            .animation(.smooth, value: filteredGroups.flatMap { $0.reports.map(\.id) })
            .onChange(of: model.selection) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id) }
            }
            .onChange(of: filteredGroups.flatMap { $0.reports.map(\.id) }) { _, ids in
                if let selection = model.selection, !ids.contains(selection) { model.selection = nil }
            }
        }
    }

    private func select(_ id: String) {
        model.selection = id
        listFocused = true
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        let ids = filteredGroups.flatMap { $0.reports.map(\.id) }
        guard !ids.isEmpty else { return .ignored }
        let current = model.selection.flatMap { ids.firstIndex(of: $0) }
        let next = current.map { min(max($0 + offset, 0), ids.count - 1) } ?? 0
        model.selection = ids[next]
        return .handled
    }

    private var foundNothing: Bool {
        !model.isScanning && search.isEmpty && model.visibleReports.isEmpty
    }

    private var emptyTitle: String {
        if model.isScanning { return "Looking around." }
        if !search.isEmpty { return "No matches." }
        return foundNothing ? "Nothing to cut back." : "All clear here."
    }

    private var emptyDetail: String {
        if model.isScanning { return "Reading git metadata across your folders." }
        if !search.isEmpty { return "Nothing matches that filter." }
        return foundNothing ? "Coppice checks your code folders and agent directories." : "No worktrees in \(scope.title)."
    }

    private var emptyState: some View {
        VStack(spacing: Space.l) {
            GrowingStump(lineWidth: 1.2)
                .frame(height: 110)
                .foregroundStyle(.secondary)
            Text(emptyTitle)
                .font(.display(26, italic: true))
            Text(emptyDetail)
                .font(.uiCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if foundNothing {
                Button("Open Settings") { model.openSettings(.scanning) }
                    .buttonStyle(.mono)
                    .padding(.top, Space.s)
            }
        }
        .padding(Space.xxl)
    }

    private var subtitle: String {
        if model.isScanning, model.visibleReports.isEmpty { return "Scanning…" }
        let count = model.visibleReports.count
        return "\(count) worktrees · \(Format.bytes(model.totalBytes))"
    }

    private var filteredGroups: [RepoGroup] {
        model.groups.compactMap { group in
            let matching = group.reports.filter { scope.contains($0) && matchesSearch($0) }
            guard !matching.isEmpty else { return nil }
            return RepoGroup(path: group.path, reports: matching)
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

extension MainView {
    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.smooth) { columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly }
            } label: {
                Label("Sidebar", systemImage: "sidebar.leading")
            }
            .help("Show or hide the sidebar")
        }
        .withoutGlass()
    }

    var headerActions: some View {
        HStack(spacing: Space.m) {
            Button {
                model.confirmingSweep = true
            } label: {
                ZStack {
                    Label("Sweep 888.8 MB", systemImage: "scissors").hidden()
                    Label(
                        model.reclaimableBytes > 0 ? "Sweep \(Format.compactBytes(model.reclaimableBytes))" : "Sweep",
                        systemImage: "scissors"
                    )
                    .numeric(model.reclaimableBytes)
                }
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.mono)
            .disabled(model.sweepCandidates.isEmpty || model.isWorking)
            .help("Delete regenerable build output. Reversible by reinstalling.")

            Button { model.rescan() } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: model.isScanning)
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .disabled(model.isScanning)
            .accessibilityLabel("Rescan")
            .help("Rescan every worktree (⌘R)")

            Button { showInspector.toggle() } label: {
                Image(systemName: "sidebar.trailing")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Inspector")
            .help("Show or hide the inspector")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .imageScale(.large)
    }

    var filterField: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Filter worktrees", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand { search = "" }
                .task { searchFocused = false }
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Clear filter")
            }
        }
        .font(.uiCallout)
        .padding(.horizontal, Space.s)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(searchFocused ? 0.35 : 0.14)))
        .frame(maxWidth: 240)
        .background {
            Button("Find") { searchFocused = true }
                .keyboardShortcut("f")
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    func settingsSidebar(selected: SettingsPane) -> some View {
        List {
            SidebarRow(title: "Back", symbol: "chevron.left", selected: false) {
                model.settingsPane = nil
            }
            .keyboardShortcut(.cancelAction)
            .listRowInsets(EdgeInsets(top: 1, leading: Space.s, bottom: 1, trailing: Space.s))

            Section {
                ForEach(SettingsPane.allCases) { pane in
                    SidebarRow(title: pane.title, symbol: pane.symbol, selected: pane == selected) {
                        model.settingsPane = pane
                    }
                    .listRowInsets(EdgeInsets(top: 1, leading: Space.s, bottom: 1, trailing: Space.s))
                }
            } header: {
                SectionLabel("Settings")
                    .padding(.top, Space.m)
                    .padding(.leading, Space.s)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    func settingsDetail(_ pane: SettingsPane) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(pane.title)
                .font(.display(30))
                .contentTransition(.opacity)
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.l)
            SettingsPaneView(pane: pane)
                .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var sizingProgress: (done: Int, total: Int) {
        (model.visibleReports.filter(\.measured).count, model.visibleReports.count)
    }

    var activityStatus: some View {
        let progress = sizingProgress
        return HStack(spacing: Space.s) {
            if model.isScanning {
                Text("Scanning")
            } else {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: Double(progress.done) / Double(max(progress.total, 1)))
                        .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: progress.done)
                }
                .frame(width: 11, height: 11)
                Text("Sizing \(progress.done) of \(progress.total)")
                    .monospacedDigit()
                    .numeric(progress.done)
            }
        }
        .font(.uiCaption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

extension WorktreeReport {
    var accessibilitySummary: String {
        let size = measured ? Format.bytes(totalBytes) : "size pending"
        return "\(worktree.name), \(worktree.displayBranch), \(size), \(verdict.shortLabel)"
    }
}

struct SidebarRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var count: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(selected ? .primary : .tertiary)
                Text(title)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: Space.xs)
                if let count {
                    Text("\(count)")
                        .font(.uiCaption)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .numeric(count)
                        .fixedSize()
                }
            }
            .font(.ui.weight(selected ? .medium : .regular))
            .padding(.horizontal, Space.s)
            .padding(.vertical, 7)
            .contentShape(.rect)
            .background(.white.opacity(selected ? 0.12 : 0), in: .rect(cornerRadius: 6))
            .animation(.snappy(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WorktreeRow: View {
    let report: WorktreeReport

    var body: some View {
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(report.worktree.name)
                    .font(.ui.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(report.worktree.displayBranch)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Space.s)

            if report.artifactBytes > 0 {
                Text(Format.compactBytes(report.artifactBytes))
                    .font(.uiCaption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .numeric(report.artifactBytes)
                    .help("Build output a sweep frees")
            }

            Text(report.measured ? Format.compactBytes(report.totalBytes) : "…")
                .monospacedDigit()
                .numeric(report.totalBytes)
                .foregroundStyle(report.measured ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 72, alignment: .trailing)

            VerdictBadge(verdict: report.verdict)
                .frame(width: 96, alignment: .leading)
        }
        .padding(.vertical, Space.m)
    }
}
