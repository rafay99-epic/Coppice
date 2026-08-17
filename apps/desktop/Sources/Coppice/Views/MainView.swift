import SwiftUI

/// The full list. Grouped by repository, verdict on every row, inspector on the
/// right for whatever is selected.
struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.lineStrong)
            statsRow
            Divider().overlay(Theme.lineStrong)

            HStack(spacing: 0) {
                listPane
                if model.selectedReport != nil {
                    Divider().overlay(Theme.lineStrong)
                    InspectorView()
                        .frame(width: 320)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Theme.motion, value: model.selection)

            Divider().overlay(Theme.lineStrong)
            statusBar
        }
        .background(Theme.background)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Worktrees")
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()

            Button("Rescan") { model.rescan() }
                .buttonStyle(SecondaryButton())
                .disabled(model.isScanning)

            if !model.prunableReports.isEmpty {
                Button("Prune \(model.prunableReports.count)") {
                    Task { await model.prune() }
                }
                .buttonStyle(SecondaryButton())
                .disabled(model.isWorking)
            }

            Button {
                Task { await model.sweep(model.sweepCandidates) }
            } label: {
                Text(model.reclaimableBytes > 0
                     ? "Sweep \(Format.bytes(model.reclaimableBytes))"
                     : "Nothing to sweep")
            }
            .buttonStyle(PrimaryButton())
            .disabled(model.sweepCandidates.isEmpty || model.isWorking)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    private var subtitle: String {
        let repos = model.groups.count
        return "\(model.visibleReports.count) across \(repos) repo\(repos == 1 ? "" : "s") · \(Format.bytes(model.totalBytes))"
    }

    private var statsRow: some View {
        HStack(spacing: 1) {
            StatTile(value: Format.bytes(model.reclaimableBytes), label: "reclaimable now", tint: Theme.safe)
            StatTile(value: "\(model.sweepCandidates.count)", label: "sweepable worktrees")
            StatTile(value: "\(model.protectedCount)", label: "protected", tint: Theme.blocked)
            StatTile(value: "\(model.prunableReports.count)", label: "prunable", tint: Theme.info)
        }
        .background(Theme.line)
        .animation(Theme.motion, value: model.reclaimableBytes)
    }

    // MARK: List

    private var listPane: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if model.visibleReports.isEmpty {
                    emptyState
                }
                ForEach(model.groups, id: \.repo) { group in
                    Section {
                        ForEach(group.reports) { report in
                            WorktreeRow(report: report, isSelected: model.selection == report.id)
                                .onTapGesture {
                                    model.selection = model.selection == report.id ? nil : report.id
                                }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func groupHeader(_ group: (repo: String, harness: Harness, reports: [WorktreeReport])) -> some View {
        let bytes = group.reports.reduce(0) { $0 + $1.totalBytes }
        return HStack(spacing: 7) {
            Image(systemName: group.harness.symbol)
                .font(.system(size: 9))
                .foregroundStyle(Theme.tertiary)
            SectionLabel(text: "\(group.repo) · \(group.harness.displayName) · \(group.reports.count)")
            Spacer()
            Text(Format.bytes(bytes))
                .font(Theme.mono(9))
                .foregroundStyle(Theme.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(Theme.panel)
        .hairline()
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.isScanning ? "Scanning…" : "No worktrees found")
                .font(.system(size: 14, weight: .medium))
            Text(model.isScanning
                 ? "Reading git metadata across your scan roots."
                 : """
                   Coppice looks in your code roots and in the agent worktree \
                   directories. Add a root in Settings if something is missing.
                   """)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
    }

    // MARK: Status

    private var statusBar: some View {
        HStack(spacing: 10) {
            if model.isScanning {
                Text("Scanning")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.secondary)
            } else if let message = model.statusMessage {
                Text(message)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.secondary)
            } else {
                Text("Sweeping is reversible. Removing is not.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            let measured = model.visibleReports.filter(\.measured).count
            if measured < model.visibleReports.count {
                Text("sizing \(measured)/\(model.visibleReports.count)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            if !model.visibleReports.isEmpty {
                ProgressStrip(
                    fraction: Double(model.visibleReports.filter(\.measured).count)
                        / Double(model.visibleReports.count)
                )
            }
        }
    }
}

/// One worktree. Name and branch left, size and verdict right.
struct WorktreeRow: View {
    let report: WorktreeReport
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(isSelected ? Theme.primary : .clear)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(report.worktree.name)
                    .font(Theme.mono(12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(report.worktree.displayBranch)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            if report.artifactBytes > 0 {
                Text(Format.bytes(report.artifactBytes))
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.safe.opacity(0.85))
                    .help("Regenerable build artifacts")
            }

            Text(report.measured ? Format.bytes(report.totalBytes) : "—")
                .font(Theme.mono(11))
                .foregroundStyle(report.measured ? Theme.primary : Theme.tertiary)
                .frame(width: 72, alignment: .trailing)
                .contentTransition(.numericText())

            VerdictBadge(verdict: report.verdict)
                .frame(width: 168, alignment: .leading)
        }
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
        .hairline()
        .opacity(report.verdict.canRemove ? 1 : 0.72)
    }

    private var rowBackground: Color {
        if isSelected { return Theme.elevated }
        return hovering ? Theme.panel : .clear
    }
}

// MARK: - Buttons

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.black : Theme.tertiary)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(isEnabled ? Theme.primary : Theme.line, in: RoundedRectangle(cornerRadius: 6))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.fade, value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .foregroundStyle(isEnabled ? Theme.primary : Theme.tertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineStrong, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.fade, value: configuration.isPressed)
    }
}

struct DangerButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Theme.blocked : Theme.tertiary)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Theme.blocked.opacity(isEnabled ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.blocked.opacity(isEnabled ? 0.42 : 0.15), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.fade, value: configuration.isPressed)
    }
}
