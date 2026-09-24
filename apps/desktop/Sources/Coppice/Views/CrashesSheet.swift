import SwiftUI
import AppKit

struct CrashesSheet: View {
    let groups: [CrashGroup]
    let hangs: [Diagnostics.Problem]
    let environment: String

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var copied = false

    private var selected: CrashGroup? {
        groups.first { $0.id == selection } ?? groups.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            HStack(alignment: .firstTextBaseline) {
                Text("Crashes and hangs").font(.heading(20))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.quiet)
                    .keyboardShortcut(.cancelAction)
            }

            if groups.isEmpty && hangs.isEmpty {
                Text("Nothing recorded in the last 30 days.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: Space.xl) {
                    sidebar.frame(width: 230)
                    Divider().opacity(0.5)
                    if let selected {
                        detail(selected)
                    } else {
                        Text("No crash reports, only hangs.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .font(.ui)
        .padding(Space.xxl)
        .frame(width: 760, height: 580)
        .background(.black)
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    Button { selection = group.id } label: { groupRow(group) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(group.id == selected?.id ? .isSelected : [])
                }
                if !hangs.isEmpty {
                    SectionLabel("Hangs")
                        .padding(.top, Space.l)
                        .padding(.bottom, Space.xs)
                    ForEach(hangs.prefix(12), id: \.self) { hang in
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(hang.message.replacingOccurrences(of: "main thread blocked for ", with: ""))
                                .lineLimit(2)
                            Text(hang.date?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .font(.uiCaption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, Space.xs)
                    }
                }
            }
        }
    }

    private func groupRow(_ group: CrashGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            Text("\(group.reports.count)")
                .font(.display(22))
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(group.latest.kind).lineLimit(1)
                Text(group.latest.headline)
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(group.channels) · \(group.latest.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.s)
        .padding(.horizontal, Space.s)
        .background(.white.opacity(group.id == selected?.id ? 0.08 : 0), in: .rect(cornerRadius: 6))
        .contentShape(.rect)
    }

    private func detail(_ group: CrashGroup) -> some View {
        let crash = group.latest
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(crash.kind).font(.heading(17))
                    if let reason = crash.reason {
                        Text(reason)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(group.reports.count) time\(group.reports.count == 1 ? "" : "s") · \(group.channels) · version \(crash.version)")
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                }

                if !crash.before.isEmpty {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        SectionLabel("Right before")
                        ForEach(crash.before, id: \.self) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .font(.uiCaption.monospaced())
                                    .foregroundStyle(.tertiary)
                                Text(entry.text)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Space.xs) {
                    SectionLabel("Backtrace")
                    backtrace(crash)
                }

                HStack(spacing: Space.m) {
                    Button(copied ? "Copied" : "Copy report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(crash.summary + "\n\n" + environment, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.mono)
                    Button("Show crash file") { NSWorkspace.shared.activateFileViewerSelecting([crash.url]) }
                        .buttonStyle(.quiet)
                    Button("Report issue") {
                        if let url = DiagnosticsExport.issueURL(crash: crash, environment: environment) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.quiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: group.id) { copied = false }
    }

    private func backtrace(_ crash: CrashReport) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(crash.frames.prefix(24).enumerated()), id: \.offset) { index, frame in
                let bright = index == crash.likely || frame.isApp
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text("\(index)")
                        .frame(width: 18, alignment: .trailing)
                    Text(frame.library)
                        .frame(width: 84, alignment: .leading)
                        .lineLimit(1)
                    Text(frame.symbol)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .fontWeight(bright ? .semibold : .regular)
                }
                .foregroundStyle(bright ? .primary : .tertiary)
            }
        }
        .font(.uiCaption.monospaced())
        .textSelection(.enabled)
    }
}
