import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var step = 0

    private let stepCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch step {
                case 0: found
                case 1: twoWays
                default: menuBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            controls
        }
        .font(.ui)
        .padding(.horizontal, Space.xxxl)
        .padding(.top, Space.xxxl)
        .padding(.bottom, Space.xl)
        .frame(minWidth: 680, minHeight: 500)
        .background(.black)
        .tint(.white)
        .animation(.smooth(duration: 0.35), value: step)
    }

    private var found: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            VStack(alignment: .leading, spacing: Space.xl) {
                if model.isScanning && model.visibleReports.isEmpty {
                    title("Looking for", "worktrees…")
                } else {
                    title("Your agents left \(model.visibleReports.count) worktrees", "behind.")
                }

                HStack(alignment: .firstTextBaseline, spacing: Space.xxl) {
                    stat(size(model.totalBytes), "on disk")
                    stat(size(model.reclaimableBytes), "safe to free")
                }

                Text("\(agentNames) gets its own copy of your repo. Nothing deletes them.")
                    .font(.uiLarge)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360, alignment: .leading)

            Spacer(minLength: 0)

            GrowingStump(lineWidth: 1.4)
                .frame(height: 250)
        }
    }

    private var twoWays: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            title("Two ways to", "get space back.")
            VStack(alignment: .leading, spacing: Space.xl) {
                way(
                    "Sweep",
                    symbol: "scissors",
                    detail: "Deletes node_modules and build output. Your code stays, and one install brings it back."
                )
                way(
                    "Move to Trash",
                    symbol: "trash",
                    detail: "Removes a whole worktree. Commits stay on the branch, and the folder waits in the Trash."
                )
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    private var menuBar: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            title("It lives in", "your menu bar.")
            Text("Coppice only acts when you click. It never touches a worktree an agent is using, or your main checkout.")
                .font(.uiLarge)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460, alignment: .leading)
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("Watching")
                Text(watching)
                    .font(.ui)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.s)
            Text("Change folders and agents in Settings.")
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
        }
    }

    private var controls: some View {
        HStack(spacing: Space.l) {
            HStack(spacing: Space.s) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.snappy, value: step)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .foregroundStyle(.secondary)
            }
            Button(step == stepCount - 1 ? "Start using Coppice" : "Continue") {
                if step == stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(.mono)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func title(_ plain: String, _ emphasis: String) -> some View {
        (Text(plain + " ") + Text(emphasis).font(.display(40, italic: true)))
            .font(.display(40))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .numeric(plain)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(value)
                .font(.display(32))
                .monospacedDigit()
                .numeric(value)
            Text(label)
                .font(.uiCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func way(_ name: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.l) {
            Image(systemName: symbol)
                .font(.uiLarge)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .symbolEffect(.bounce, options: .nonRepeating, value: step)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(name).font(.heading(20))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func size(_ bytes: Int64) -> String {
        bytes == 0 && (model.isScanning || model.isMeasuring) ? "…" : Format.compactBytes(bytes)
    }

    private var agentNames: String {
        let names = model.presentHarnesses.filter { $0 != .manual }.map(\.displayName)
        return names.isEmpty ? "Every agent task" : "Every task in \(names.formatted(.list(type: .and)))"
    }

    private var watching: String {
        let folders = settings.codeRoots.map { ($0.path as NSString).abbreviatingWithTildeInPath }
        let agents = model.detectedHarnesses.count
        return (folders + ["\(agents) agent\(agents == 1 ? "" : "s")"]).joined(separator: ", ")
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        model.settingsChanged()
    }
}
