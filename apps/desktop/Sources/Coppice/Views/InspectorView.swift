import SwiftUI

/// Detail for the selected worktree, and the only place Remove exists.
///
/// Built from `Form` and `LabeledContent` so it inherits the inspector metrics
/// the system already uses in Xcode and Finder's Get Info, rather than
/// hand-rolled rows that drift from them.
struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmingRemoval = false
    @State private var deleteBranch = false
    /// Set when the user opens the sheet from the override button rather than
    /// the normal Remove, so the sheet knows to show what will be discarded.
    @State private var forcing = false

    var body: some View {
        Group {
            if let report = model.selectedReport {
                content(report)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.trailing",
                    description: Text("Select a worktree to see why Coppice reached its verdict.")
                )
            }
        }
        .sheet(isPresented: $confirmingRemoval) {
            if let report = model.selectedReport {
                RemoveSheet(report: report, deleteBranch: $deleteBranch, forcing: forcing) {
                    Task { await model.remove(report, deleteBranch: deleteBranch, force: forcing) }
                }
            }
        }
    }

    private func content(_ report: WorktreeReport) -> some View {
        Form {
            Section {
                LabeledContent("Status") { VerdictBadge(verdict: report.verdict) }
                statusExplanation(report)
            } header: {
                header(report)
            }

            Section("Size") {
                if report.measured {
                    LabeledContent("Build artifacts") {
                        Text(Format.bytes(report.artifactBytes)).foregroundStyle(.green).monospacedDigit()
                    }
                    .help("Regenerable. A sweep frees this and an install command puts it back.")

                    LabeledContent("Everything else") {
                        Text(Format.bytes(report.uniqueBytes)).monospacedDigit()
                    }
                    .help("Only recoverable from the Trash.")
                } else {
                    LabeledContent("Measuring") { ProgressView().controlSize(.small) }
                }
            }

            pullRequestSection(report)

            Section("Details") {
                LabeledContent("Repository", value: report.worktree.repoName)
                LabeledContent("Branch", value: report.worktree.displayBranch)
                LabeledContent("Created by", value: report.worktree.harness.displayName)
                if !report.worktree.head.isEmpty {
                    LabeledContent("HEAD", value: String(report.worktree.head.prefix(10)))
                }
                LabeledContent("Location") {
                    Text(report.worktree.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                        .truncationMode(.middle)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: report.worktree.path)
                }
                .disabled(report.verdict == .prunable)
            }

            if !report.artifacts.isEmpty {
                Section("Build Artifacts") {
                    ForEach(report.artifacts.sorted { $0.bytes > $1.bytes }) { artifact in
                        LabeledContent(artifact.kind) {
                            Text(Format.compactBytes(artifact.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                actions(report)
            }
        }
        .formStyle(.grouped)
    }

    /// Pull request state for this branch, or a spinner while it is fetched.
    /// Extracted so `content` stays readable rather than one long builder.
    @ViewBuilder
    private func pullRequestSection(_ report: WorktreeReport) -> some View {
        if let pullRequest = report.pullRequest {
            Section("Pull Request") {
                LabeledContent {
                    Label(pullRequest.summary, systemImage: pullRequest.symbol)
                        .foregroundStyle(pullRequest.isSettled ? .secondary : .primary)
                } label: {
                    Text("Status")
                }
                Text(pullRequest.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if pullRequest.isSettled {
                    Label(
                        "This branch is finished, so anything uncommitted here is probably scratch work.",
                        systemImage: "lightbulb"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Link("Open on GitHub", destination: URL(string: pullRequest.url) ?? URL(fileURLWithPath: "/"))
                    .font(.caption)
            }
        } else if model.isCheckingPullRequests {
            Section("Pull Request") {
                LabeledContent("Status") {
                    ProgressView().controlSize(.small)
                }
            }
        }
    }

    private func header(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(report.worktree.name)
                .font(.headline)
                .textSelection(.enabled)
            Text(report.worktree.displayBranch)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func statusExplanation(_ report: WorktreeReport) -> some View {
        switch report.verdict {
        case .blocked(let blocker):
            VStack(alignment: .leading, spacing: 6) {
                Text(blocker.summary).font(.callout)
                Text(blocker.remedy).font(.caption).foregroundStyle(.secondary)
                if case .ignoredConfig(let files) = blocker {
                    ForEach(files, id: \.self) { file in
                        Label(file, systemImage: "doc.text.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)

        case .caution(let list):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(list, id: \.self) { caution in
                    Label(caution.summary, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .safe:
            Text("Clean, pushed, nothing running here, and no local-only config.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .prunable:
            Text("The directory is already gone. Pruning clears the leftover git metadata and touches nothing on disk.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .orphan:
            Text("The parent repository no longer exists, so nothing can reclaim this.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func actions(_ report: WorktreeReport) -> some View {
        if report.verdict.canSweep, report.artifactBytes > 0 {
            Button {
                Task { await model.sweep([report]) }
            } label: {
                Label("Sweep \(Format.compactBytes(report.artifactBytes))", systemImage: "scissors")
            }
            .disabled(model.isWorking)
        }

        if report.verdict == .prunable {
            Button {
                Task { await model.prune() }
            } label: {
                Label("Prune Metadata", systemImage: "clock.arrow.circlepath")
            }
            .disabled(model.isWorking)
        } else {
            Button(role: .destructive) {
                forcing = false
                confirmingRemoval = true
            } label: {
                Label("Remove Worktree…", systemImage: "trash")
            }
            .disabled(!report.verdict.canRemove || model.isWorking)

            if let blocker = report.verdict.blocker {
                overrideSection(report, blocker)
            }
        }
    }

    /// The escape hatch.
    ///
    /// Worktrees are scratch space, so refusing forever would make Coppice
    /// useless on exactly the ones the user most wants gone. Overridable
    /// blockers get a second, deliberately plainer button that states what is
    /// destroyed; absolute ones say why no button exists.
    @ViewBuilder
    private func overrideSection(_ report: WorktreeReport, _ blocker: Blocker) -> some View {
        if blocker.severity == .absolute {
            Label(blocker.remedy, systemImage: "hand.raised.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(blocker.remedy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if report.isLikelyDisposable {
                    Label("Its pull request is closed, so this is likely safe to discard.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(role: .destructive) {
                    forcing = true
                    confirmingRemoval = true
                } label: {
                    Label("Remove Anyway…", systemImage: "exclamationmark.triangle")
                }
                .disabled(model.isWorking)

                if let loss = blocker.lossIfForced {
                    Text("Discards work: \(loss).")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Typed confirmation for the one irreversible action.
///
/// The name has to be entered by hand. That is what makes bulk removal
/// impossible and forces the user to read what they actually picked.
struct RemoveSheet: View {
    let report: WorktreeReport
    @Binding var deleteBranch: Bool
    /// Overriding a blocker. The sheet changes tone and lists what is destroyed.
    var forcing = false
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @State private var typed = ""

    private var matches: Bool { typed == report.worktree.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: forcing ? "exclamationmark.triangle.fill" : "trash.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(forcing ? AnyShapeStyle(.orange) : AnyShapeStyle(.red))
                VStack(alignment: .leading, spacing: 4) {
                    Text(forcing
                         ? "Discard work and remove “\(report.worktree.name)”?"
                         : "Remove “\(report.worktree.name)”?")
                        .font(.headline)
                    Text(forcing
                         ? "Coppice would normally refuse this. Removing it destroys work that exists nowhere else."
                         : "The directory goes to the Trash, then git metadata is pruned. Anything gitignored inside has no copy in git.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20)

            Divider()

            Form {
                if forcing, let loss = report.verdict.blocker?.lossIfForced {
                    Section {
                        Label(loss, systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        if case .ignoredConfig(let files) = report.verdict.blocker {
                            ForEach(files, id: \.self) { file in
                                Text(file).font(.caption).monospaced().foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("What you are discarding")
                    }
                }

                if let pullRequest = report.pullRequest {
                    LabeledContent("Pull request") {
                        Label(pullRequest.summary, systemImage: pullRequest.symbol)
                            .foregroundStyle(pullRequest.state == .open ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    }
                }

                LabeledContent("Branch", value: report.worktree.displayBranch)
                LabeledContent("Repository", value: report.worktree.repoName)
                LabeledContent("Size", value: report.measured ? Format.bytes(report.totalBytes) : "Not measured")

                Toggle("Also delete the branch", isOn: $deleteBranch)
                    .disabled(report.worktree.branch == nil)
                    .help("Uses git branch -d, so git still refuses if the branch is unmerged.")

                if settings.rescueIgnoredConfig {
                    Label(
                        "Gitignored config is copied to \(settings.rescueDirectory.lastPathComponent) first.",
                        systemImage: "shield.lefthalf.filled"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TextField("Type “\(report.worktree.name)” to confirm", text: $typed)
                    .textFieldStyle(.roundedBorder)
            }
            // Scrolls, and is the only part of the sheet that does. The header
            // states what is about to happen and the footer holds the buttons,
            // so both must stay pinned: a confirmation whose Cancel button can
            // be scrolled out of reach is worse than no confirmation at all.
            //
            // The middle grew past the window once the forced-removal section
            // and pull request row were added, which is what made an earlier
            // `.scrollDisabled(true)` here a real bug rather than a tidy-up.
            .formStyle(.grouped)
            .frame(maxHeight: 420)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(forcing ? "Discard and Remove" : "Remove") {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(forcing ? .orange : .red)
                .disabled(!matches)
            }
            .padding(20)
        }
        .frame(width: 440)
    }
}
