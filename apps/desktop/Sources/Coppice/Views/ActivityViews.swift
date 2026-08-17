import SwiftUI

/// Live progress for whatever is running.
///
/// Determinate wherever a count exists, because "Sweeping 4 of 17 · t3code-a1b2"
/// tells the user how long is left and that nothing has hung. An indeterminate
/// spinner is used only where the work really is one indivisible step.
struct ActivityBar: View {
    let activity: Activity

    var body: some View {
        if activity.isBusy {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(activity.title)
                        .font(.callout)
                    Spacer()
                    if let freed = activity.freedSoFar {
                        Text("\(Format.bytes(freed)) freed")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }

                if let fraction = activity.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }

                if let detail = activity.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .animation(.default, value: activity)
        }
    }
}

/// The result of the last operation: what happened, and what did not.
///
/// Failures are never swallowed into a cheerful "Done". A partial sweep that hit
/// three permission errors says so, and lists them, because the user needs to
/// know which paths still hold space.
struct BannerView: View {
    let banner: Banner
    let onDismiss: () -> Void

    @State private var showingDetails = false

    private var tint: Color {
        switch banner.kind {
        case .success: return .green
        case .warning: return .orange
        case .failure: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: banner.kind.symbol)
                    .foregroundStyle(tint)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(banner.title)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text(banner.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if !banner.details.isEmpty {
                    Button(showingDetails ? "Hide" : "Details") {
                        withAnimation { showingDetails.toggle() }
                    }
                    .controlSize(.small)
                }

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Dismiss")
            }

            if showingDetails {
                // A sweep over fifty worktrees can fail on plenty of them, so
                // this list has no useful upper bound. Cap the height and let it
                // scroll rather than pushing the rest of the window off screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(banner.details) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.caption).fontWeight(.medium)
                                Text(item.reason)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 28)
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10))
        .overlay(alignment: .leading) {
            Rectangle().fill(tint).frame(width: 3)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
