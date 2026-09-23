import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var confirmingRemoval = false

    var body: some View {
        Group {
            if let report = model.selectedReport {
                content(report)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "sidebar.trailing",
                    description: Text("Select a worktree to see what is in it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .sheet(isPresented: $confirmingRemoval) {
            if let report = model.selectedReport {
                RemoveSheet(report: report) { deleteBranch in
                    Task { await model.remove(report, deleteBranch: deleteBranch) }
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
                        Text(Format.bytes(report.artifactBytes)).monospacedDigit().numeric(report.artifactBytes)
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
        .scrollContentBackground(.hidden)
        .background(.black)
        .animation(.smooth, value: report.verdict)
        .animation(.smooth, value: report.measured)
    }

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
        case .blocked(let blocker) where blocker.severity == .absolute:
            VStack(alignment: .leading, spacing: 4) {
                Text(blocker.summary).font(.callout)
                Text(blocker.remedy).font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .blocked(let blocker):
            VStack(alignment: .leading, spacing: 4) {
                Text(blocker.summary).font(.callout)
                Text("Removing moves it to the Trash. Commits stay on the branch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text("Clean, pushed, and nothing is running here.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .prunable:
            Text("The folder is already gone. Pruning clears the leftover git metadata.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        case .orphan:
            Text("Its repository no longer exists.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        } else if report.verdict.canRemove {
            Button(role: .destructive) {
                confirmingRemoval = true
            } label: {
                Label("Move to Trash…", systemImage: "trash")
            }
            .disabled(model.isWorking)
        }
    }
}

struct RemoveSheet: View {
    let report: WorktreeReport
    let onConfirm: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var deleteBranch = false
    @State private var blockers: [Blocker]?

    private var notes: [String] { (blockers ?? []).compactMap(\.removalNote) }
    private var ignoredFiles: [String] {
        (blockers ?? []).flatMap { blocker -> [String] in
            if case .ignoredConfig(let files) = blocker { return files }
            return []
        }
    }
    private var holdsCommits: Bool { (blockers ?? []).contains(where: \.holdsCommits) }
    private var sizeText: String {
        report.measured ? "\(Format.bytes(report.totalBytes)). " : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Move \(report.worktree.name) to the Trash?")
                    .font(.headline)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(sizeText)You can restore it from the Trash.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            Form {
                if blockers == nil {
                    LabeledContent("Checking what is inside") { ProgressView().controlSize(.small) }
                } else if !notes.isEmpty || !ignoredFiles.isEmpty {
                    Section("Goes with it") {
                        ForEach(notes, id: \.self) { note in
                            Text(note).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(ignoredFiles, id: \.self) { file in
                            LabeledContent {
                                Text(settings.rescueIgnoredConfig ? "copy saved to Coppice Rescue" : "kept in the Trash")
                                    .foregroundStyle(.secondary)
                            } label: {
                                Text(file).monospaced()
                            }
                        }
                    }
                }

                Section {
                    if let pullRequest = report.pullRequest {
                        LabeledContent("Pull request") {
                            Label(pullRequest.summary, systemImage: pullRequest.symbol)
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Branch", value: report.worktree.displayBranch)
                    Toggle("Delete branch too", isOn: $deleteBranch)
                        .disabled(report.worktree.branch == nil)
                    if deleteBranch, holdsCommits {
                        Text("Its commits are only on this branch. Git keeps the branch unless it is merged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: 360)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    onConfirm(deleteBranch)
                    dismiss()
                }
                .buttonStyle(.mono)
                .disabled(blockers == nil)
            }
            .padding(20)
        }
        .frame(width: 420)
        .task {
            blockers = await model.allBlockers(for: report)
        }
    }
}
