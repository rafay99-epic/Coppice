import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var removing: WorktreeReport?

    var body: some View {
        Group {
            if let report = model.selectedReport {
                content(report)
            } else {
                VStack(spacing: Space.s) {
                    Text("Nothing selected")
                        .font(.heading(17))
                    Text("Pick a worktree to see what is inside.")
                        .font(.uiCallout)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(Space.xl)
            }
        }
        .font(.ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .sheet(item: $removing) { report in
            RemoveSheet(report: report) { deleteBranch in
                Task { await model.remove(report, deleteBranch: deleteBranch) }
            }
        }
    }

    private func content(_ report: WorktreeReport) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                header(report)
                sizes(report)
                pullRequestSection(report)
                details(report)
                artifacts(report)
                actions(report)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.smooth, value: report.verdict)
        .animation(.smooth, value: report.measured)
    }

    private func header(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(report.worktree.name)
                    .font(.heading(20))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(report.worktree.displayBranch)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            VerdictBadge(verdict: report.verdict)
            statusExplanation(report)
        }
    }

    @ViewBuilder
    private func sizes(_ report: WorktreeReport) -> some View {
        section("Size") {
            if report.measured {
                row("Build output", value: Format.bytes(report.artifactBytes))
                    .help("A sweep frees this. An install brings it back.")
                row("Everything else", value: Format.bytes(report.uniqueBytes))
                    .help("Only recoverable from the Trash.")
            } else {
                row("Measuring", value: "…")
            }
        }
    }

    @ViewBuilder
    private func pullRequestSection(_ report: WorktreeReport) -> some View {
        if let pullRequest = report.pullRequest {
            section("Pull request") {
                Label(pullRequest.summary, systemImage: pullRequest.symbol)
                    .foregroundStyle(pullRequest.isSettled ? .secondary : .primary)
                Text(pullRequest.title)
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if pullRequest.isSettled {
                    Text("This branch is finished, so leftover edits are likely scratch work.")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let url = URL(string: pullRequest.url) {
                    Link("Open on GitHub", destination: url)
                        .font(.uiCallout)
                        .foregroundStyle(.primary)
                }
            }
        } else if model.isCheckingPullRequests {
            section("Pull request") {
                Text("Checking…")
                    .font(.uiCallout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func details(_ report: WorktreeReport) -> some View {
        section("Details") {
            row("Repository", value: report.worktree.repoName)
            row("Created by", value: report.worktree.harness.displayName)
            if !report.worktree.head.isEmpty {
                row("HEAD", value: String(report.worktree.head.prefix(10)))
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Location")
                    .foregroundStyle(.secondary)
                Text((report.worktree.path as NSString).abbreviatingWithTildeInPath)
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: report.worktree.path)
            }
            .buttonStyle(.plain)
            .font(.uiCallout)
            .underline()
            .disabled(report.verdict == .prunable)
        }
    }

    @ViewBuilder
    private func artifacts(_ report: WorktreeReport) -> some View {
        if !report.artifacts.isEmpty {
            section("Build output") {
                ForEach(report.artifacts.sorted { $0.bytes > $1.bytes }) { artifact in
                    row(artifact.kind, value: Format.compactBytes(artifact.bytes))
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: Space.s) {
                content()
            }
        }
    }

    private func row(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: Space.s)
            Text(value)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
                .numeric(value)
        }
    }

    @ViewBuilder
    private func statusExplanation(_ report: WorktreeReport) -> some View {
        Group {
            switch report.verdict {
            case .blocked(let blocker) where blocker.severity == .absolute:
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(blocker.summary)
                    Text(blocker.remedy).font(.uiCaption).foregroundStyle(.tertiary)
                }

            case .blocked(let blocker):
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(blocker.summary)
                    Text("Moving it to the Trash keeps commits on the branch.")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                }

            case .caution(let list):
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(list, id: \.self) { caution in
                        Text(caution.summary)
                    }
                }

            case .safe:
                Text("Clean, pushed, and nothing is running here.")

            case .prunable:
                Text("The folder is already gone. Pruning clears the leftover git metadata.")

            case .orphan:
                Text("Its repository no longer exists.")
            }
        }
        .font(.uiCallout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func actions(_ report: WorktreeReport) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if report.verdict.canSweep, report.artifactBytes > 0 {
                Button {
                    Task { await model.sweep([report]) }
                } label: {
                    Label("Sweep \(Format.compactBytes(report.artifactBytes))", systemImage: "scissors")
                }
                .buttonStyle(.mono)
                .disabled(model.isWorking)
            }

            if report.verdict == .prunable {
                Button {
                    Task { await model.prune(only: report.worktree.repoPath) }
                } label: {
                    Label("Prune metadata", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.mono)
                .disabled(model.isWorking)
            } else if report.verdict.canRemove {
                Button {
                    removing = report
                } label: {
                    Label("Move to Trash…", systemImage: "trash")
                }
                .buttonStyle(.quiet)
                .disabled(model.isWorking)
            }
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
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Move \(report.worktree.name) to the Trash?")
                    .font(.heading(20))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("\(sizeText)You can restore it from the Trash.")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
            }

            goesWithIt

            VStack(alignment: .leading, spacing: Space.s) {
                if let pullRequest = report.pullRequest {
                    HStack {
                        Text("Pull request").foregroundStyle(.secondary)
                        Spacer()
                        Label(pullRequest.summary, systemImage: pullRequest.symbol)
                    }
                }
                HStack {
                    Text("Branch").foregroundStyle(.secondary)
                    Spacer()
                    Text(report.worktree.displayBranch)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Toggle("Delete branch too", isOn: $deleteBranch)
                    .toggleStyle(.switch)
                    .tint(.white)
                    .disabled(report.worktree.branch == nil)
                if deleteBranch, holdsCommits {
                    Text("Its commits are only on this branch. Git keeps the branch unless it is merged.")
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: Space.m) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    onConfirm(deleteBranch)
                    dismiss()
                }
                .buttonStyle(.mono)
                .disabled(blockers == nil)
            }
        }
        .font(.ui)
        .padding(Space.xxl)
        .frame(width: 440)
        .background(.black)
        .animation(.smooth, value: blockers)
        .animation(.smooth, value: deleteBranch)
        .task {
            blockers = await model.allBlockers(for: report)
        }
    }

    @ViewBuilder
    private var goesWithIt: some View {
        if blockers == nil {
            Text("Checking what is inside…")
                .font(.uiCallout)
                .foregroundStyle(.tertiary)
        } else if !notes.isEmpty || !ignoredFiles.isEmpty {
            VStack(alignment: .leading, spacing: Space.m) {
                SectionLabel("Goes with it")
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(notes, id: \.self) { note in
                        Text(note).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(ignoredFiles, id: \.self) { file in
                        HStack(alignment: .firstTextBaseline) {
                            Text(file).font(.uiCallout.monospaced())
                            Spacer(minLength: Space.s)
                            Text(settings.rescueIgnoredConfig ? "Copy saved to Coppice Rescue" : "Kept in the Trash")
                                .font(.uiCaption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
