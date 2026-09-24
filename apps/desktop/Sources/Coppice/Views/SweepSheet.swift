import SwiftUI

struct SweepSheet: View {
    let targets: [WorktreeReport]
    let onConfirm: ([WorktreeReport]) -> Void

    @Environment(\.dismiss) private var dismiss

    private var totalBytes: Int64 { targets.reduce(0) { $0 + $1.artifactBytes } }
    private var shown: [WorktreeReport] { Array(targets.sorted { $0.artifactBytes > $1.artifactBytes }.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Sweep build output in \(targets.count) worktree\(targets.count == 1 ? "" : "s")?")
                    .font(.heading(20))
                    .lineLimit(2)
                Text("Source, git history and local config stay. An install command rebuilds everything this removes.")
                    .font(.uiCallout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Space.s) {
                ForEach(shown) { report in
                    HStack(alignment: .firstTextBaseline) {
                        Text(report.worktree.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Space.s)
                        Text(Format.compactBytes(report.artifactBytes))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                if targets.count > shown.count {
                    Text("and \(targets.count - shown.count) more")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: Space.m) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Sweep \(Format.compactBytes(totalBytes))") {
                    onConfirm(targets)
                    dismiss()
                }
                .buttonStyle(.mono)
                .keyboardShortcut(.defaultAction)
                .disabled(targets.isEmpty)
            }
        }
        .font(.ui)
        .padding(Space.xxl)
        .frame(width: 440)
        .background(.black)
    }
}
