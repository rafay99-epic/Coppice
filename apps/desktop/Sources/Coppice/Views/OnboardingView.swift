import SwiftUI
import AppKit

/// First run. Four screens, each of which either reports something measured from
/// this machine or asks a question that changes behaviour. None exist to say hello.
///
/// A safety briefing rather than a feature tour, because Coppice can delete
/// things and the user has no reason to trust it yet.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var step = 0
    @State private var selectedHarnesses: Set<Harness> = []
    @State private var roots: [URL] = []

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()
            controls
                .padding(16)
        }
        .frame(minWidth: 620, minHeight: 520)
        .task {
            selectedHarnesses = Set(model.detectedHarnesses)
            roots = settings.codeRoots
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: harnesses
        case 2: locations
        default: protections
        }
    }

    // MARK: Step 1

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero(
                    symbol: "scissors",
                    title: model.visibleReports.isEmpty
                        ? "Looking for worktrees…"
                        : "You have \(model.visibleReports.count) worktrees using \(Format.bytes(model.totalBytes)).",
                    subtitle: "Measured on this machine just now, not an example."
                )

                GroupBox {
                    HStack(spacing: 0) {
                        stat("\(model.visibleReports.count)", "Worktrees")
                        Divider().frame(height: 34)
                        stat("\(model.groups.count)", "Repositories")
                        Divider().frame(height: 34)
                        stat(Format.compactBytes(model.reclaimableBytes), "Reclaimable", tint: .green)
                    }
                    .frame(maxWidth: .infinity)
                }

                Text("""
                Coding agents create a worktree per task and rarely clean up. Most of the \
                space is dependency folders, which rebuild from a single install command, so \
                most of it can go back without touching a line of your work.
                """)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if model.isScanning {
                    Label(
                        "Still scanning, so these numbers are still climbing.",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }

    private func stat(_ value: String, _ label: String, tint: Color = .primary) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2).fontWeight(.semibold).foregroundStyle(tint).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Step 2

    private var harnesses: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(
                symbol: "wand.and.sparkles",
                title: "Found \(model.detectedHarnesses.count) coding agents.",
                subtitle: "Detected by checking which tool directories exist in your home folder."
            )
            .padding(24)

            Form {
                Section {
                    if model.detectedHarnesses.isEmpty {
                        Text("No agent directories found. Coppice will still find worktrees you made by hand.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.detectedHarnesses, id: \.self) { harness in
                        Toggle(isOn: binding(for: harness)) {
                            Label {
                                let count = model.reports.filter { $0.worktree.harness == harness }.count
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(harness.displayName)
                                    Text("\(count) worktree\(count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: harness.symbol)
                            }
                        }
                    }
                } footer: {
                    Text("""
                    Unchecked agents are hidden everywhere in the app, including the totals. \
                    Worktrees you made by hand are always shown.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func binding(for harness: Harness) -> Binding<Bool> {
        Binding(
            get: { selectedHarnesses.contains(harness) },
            set: { isOn in
                if isOn { selectedHarnesses.insert(harness) } else { selectedHarnesses.remove(harness) }
            }
        )
    }

    // MARK: Step 3

    private var locations: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(
                symbol: "folder",
                title: "Where should Coppice look?",
                subtitle: "Agent worktree directories are always included. These are your own code folders."
            )
            .padding(24)

            Form {
                Section {
                    ForEach(roots, id: \.self) { root in
                        HStack {
                            Label(root.lastPathComponent, systemImage: "folder")
                            Spacer()
                            Text(root.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                            Button {
                                roots.removeAll { $0 == root }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                    Button("Add Folder…") { chooseFolder() }
                } header: {
                    Text("Code Folders")
                }

                Section {
                    Text("""
                    Without Full Disk Access macOS hides parts of your home folder, so Coppice \
                    under-reports sizes and can miss worktrees. It never needs admin rights, and \
                    it only reads names and sizes, never file contents.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button("Open Privacy Settings…") {
                        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
                        if let url = URL(string: path) { NSWorkspace.shared.open(url) }
                    }
                } header: {
                    Text("Full Disk Access")
                }
            }
            .formStyle(.grouped)
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
        VStack(alignment: .leading, spacing: 0) {
            hero(
                symbol: "lock.shield",
                title: "What Coppice will never delete.",
                subtitle: "Every rule is checked again at the moment of deletion, not just when the list was built."
            )
            .padding(24)

            Form {
                Section {
                    rule(
                        "Anything with a process running in it",
                        "An open session, editor or dev server blocks both sweep and remove."
                    )
                    rule(
                        "Uncommitted or untracked changes",
                        "Modified files, staged files and new files all block removal."
                    )
                    rule(
                        "Commits that exist nowhere else",
                        "Unpushed work, or commits missing from the default branch."
                    )
                    rule(
                        "Gitignored config such as .env.local",
                        "Git reports these worktrees as clean, so this is the rule that matters most."
                    )
                    rule(
                        "The repository's own working copy",
                        "The main worktree is never removable, under any setting."
                    )
                }

                Section {
                    Label {
                        Text("""
                        Dry run: \(model.visibleReports.count) worktrees checked, \
                        \(model.protectedCount) protected, \
                        \(Format.bytes(model.reclaimableBytes)) safe to sweep. Nothing has been deleted.
                        """)
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                    }
                    .font(.callout)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func rule(_ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lock.fill").foregroundStyle(.red)
        }
    }

    // MARK: Chrome

    private func hero(symbol: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var controls: some View {
        HStack {
            ForEach(0..<stepCount, id: \.self) { index in
                Circle()
                    .fill(index == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 6, height: 6)
            }

            Spacer()

            if step > 0 {
                Button("Back") { step -= 1 }
            }
            Button(step == stepCount - 1 ? "Start Using Coppice" : "Continue") {
                if step == stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
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
