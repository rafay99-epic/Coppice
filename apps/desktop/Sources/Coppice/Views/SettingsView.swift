import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case scanning
    case diagnostics
    case about

    var id: Self { self }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .scanning: return "folder"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }
}

struct SettingsPaneView: View {
    let pane: SettingsPane

    var body: some View {
        switch pane {
        case .general: GeneralSettings()
        case .scanning: ScanningSettings()
        case .diagnostics: DiagnosticsSettings()
        case .about: AboutSettings()
        }
    }
}

struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) { content }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.black)
        .toggleStyle(.mono)
        .buttonStyle(.quiet)
        .labeledContentStyle(SettingsRowStyle())
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.heading(17))
                .padding(.bottom, Space.xs)
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    row.padding(.vertical, Space.s)
                    if row.id != rows.last?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
            if let footer {
                Hint(footer).padding(.top, Space.xs)
            }
        }
    }
}

struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.m) {
            configuration.label
            Spacer(minLength: Space.m)
            configuration.content
                .foregroundStyle(.secondary)
        }
    }
}

struct Hint: View {
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
            SettingsSection(title: "Menu bar", footer: "Dock changes apply the next time Coppice opens.") {
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
            }

            SettingsSection(title: "Safety") {
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
            }

            SettingsSection(title: "Updates") {
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
            }
        }
    }
}

private struct ScanningSettings: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        SettingsForm {
            SettingsSection(title: "Code folders", footer: "Agent worktree folders are always scanned.") {
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
            }

            SettingsSection(title: "Agents") {
                ForEach(Harness.allCases, id: \.self) { harness in
                    Toggle(isOn: harnessBinding(harness)) {
                        Label(harness.displayName, systemImage: harness.symbol)
                    }
                }
            }

            SettingsSection(title: "Pull requests", footer: "A merged pull request marks a branch as finished.") {
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
            }

            SettingsSection(title: "Sessions") {
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

            Button("Source code") {
                if let url = URL(string: "https://github.com/\(Updater.repository)") {
                    NSWorkspace.shared.open(url)
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
