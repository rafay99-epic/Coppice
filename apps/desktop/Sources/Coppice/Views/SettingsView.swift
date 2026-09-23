import SwiftUI
import AppKit

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
        .font(.ui)
        .tint(.white)
        .frame(width: 580, height: 560)
        .toolbarBackground(.black, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .background(.black)
    }
}

private struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(.black)
            .contentMargins(.horizontal, Space.xl, for: .scrollContent)
            .contentMargins(.vertical, Space.l, for: .scrollContent)
    }
}

private struct SettingsHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.heading(17))
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.top, Space.s)
            .padding(.bottom, Space.xs)
    }
}

private struct Hint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.uiCaption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: Updater

    var body: some View {
        SettingsForm {
            Section {
                Toggle("Show reclaimable space", isOn: $settings.showSizeInMenuBar)
                LabeledContent("Show from") {
                    HStack(spacing: Space.m) {
                        Slider(value: $settings.notifyThresholdGB, in: 1...50, step: 1)
                            .frame(width: 180)
                        Text("\(Int(settings.notifyThresholdGB)) GB")
                            .monospacedDigit()
                            .numeric(settings.notifyThresholdGB)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .disabled(!settings.showSizeInMenuBar)
                Toggle("Show Coppice in the Dock", isOn: $settings.showsDockIcon)
            } header: {
                SettingsHeader(title: "Menu bar")
            } footer: {
                Hint("Dock changes apply the next time Coppice opens.")
            }

            Section {
                Toggle("Save .env files before removing", isOn: $settings.rescueIgnoredConfig)
                LabeledContent("Saved to") {
                    Button(settings.rescueDirectory.lastPathComponent) {
                        try? FileManager.default.createDirectory(
                            at: settings.rescueDirectory,
                            withIntermediateDirectories: true
                        )
                        NSWorkspace.shared.open(settings.rescueDirectory)
                    }
                    .buttonStyle(.link)
                    .foregroundStyle(.primary)
                }
            } header: {
                SettingsHeader(title: "Safety")
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.autoUpdateCheck)
                LabeledContent("Status") {
                    HStack(spacing: Space.m) {
                        Text(updater.statusText)
                            .foregroundStyle(.secondary)
                            .numeric(updater.statusText)
                        Button("Check now") { Task { await updater.checkNow() } }
                            .disabled(updater.isBusy || !Channel.current.updatesEnabled)
                    }
                }
            } header: {
                SettingsHeader(title: "Updates")
            }
        }
    }
}

private struct ScanningSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsForm {
            Section {
                ForEach(settings.codeRoots, id: \.self) { root in
                    HStack(spacing: Space.m) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text((root.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.codeRoots = settings.codeRoots.filter { $0 != root }
                            model.settingsChanged()
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .accessibilityLabel("Stop scanning this folder")
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Stop scanning this folder")
                    }
                }
                Button("Add folder…") { addRoot() }
            } header: {
                SettingsHeader(title: "Code folders")
            } footer: {
                Hint("Agent worktree folders are always scanned.")
            }

            Section {
                ForEach(Harness.allCases, id: \.self) { harness in
                    Toggle(isOn: harnessBinding(harness)) {
                        Label(harness.displayName, systemImage: harness.symbol)
                    }
                }
            } header: {
                SettingsHeader(title: "Agents")
            }

            Section {
                Toggle("Check pull request status", isOn: $settings.checkPullRequests)
                    .disabled(!model.canCheckPullRequests)
                if model.canCheckPullRequests {
                    LabeledContent("Refresh") {
                        Button("Check now") { model.fetchPullRequests() }
                            .disabled(model.isCheckingPullRequests)
                    }
                } else {
                    Hint("Needs the GitHub CLI (gh).")
                }
            } header: {
                SettingsHeader(title: "Pull requests")
            } footer: {
                Hint("A merged pull request marks a branch as finished.")
            }

            Section {
                LabeledContent("Recent session") {
                    HStack(spacing: Space.m) {
                        Slider(value: $settings.recentSessionHours, in: 1...168, step: 1)
                            .frame(width: 180)
                        Text("\(Int(settings.recentSessionHours)) h")
                            .monospacedDigit()
                            .numeric(settings.recentSessionHours)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                LabeledContent("Scan") {
                    Button("Rescan now") { model.settingsChanged() }
                }
            } header: {
                SettingsHeader(title: "Sessions")
            }
        }
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
        VStack(spacing: 0) {
            Spacer(minLength: Space.xl)

            GrowingStump(lineWidth: 1.3)
                .frame(height: 120)

            (Text("Cut it back. ") + Text("It grows again.").font(.display(30, italic: true)))
                .font(.display(30))
                .multilineTextAlignment(.center)
                .padding(.top, Space.xl)

            Text("\(Channel.current.displayName) \(Updater.currentVersion)")
                .font(.uiCallout)
                .foregroundStyle(.secondary)
                .padding(.top, Space.s)

            HStack(spacing: Space.xl) {
                Button("Activity log") { NSWorkspace.shared.open(Log.shared.logFileURL) }
                Button("Source code") {
                    if let url = URL(string: "https://github.com/\(Updater.repository)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .buttonStyle(.link)
            .foregroundStyle(.primary)
            .padding(.top, Space.xl)

            Spacer(minLength: Space.xl)

            Text("MIT licensed. Syntax Lab Technology.")
                .font(.uiCaption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}
