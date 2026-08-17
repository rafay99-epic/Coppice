import SwiftUI
import AppKit

/// Standard macOS settings: a tabbed window of grouped forms, sized to its
/// content, using system controls throughout.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ScanningSettings()
                .tabItem { Label("Scanning", systemImage: "folder") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 430)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        Form {
            Section {
                Toggle("Show reclaimable space in the menu bar", isOn: $settings.showSizeInMenuBar)
                LabeledContent("Show once it passes") {
                    HStack {
                        Slider(value: $settings.notifyThresholdGB, in: 1...50, step: 1)
                        Text("\(Int(settings.notifyThresholdGB)) GB")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!settings.showSizeInMenuBar)
            } header: {
                Text("Menu Bar")
            }

            Section {
                Toggle("Rescue gitignored config before removing", isOn: $settings.rescueIgnoredConfig)
                Button("Open Rescue Folder") {
                    try? FileManager.default.createDirectory(
                        at: settings.rescueDirectory,
                        withIntermediateDirectories: true
                    )
                    NSWorkspace.shared.open(settings.rescueDirectory)
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("""
                Copies files like .env.local into \(settings.rescueDirectory.lastPathComponent) first. \
                Git has no copy of these, so this is the only backup they get.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.autoUpdateCheck)
                LabeledContent("Status") {
                    HStack(spacing: 8) {
                        Text(updater.statusText).foregroundStyle(.secondary)
                        Button("Check Now") { Task { await updater.checkNow() } }
                            .controlSize(.small)
                            .disabled(updater.isBusy || !Channel.current.updatesEnabled)
                    }
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScanningSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(settings.codeRoots, id: \.self) { root in
                    HStack {
                        Label(root.lastPathComponent, systemImage: "folder")
                        Spacer()
                        Button {
                            settings.codeRoots = settings.codeRoots.filter { $0 != root }
                            model.settingsChanged()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Button("Add Folder…") { addRoot() }
            } header: {
                Text("Code Folders")
            } footer: {
                Text("Agent worktree directories are always scanned and cannot be removed from this list.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Harness.allCases, id: \.self) { harness in
                    Toggle(isOn: harnessBinding(harness)) {
                        Label(harness.displayName, systemImage: harness.symbol)
                    }
                }
            } header: {
                Text("Show Worktrees From")
            }

            Section {
                Toggle("Check pull request status", isOn: $settings.checkPullRequests)
                    .disabled(!model.canCheckPullRequests)
                if !model.canCheckPullRequests {
                    Text("""
                    Requires the GitHub CLI (gh). Without it Coppice still works, \
                    it just cannot tell whether a branch is finished.
                    """)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Check Now") { model.fetchPullRequests() }
                    .disabled(!model.canCheckPullRequests || model.isCheckingPullRequests)
            } header: {
                Text("Pull Requests")
            } footer: {
                Text("""
                A merged or closed pull request means a branch is finished, which is how \
                Coppice knows leftover edits in that worktree are probably scratch work \
                rather than something to protect.
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Recent session window") {
                    HStack {
                        Slider(value: $settings.recentSessionHours, in: 1...168, step: 1)
                        Text("\(Int(settings.recentSessionHours))h")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Button("Rescan Now") { model.settingsChanged() }
            }
        }
        .formStyle(.grouped)
    }

    private func harnessBinding(_ harness: Harness) -> Binding<Bool> {
        Binding(
            get: { settings.enabledHarnesses.contains(harness) },
            set: { isOn in
                var current = settings.enabledHarnesses
                if isOn { current.insert(harness) } else { current.remove(harness) }
                settings.enabledHarnesses = current
            }
        )
    }

    private func addRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var current = settings.codeRoots
        for url in panel.urls where !current.contains(url) { current.append(url) }
        settings.codeRoots = current
        model.settingsChanged()
    }
}

private struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)

            VStack(spacing: 3) {
                Text(Channel.current.displayName).font(.title3).fontWeight(.semibold)
                Text("Version \(Updater.currentVersion)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("""
            Cuts agent worktrees back so they grow again. Sweeping removes build output that \
            any install command rebuilds. Removing is gated behind eleven checks, all re-run \
            at the moment of deletion.
            """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            HStack {
                Button("Activity Log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                Button("Source Code") {
                    if let url = URL(string: "https://github.com/\(Updater.repository)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            Spacer()

            Text("GPL-3.0 · Syntax Lab Technology")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
