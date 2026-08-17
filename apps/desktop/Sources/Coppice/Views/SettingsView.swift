import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gear") }
            scanning.tabItem { Label("Scanning", systemImage: "folder") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 400)
        .background(Theme.background)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Show reclaimable space in the menu bar", isOn: $settings.showSizeInMenuBar)
                HStack {
                    Text("Show once it passes")
                    Slider(value: $settings.notifyThresholdGB, in: 1...50, step: 1)
                    Text("\(Int(settings.notifyThresholdGB)) GB")
                        .font(Theme.mono(11))
                        .frame(width: 46, alignment: .trailing)
                }
                .disabled(!settings.showSizeInMenuBar)
            } header: {
                Text("Menu bar")
            }

            Section {
                Toggle("Rescue gitignored config before removing", isOn: $settings.rescueIgnoredConfig)
                Text("""
                Copies files like .env.local into \(settings.rescueDirectory.path) first. \
                Git has no copy of these, so this is the only backup they get.
                """)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                Button("Open rescue folder") {
                    try? FileManager.default.createDirectory(at: settings.rescueDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(settings.rescueDirectory)
                }
            } header: {
                Text("Safety")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.autoUpdateCheck)
                HStack {
                    Button("Check now") { Task { await updater.checkNow() } }
                        .disabled(updater.isBusy)
                    Text(updater.statusText)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondary)
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
    }

    private var scanning: some View {
        Form {
            Section {
                ForEach(settings.codeRoots, id: \.self) { root in
                    HStack {
                        Text(root.path).font(Theme.mono(10)).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button {
                            settings.codeRoots = settings.codeRoots.filter { $0 != root }
                            model.settingsChanged()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add folder…") { addRoot() }
            } header: {
                Text("Code roots")
            } footer: {
                Text("Agent worktree directories are always scanned and cannot be removed from this list.")
                    .font(.system(size: 10))
            }

            Section {
                ForEach(Harness.allCases, id: \.self) { harness in
                    Toggle(harness.displayName, isOn: Binding(
                        get: { settings.enabledHarnesses.contains(harness) },
                        set: { isOn in
                            var current = settings.enabledHarnesses
                            if isOn { current.insert(harness) } else { current.remove(harness) }
                            settings.enabledHarnesses = current
                        }
                    ))
                }
            } header: {
                Text("Harnesses")
            }

            Section {
                HStack {
                    Text("Recent session window")
                    Slider(value: $settings.recentSessionHours, in: 1...168, step: 1)
                    Text("\(Int(settings.recentSessionHours))h")
                        .font(Theme.mono(11))
                        .frame(width: 46, alignment: .trailing)
                }
                Button("Rescan now") { model.settingsChanged() }
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Image(systemName: "scissors").font(.system(size: 22)).foregroundStyle(Theme.safe)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Channel.current.displayName).font(.system(size: 15, weight: .semibold))
                    Text("Version \(Updater.currentVersion)")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.secondary)
                }
            }

            Text("""
            Cuts agent worktrees back so they grow again. Sweeping removes build output \
            that any install command rebuilds. Removing is gated behind eleven checks, \
            all re-run at the moment of deletion.
            """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Theme.line)

            HStack {
                Button("Activity log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                Button("Source") {
                    if let url = URL(string: "https://github.com/\(Updater.repository)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
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
