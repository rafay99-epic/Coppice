import SwiftUI

/// Detail for the selected worktree, and the only place Remove exists.
///
/// The destructive action is deliberately not on the list row. Sweeping is one
/// click because it is reversible; removing takes a selection, a scroll and a
/// typed confirmation because it is not.
struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmingRemoval = false
    @State private var deleteBranch = false

    private var report: WorktreeReport? { model.selectedReport }

    var body: some View {
        ScrollView {
            if let report {
                VStack(alignment: .leading, spacing: 18) {
                    identity(report)
                    sizes(report)
                    verdictSection(report)
                    facts(report)
                    if !report.artifacts.isEmpty { artifacts(report) }
                    removal(report)
                }
                .padding(18)
            }
        }
        .background(Theme.panel)
        .sheet(isPresented: $confirmingRemoval) {
            if let report {
                RemoveConfirmation(report: report, deleteBranch: $deleteBranch) {
                    Task { await model.remove(report, deleteBranch: deleteBranch) }
                }
            }
        }
    }

    private func identity(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(report.worktree.name)
                .font(Theme.mono(15, weight: .semibold))
                .textSelection(.enabled)
            Text(report.worktree.displayBranch)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.secondary)
                .textSelection(.enabled)
            Text(report.worktree.path)
                .font(Theme.mono(9))
                .foregroundStyle(Theme.tertiary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sizes(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Size on disk")
            if report.measured {
                sizeRow("Build artifacts", report.artifactBytes, Theme.safe, "regenerable, sweep frees this")
                sizeRow("Everything else", report.uniqueBytes, Theme.primary, "only recoverable from the Trash")
            } else {
                Text("Measuring…")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    private func sizeRow(_ label: String, _ bytes: Int64, _ tint: Color, _ help: String) -> some View {
        HStack {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label).font(.system(size: 11))
            Spacer()
            Text(Format.bytes(bytes))
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(tint)
        }
        .help(help)
    }

    private func verdictSection(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Verdict")
            VerdictBadge(verdict: report.verdict)
            switch report.verdict {
            case .blocked(let blocker):
                Text(blocker.remedy)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .ignoredConfig(let files) = blocker {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(files, id: \.self) { file in
                            Text(file)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.blocked)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.blocked.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                }
            case .caution(let list):
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(list, id: \.self) { caution in
                        Label(caution.summary, systemImage: "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.caution)
                    }
                }
            case .safe:
                Text("Clean, pushed, nothing running here, no local-only config.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .prunable:
                Text("The directory is already gone. Pruning clears the leftover git metadata and touches nothing on disk.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .orphan:
                Text("The parent repository no longer exists, so no git command can reach this. Nothing can reclaim it.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func facts(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Details")
            fact("Repository", report.worktree.repoName)
            fact("Created by", report.worktree.harness.displayName)
            fact("HEAD", report.worktree.head.isEmpty ? "unknown" : String(report.worktree.head.prefix(10)))
            fact("Sweepable", report.verdict.canSweep ? "yes" : "no, something is running here")
            fact("Removable", report.verdict.canRemove ? "yes" : "no")
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .font(Theme.mono(10))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func artifacts(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Build artifacts (\(report.artifacts.count))")
            ForEach(report.artifacts.sorted { $0.bytes > $1.bytes }) { artifact in
                HStack {
                    Text(artifact.kind)
                        .font(Theme.mono(10))
                    Spacer()
                    Text(Format.bytes(artifact.bytes))
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
    }

    private func removal(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider().overlay(Theme.line)

            if report.verdict.canSweep && report.artifactBytes > 0 {
                Button("Sweep \(Format.bytes(report.artifactBytes))") {
                    Task { await model.sweep([report]) }
                }
                .buttonStyle(SecondaryButton())
                .disabled(model.isWorking)
            }

            if report.verdict == .prunable {
                Button("Prune metadata") { Task { await model.prune() } }
                    .buttonStyle(SecondaryButton())
                    .disabled(model.isWorking)
            } else {
                Button("Remove worktree…") { confirmingRemoval = true }
                    .buttonStyle(DangerButton())
                    .disabled(!report.verdict.canRemove || model.isWorking)

                if !report.verdict.canRemove {
                    Text("Removal is blocked. Clear the reason above and rescan.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Typed confirmation. The name has to be entered by hand, which is the point:
/// it makes bulk removal impossible and forces the user to read what they picked.
struct RemoveConfirmation: View {
    let report: WorktreeReport
    @Binding var deleteBranch: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var typed = ""

    private var matches: Bool { typed == report.worktree.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Remove this worktree?")
                    .font(.system(size: 15, weight: .semibold))
                Text("The directory goes to the Trash, then git metadata is pruned. Anything gitignored inside has no copy in git.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                fact("Worktree", report.worktree.name)
                fact("Branch", report.worktree.displayBranch)
                fact("Repository", report.worktree.repoName)
                fact("Size", report.measured ? Format.bytes(report.totalBytes) : "not measured")
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 6))

            if settings.rescueIgnoredConfig {
                Label(
                    "Gitignored config is copied to \(settings.rescueDirectory.lastPathComponent) first.",
                    systemImage: "shield.lefthalf.filled"
                )
                .font(.system(size: 10))
                .foregroundStyle(Theme.safe)
            }

            Toggle("Also delete the branch \(report.worktree.branch ?? "")", isOn: $deleteBranch)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .disabled(report.worktree.branch == nil)
                .help("Uses git branch -d, so git still refuses if the branch is unmerged.")

            VStack(alignment: .leading, spacing: 5) {
                Text("Type \(report.worktree.name) to confirm")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                TextField("", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.mono(11))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButton())
                    .keyboardShortcut(.cancelAction)
                Button("Remove") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(DangerButton())
                .disabled(!matches)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondary)
            Spacer()
            Text(value).font(Theme.mono(10))
        }
    }
}
