import SwiftUI
import AppKit

/// First run. Four screens, and every one either reports something measured from
/// this machine or asks a question that changes behaviour. None of them exist to
/// say hello.
///
/// This is a safety briefing rather than a feature tour, because Coppice is
/// allowed to delete things and the user has no reason to trust it yet.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @State private var step = 0
    @State private var selectedHarnesses: Set<Harness> = []
    @State private var roots: [URL] = []

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
            Divider().overlay(Theme.line)

            Group {
                switch step {
                case 0: welcome
                case 1: harnesses
                case 2: locations
                default: protections
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Divider().overlay(Theme.line)
            controls
        }
        .background(Theme.background)
        .animation(Theme.motion, value: step)
        .task {
            selectedHarnesses = Set(model.detectedHarnesses)
            roots = settings.codeRoots
            model.start()
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            Image(systemName: "scissors").foregroundStyle(Theme.safe)
            Text("Coppice").font(.system(size: 13, weight: .semibold))
            Spacer()
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.primary : Theme.line)
                    .frame(width: index == step ? 20 : 7, height: 3)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .animation(Theme.motion, value: step)
    }

    // MARK: Step 1

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("You have \(model.visibleReports.count) worktrees using \(Format.bytes(model.totalBytes)).",
                    "Measured on this machine just now, not an example.")

            HStack(spacing: 1) {
                StatTile(value: "\(model.visibleReports.count)", label: "worktrees found")
                StatTile(value: "\(model.groups.count)", label: "repositories")
                StatTile(value: Format.bytes(model.reclaimableBytes), label: "in build artifacts", tint: Theme.safe)
            }
            .background(Theme.line)
            .clipShape(RoundedRectangle(cornerRadius: 7))

            Text("""
            Agents create a worktree per task and rarely clean up. The space is mostly \
            dependency folders, which rebuild from a single install command, so most of \
            it can go back without touching a line of your work.
            """)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if model.isScanning {
                Text("Still scanning, so these numbers are still climbing.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: Step 2

    private var harnesses: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Detected \(model.detectedHarnesses.count) coding agents.",
                    "Found by checking which tool directories exist in your home folder.")

            VStack(spacing: 0) {
                ForEach(model.detectedHarnesses, id: \.self) { harness in
                    harnessRow(harness)
                }
                if model.detectedHarnesses.isEmpty {
                    Text("No agent directories found. Coppice will still find worktrees you made by hand.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondary)
                        .padding(14)
                }
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))

            Text("Unchecked agents are hidden everywhere in the app, including the totals.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiary)
        }
    }

    private func harnessRow(_ harness: Harness) -> some View {
        let count = model.reports.filter { $0.worktree.harness == harness }.count
        return HStack(spacing: 11) {
            Image(systemName: harness.symbol)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(harness.displayName).font(.system(size: 12, weight: .medium))
                Text("\(count) worktree\(count == 1 ? "" : "s")")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { selectedHarnesses.contains(harness) },
                set: { isOn in
                    if isOn { selectedHarnesses.insert(harness) } else { selectedHarnesses.remove(harness) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .hairline()
    }

    // MARK: Step 3

    private var locations: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("Where should Coppice look?",
                    "Agent worktree directories are always included. These are your own code folders.")

            VStack(spacing: 0) {
                ForEach(roots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.tertiary)
                        Text(root.path)
                            .font(Theme.mono(11))
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button {
                            roots.removeAll { $0 == root }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .hairline()
                }
                HStack {
                    Button("Add folder…") { chooseFolder() }
                        .buttonStyle(SecondaryButton())
                    Spacer()
                }
                .padding(11)
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 7) {
                Text("Full Disk Access")
                    .font(.system(size: 12, weight: .medium))
                Text("""
                Without it macOS hides parts of your home folder, so Coppice under-reports \
                sizes and can miss worktrees. It never needs admin rights, and it never \
                reads file contents, only names and sizes.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
                    if let url { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(SecondaryButton())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !roots.contains(url) { roots.append(url) }
    }

    // MARK: Step 4

    private var protections: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("What Coppice will never delete.",
                    "Every rule is checked again at the moment of deletion, not just when the list was built.")

            VStack(alignment: .leading, spacing: 0) {
                rule("Anything with a process running in it", "An open session, editor or dev server blocks both sweep and remove.")
                rule("Uncommitted or untracked changes", "Modified files, staged files and new files all block removal.")
                rule("Commits that exist nowhere else", "Unpushed work, or commits missing from the default branch.")
                rule("Gitignored config such as .env.local", "Git reports these worktrees as clean, so this is the rule that matters most.")
                rule("The repository's own working copy", "The main worktree is never removable, under any setting.")
            }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1))

            let blocked = model.reports.filter { !$0.verdict.canRemove }.count
            Label(
                """
                Dry run on your machine: \(model.reports.count) worktrees checked, \
                \(blocked) protected, \(Format.bytes(model.reclaimableBytes)) safe to sweep. \
                Nothing has been deleted.
                """,
                systemImage: "checkmark.shield"
            )
            .font(.system(size: 11))
            .foregroundStyle(Theme.safe)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.safe.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundStyle(Theme.blocked)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .hairline()
    }

    // MARK: Chrome

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(SecondaryButton())
            }
            Spacer()
            Button(step == stepCount - 1 ? "Start using Coppice" : "Continue") {
                if step == stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(PrimaryButton())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func finish() {
        // `.manual` is never detected — it has no directory to find — so it has
        // to be added explicitly. Without it, every worktree made by hand and
        // every ordinary repository's own working copy disappears from the list.
        settings.enabledHarnesses = selectedHarnesses.union([.manual])
        settings.codeRoots = roots
        settings.hasCompletedOnboarding = true
        model.settingsChanged()
    }
}
