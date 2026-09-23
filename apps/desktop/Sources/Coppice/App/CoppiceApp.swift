import SwiftUI
import AppKit

@main
struct CoppiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel
    @StateObject private var updater = Updater()

    private let presentsWindowAtLaunch: Bool

    init() {
        let settings = AppSettings()
        let model = AppModel(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        presentsWindowAtLaunch = AppSettings.presentsWindowAtLaunch

        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        Window("Coppice", id: WindowID.main) {
            RootView()
                .font(.ui)
                .toolbarBackground(.black, for: .windowToolbar)
                .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 900, minHeight: 560)
                .preferredColorScheme(.dark)
                .tint(.white)
                .task { updater.startAutomaticChecks(settings: settings) }
        }
        .defaultSize(width: 1180, height: 720)
        .defaultLaunchBehavior(presentsWindowAtLaunch ? .presented : .suppressed)
        .commands { CoppiceCommands(model: model, updater: updater) }

        MenuBarExtra {
            MenuBarView()
                .font(.ui)
                .preferredColorScheme(.dark)
                .tint(.white)
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .font(.ui)
                .preferredColorScheme(.dark)
                .tint(.white)
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        }
    }
}

enum WindowID {
    static let main = "coppice.main"
}

struct CoppiceCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .saveItem) {}

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Task { await updater.checkNow() } }
                .disabled(!Channel.current.updatesEnabled || updater.isBusy)
        }

        CommandMenu("Worktrees") {
            Button("Rescan") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning)

            Divider()

            Button("Sweep Build Artifacts…") {
                model.confirmingSweep = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(model.sweepCandidates.isEmpty || model.isWorking)

            Button("Prune Stale Worktrees") { Task { await model.prune() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(model.prunableReports.isEmpty || model.isWorking)
        }

        CommandGroup(replacing: .help) {
            Button("Coppice Help") {
                if let url = URL(string: "https://github.com/\(Updater.repository)") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Show Activity Log") {
                NSWorkspace.shared.open(Log.shared.logFileURL)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showWindow = Notification.Name("com.syntaxlabtechnology.coppice.showWindow")

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: Self.showWindow, object: nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppSettings.showsDockIcon ? .regular : .accessory)
        Log.shared.write("Coppice \(Updater.currentVersion) (\(Channel.current.rawValue)) launched")

        installExceptionLogger()
        Log.shared.installCrashHandlers()

        if AppSettings.presentsWindowAtLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(name: Self.showWindow, object: nil)
            }
        }
    }

    private func installExceptionLogger() {
        NSSetUncaughtExceptionHandler { exception in
            Log.shared.critical(
                "uncaught \(exception.name.rawValue): \(exception.reason ?? "no reason given")"
            )
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    private var shouldShowSize: Bool {
        settings.showSizeInMenuBar
            && Double(model.reclaimableBytes) >= settings.notifyThresholdGB * 1_000_000_000
    }

    private var symbol: String {
        if model.isWorking { return "arrow.triangle.2.circlepath" }
        return shouldShowSize ? "scissors.circle.fill" : "scissors"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
            if shouldShowSize {
                Text(Format.compactBytes(model.reclaimableBytes))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coppice")
        .accessibilityValue(
            shouldShowSize ? "\(Format.bytes(model.reclaimableBytes)) reclaimable" : "Nothing to reclaim"
        )
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.showWindow)) { _ in
            openMainWindow(openWindow)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if settings.hasCompletedOnboarding {
            MainView()
        } else {
            OnboardingView()
        }
    }
}

@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    openWindow(id: WindowID.main)
    NSApp.activate(ignoringOtherApps: true)
}
