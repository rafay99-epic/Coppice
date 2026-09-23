import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(.horizontal, Space.xl)
                .padding(.top, Space.xl)
                .padding(.bottom, Space.l)

            if case .available(let release) = updater.status {
                updateCallout(release)
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.m)
            }

            if let banner = model.banner {
                BannerView(banner: banner) { model.banner = nil }
                    .padding(.horizontal, Space.l)
                    .padding(.bottom, Space.m)
            }

            Divider().opacity(0.5)

            Group {
                if model.visibleReports.isEmpty {
                    emptyState
                } else {
                    breakdown
                }
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)

            Divider().opacity(0.5)

            footer
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
        }
        .font(.ui)
        .frame(width: 300)
        .background(.black)
        .animation(.smooth, value: model.banner)
        .animation(.smooth, value: model.activity.isMutating)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(heroLabel)
            Text(heroValue)
                .font(.display(40))
                .foregroundStyle(model.reclaimableBytes > 0 ? .primary : .secondary)
                .numeric(heroValue)
            Text(subtitle)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
                .numeric(subtitle)
            if model.activity.isMutating {
                ActivityBar(activity: model.activity)
                    .padding(.top, Space.s)
            }
        }
    }

    private var heroLabel: String {
        model.isScanning && model.visibleReports.isEmpty ? "Scanning" : "Reclaimable"
    }

    private var heroValue: String {
        if model.isScanning, model.visibleReports.isEmpty { return "…" }
        return Format.compactBytes(model.reclaimableBytes)
    }

    private var subtitle: String {
        if model.visibleReports.isEmpty { return "No worktrees found yet" }
        let repos = model.groups.count
        return "\(model.visibleReports.count) worktrees in \(repos) repo\(repos == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        Text(model.isScanning
             ? "Reading git metadata in your folders."
             : "Nothing found. Add a folder in Settings.")
            .font(.uiCallout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var breakdown: some View {
        VStack(spacing: Space.m) {
            row("Safe to sweep", detail: "\(model.sweepCandidates.count) worktrees", value: Format.compactBytes(model.reclaimableBytes))
            row("Has work", detail: "Uncommitted or unpushed", value: "\(model.hasWorkCount)")
            let stale = model.visibleReports.filter { Scope.stale.contains($0) }.count
            if stale > 0 {
                row("Stale", detail: "Folder gone or repo missing", value: "\(stale)")
            }
        }
    }

    private func row(_ title: String, detail: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title)
                Text(detail).font(.uiCaption).foregroundStyle(.tertiary)
            }
            Spacer(minLength: Space.s)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .numeric(value)
        }
    }

    private func updateCallout(_ release: Updater.Release) -> some View {
        HStack(spacing: Space.m) {
            Text("Version \(release.version) is ready")
                .font(.uiCallout)
            Spacer(minLength: Space.s)
            Button("Update") { Task { await updater.installUpdate() } }
                .buttonStyle(.mono)
                .disabled(updater.isBusy)
        }
        .padding(Space.m)
        .background(.white.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Button {
                    Task { await model.sweep(model.sweepCandidates) }
                } label: {
                    Label("Sweep", systemImage: "scissors")
                }
                .buttonStyle(.mono)
                .disabled(model.sweepCandidates.isEmpty || model.isWorking)

                Button("Open Coppice") { openMainWindow(openWindow) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Menu {
                    Button("Rescan") { model.rescan() }
                        .disabled(model.isScanning)
                    Button("Prune \(model.prunableReports.count) stale") { Task { await model.prune() } }
                        .disabled(model.prunableReports.isEmpty || model.isWorking)
                    Divider()
                    SettingsLink { Text("Settings…") }
                    Button("Activity log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                    Divider()
                    Button("Quit Coppice") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("More")
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }

            if let last = model.lastScan {
                Text("Checked at \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.uiCaption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
