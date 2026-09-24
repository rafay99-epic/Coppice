import SwiftUI

struct ActivityBar: View {
    let activity: Activity

    var body: some View {
        if activity.isBusy {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(activity.title)
                        .font(.uiCallout)
                    Spacer(minLength: Space.s)
                    if let freed = activity.freedSoFar {
                        Text("\(Format.bytes(freed)) freed")
                            .font(.uiCaption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .numeric(freed)
                    }
                }

                if let fraction = activity.fraction {
                    ProgressLine(value: fraction, height: 2)
                }

                if let detail = activity.detail {
                    Text(detail)
                        .font(.uiCaption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .animation(.smooth, value: activity)
        }
    }
}

struct BannerView: View {
    let banner: Banner
    let onDismiss: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Image(systemName: banner.kind.symbol)
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(banner.title)
                        .font(.ui.weight(.medium))
                    Text(banner.message)
                        .font(.uiCaption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Space.s)

                Group {
                    if banner.opensCrashes {
                        Button("View crash") { model.openCrashes() }
                    } else {
                        Button("Open log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                    }
                }
                .buttonStyle(.plain)
                .fixedSize()
                .font(.uiCaption)
                .foregroundStyle(.secondary)

                if !banner.details.isEmpty {
                    Button(showingDetails ? "Hide" : "Details") {
                        withAnimation(.smooth) { showingDetails.toggle() }
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .font(.uiCaption)
                    .foregroundStyle(.secondary)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.uiCaption)
                }
                .accessibilityLabel("Dismiss")
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Dismiss")
            }

            if showingDetails {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s) {
                        ForEach(banner.details) { item in
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(item.name).font(.uiCaption.weight(.medium))
                                Text(item.reason)
                                    .font(.uiCaption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .font(.ui)
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 8))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct StatusLine: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let parts = self.parts
        return HStack(spacing: Space.xs) {
            Text("\(Text(parts.lead).foregroundStyle(.primary).fontWeight(.medium))\(parts.rest)")
                .numeric(parts.lead + parts.rest)
            if !model.isWorking, let follow = model.receipt?.follow {
                Text("·")
                Button(follow.title) { follow.open() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .underline()
            }
        }
        .font(.uiCallout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var parts: (lead: String, rest: String) {
        if model.activity.isMutating {
            return (model.activity.title, model.activity.freedSoFar.map { " · \(Format.bytes($0)) freed" } ?? "")
        }
        if let receipt = model.receipt {
            return (receipt.headline, receipt.detail.map { " \($0)" } ?? "")
        }
        if model.isScanning, model.visibleReports.isEmpty { return ("", "Scanning…") }
        return ("", "\(model.visibleReports.count) worktrees · \(Format.bytes(model.totalBytes))")
    }
}

extension Receipt.Follow {
    var title: String {
        switch self {
        case .log: return "Show log"
        case .trash: return "Show in Trash"
        }
    }

    func open() {
        switch self {
        case .log: NSWorkspace.shared.open(Log.shared.logFileURL)
        case .trash(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
