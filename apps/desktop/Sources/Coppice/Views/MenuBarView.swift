import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(12)

            if case .available(let release) = updater.status {
                Divider()
                updateCallout(release)
            }

            if let banner = model.banner {
                Divider()
                BannerView(banner: banner) { model.banner = nil }
            }

            Divider()

            if model.visibleReports.isEmpty {
                emptyState
            } else {
                breakdown
            }

            Divider()
            footer
                .padding(12)
        }
        .frame(width: 300)
        .background(.black)
        .animation(.smooth, value: model.banner)
        .animation(.smooth, value: model.activity.isMutating)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .font(.system(size: 17))
                    .foregroundStyle(model.reclaimableBytes > 0 ? .primary : .secondary)
                    .symbolEffect(.bounce, value: model.lastScan)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline).numeric(headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).numeric(subtitle)
                }
                Spacer()
            }
            if model.activity.isMutating {
                ActivityBar(activity: model.activity)
            }
        }
    }

    private var headline: String {
        if model.isScanning, model.visibleReports.isEmpty { return "Scanning…" }
        if model.reclaimableBytes == 0 { return "Nothing to reclaim" }
        return "\(Format.bytes(model.reclaimableBytes)) reclaimable"
    }

    private var subtitle: String {
        if model.visibleReports.isEmpty { return "No worktrees found yet" }
        let repos = model.groups.count
        return "\(model.visibleReports.count) worktrees in \(repos) repo\(repos == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        Text(model.isScanning
             ? "Reading git metadata across your scan folders."
             : "Nothing found. Add a folder in Settings if that looks wrong.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
    }

    private var breakdown: some View {
        VStack(spacing: 0) {
            row(
                title: "Safe to sweep",
                detail: "\(model.sweepCandidates.count) worktrees",
                value: Format.compactBytes(model.reclaimableBytes),
                symbol: "scissors",
                tint: .primary
            )
            row(
                title: "Has work",
                detail: "Uncommitted or unpushed changes",
                value: "\(model.hasWorkCount)",
                symbol: "pencil.circle.fill",
                tint: .secondary
            )
            if !model.prunableReports.isEmpty {
                row(
                    title: "Stale metadata",
                    detail: "Directories already gone",
                    value: "\(model.prunableReports.count)",
                    symbol: "clock.arrow.circlepath",
                    tint: .secondary
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func row(
        title: String,
        detail: String,
        value: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(value).font(.callout).monospacedDigit().foregroundStyle(.secondary).numeric(value)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private func updateCallout(_ release: Updater.Release) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.primary)
            Text("Version \(release.version) available").font(.callout)
            Spacer()
            Button("Update") { Task { await updater.installUpdate() } }
                .controlSize(.small)
                .disabled(updater.isBusy)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    Task { await model.sweep(model.sweepCandidates) }
                } label: {
                    Label("Sweep", systemImage: "scissors")
                }
                .buttonStyle(.mono)
                .disabled(model.sweepCandidates.isEmpty || model.isWorking)

                Button("Open Coppice") { openMainWindow(openWindow) }

                Spacer()

                Menu {
                    Button("Rescan") { model.rescan() }
                        .disabled(model.isScanning)
                    Button("Prune \(model.prunableReports.count) Stale") { Task { await model.prune() } }
                        .disabled(model.prunableReports.isEmpty || model.isWorking)
                    Divider()
                    SettingsLink { Text("Settings…") }
                    Button("Activity Log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                    Divider()
                    Button("Quit Coppice") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if let last = model.lastScan {
                Text("Last checked \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
