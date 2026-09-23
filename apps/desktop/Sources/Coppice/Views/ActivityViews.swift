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
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.white)
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

                if !banner.details.isEmpty {
                    Button(showingDetails ? "Hide" : "Details") {
                        withAnimation(.smooth) { showingDetails.toggle() }
                    }
                    .buttonStyle(.plain)
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
