import SwiftUI

/// The dropdown panel. Answers one question ("is there anything to reclaim?")
/// and offers the one safe action. Everything destructive lives in the window.
struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.line)

            if model.visibleReports.isEmpty {
                emptyState
            } else {
                summary
                Divider().overlay(Theme.line)
                actions
            }

            Divider().overlay(Theme.line)
            footer
        }
        .frame(width: 300)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "scissors")
                .foregroundStyle(Theme.safe)
            Text("Coppice")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if model.isScanning {
                Text("scanning")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.tertiary)
            } else if let last = model.lastScan {
                Text(last, style: .relative)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.isScanning ? "Looking for worktrees…" : "No worktrees found")
                .font(.system(size: 12))
            Text(model.isScanning
                 ? "This takes a moment on first run."
                 : "Nothing to clean. Add a scan root in Settings if that looks wrong.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.bytes(model.reclaimableBytes))
                    .font(Theme.mono(26, weight: .semibold))
                    .contentTransition(.numericText())
                Text("reclaimable")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            }

            HStack(spacing: 14) {
                metric("\(model.visibleReports.count)", "worktrees")
                metric("\(model.groups.count)", "repos")
                metric(Format.bytes(model.totalBytes), "on disk")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .animation(Theme.motion, value: model.reclaimableBytes)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(Theme.mono(11, weight: .medium))
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            if !model.sweepCandidates.isEmpty {
                MenuRow(
                    title: "Sweep build artifacts",
                    detail: "\(model.sweepCandidates.count) worktrees · \(Format.bytes(model.reclaimableBytes))",
                    symbol: "scissors",
                    tint: Theme.safe,
                    disabled: model.isWorking
                ) {
                    Task { await model.sweep(model.sweepCandidates) }
                }
            }
            if !model.prunableReports.isEmpty {
                MenuRow(
                    title: "Prune stale metadata",
                    detail: "\(model.prunableReports.count) worktrees git already considers dead",
                    symbol: "trash.slash",
                    tint: Theme.info,
                    disabled: model.isWorking
                ) {
                    Task { await model.prune() }
                }
            }
            MenuRow(
                title: "Open Coppice",
                detail: "Review every worktree and its verdict",
                symbol: "rectangle.stack",
                tint: Theme.primary,
                disabled: false
            ) {
                openMainWindow(openWindow)
            }
        }
        .padding(.vertical, 4)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Rescan") { model.rescan() }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
                .disabled(model.isScanning)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

/// A tappable row in the menu bar panel, with a hover state that does not repaint
/// continuously.
struct MenuRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(disabled ? Theme.tertiary : tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(disabled ? Theme.tertiary : Theme.primary)
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(hovering && !disabled ? Theme.elevated : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(Theme.fade, value: hovering)
    }
}
