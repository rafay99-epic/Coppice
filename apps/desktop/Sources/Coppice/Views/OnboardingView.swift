import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var step = 0

    private let stepCount = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(step + 1) of \(stepCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Group {
                switch step {
                case 0: found
                case 1: twoWays
                default: menuBar
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(step)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            controls
        }
        .padding(32)
        .frame(minWidth: 600, minHeight: 440)
        .background(.black)
        .animation(.smooth(duration: 0.3), value: step)
    }

    private var found: some View {
        HStack(alignment: .top, spacing: 24) {
            foundText
            GrowingStump(lineWidth: 1.6)
                .frame(height: 220)
        }
    }

    private var foundText: some View {
        VStack(alignment: .leading, spacing: 18) {
            title(
                model.isScanning && model.visibleReports.isEmpty
                    ? "Looking for worktrees…"
                    : "Your agents left \(model.visibleReports.count) worktrees behind."
            )

            HStack(spacing: 32) {
                stat(size(model.totalBytes), "on disk")
                stat(size(model.reclaimableBytes), "safe to free")
            }

            Text("\(agentNames) gets its own copy of your repo. Nothing deletes them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 10)
    }

    private var twoWays: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("Two ways to get space back.")
            way(
                "Sweep",
                symbol: "scissors",
                detail: "Deletes node_modules and build output. Your code stays. One install brings it back."
            )
            Divider()
            way(
                "Move to Trash",
                symbol: "trash",
                detail: "Removes a whole worktree. Commits stay on the branch, and the folder waits in the Trash."
            )
        }
        .padding(.top, 10)
    }

    private var menuBar: some View {
        VStack(alignment: .leading, spacing: 18) {
            title("It lives in your menu bar.")
            Text("Coppice only acts when you click. It never touches a worktree an agent is using right now, or your main checkout.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Watching", value: watching)
            Text("Change folders and agents any time in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
    }

    private var controls: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: 6, height: 6)
                }
            }
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Button(step == stepCount - 1 ? "Start" : "Continue") {
                if step == stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(.mono)
            .keyboardShortcut(.defaultAction)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .numeric(text)
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
                .numeric(value)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func way(_ name: String, symbol: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28)
                .symbolEffect(.bounce, options: .nonRepeating, value: step)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func size(_ bytes: Int64) -> String {
        bytes == 0 && (model.isScanning || model.isMeasuring) ? "…" : Format.compactBytes(bytes)
    }

    private var agentNames: String {
        let names = model.detectedHarnesses.map(\.displayName)
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
