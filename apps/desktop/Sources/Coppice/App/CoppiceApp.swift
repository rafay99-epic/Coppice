import SwiftUI
import AppKit

@main
struct CoppiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel
    @StateObject private var updater = Updater()

    /// Read once at launch: scene modifiers are evaluated when the scene is
    /// built, not re-evaluated as settings change.
    private let presentsWindowAtLaunch: Bool

    init() {
        let settings = AppSettings()
        let model = AppModel(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        presentsWindowAtLaunch = AppSettings.presentsWindowAtLaunch

        // Start scanning at launch, not when a window opens. This is a menu bar
        // app, so the window may never open at all, and the status item has to
        // show a figure before anyone clicks anything.
        Task { @MainActor in model.start() }
    }

    var body: some Scene {
        // The window is declared first on purpose. SwiftUI treats the leading
        // scene as the app's primary one, and with `MenuBarExtra` in that slot
        // the window scene never presents at launch and `openWindow(id:)`
        // silently does nothing.
        Window("Coppice", id: WindowID.main) {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 820, minHeight: 520)
                // Adopt whatever appearance the user picked. Forcing dark makes
                // the app the only light-on-dark window on a light desktop.
                .task { updater.startAutomaticChecks(settings: settings) }
        }
        .defaultSize(width: 1000, height: 640)
        // Show the window on a first run, so installing a menu bar app is not a
        // launch where visibly nothing happens. Dev always presents it, because
        // that channel exists to be looked at. After onboarding, Stable and
        // Nightly stay quiet in the menu bar the way a background utility should.
        .defaultLaunchBehavior(presentsWindowAtLaunch ? .presented : .suppressed)
        .commands { CoppiceCommands(model: model, updater: updater) }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        }
    }
}

enum WindowID {
    static let main = "coppice.main"
}

/// The real macOS menu bar, present whenever the window is.
///
/// A menu bar app still deserves menu commands: keyboard shortcuts, a discoverable
/// list of what the app can do, and the standard Help/About placement. These
/// replace SwiftUI's document-shaped defaults, which make no sense here.
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
                Task { await model.sweep(model.sweepCandidates) }
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

/// Keeps the process alive with no windows open, and gives the app a real menu
/// bar only while a window is showing.
///
/// A pure accessory app has no menu bar at all, so ⌘R, ⌘, and the About box have
/// nowhere to live. A regular app shows a permanent Dock icon, which a background
/// utility has not earned. Switching policy with the window gets both: no Dock
/// clutter while it sits in the menu bar, a full menu bar once you open it.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Posted when the app is asked to show itself: launching it again from
    /// Finder or Spotlight, or clicking the Dock icon while a window is open.
    static let showWindow = Notification.Name("com.syntaxlabtechnology.coppice.showWindow")

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Launching an already-running app should surface it rather than do
    /// nothing. Without this, opening Coppice from Spotlight when it is already
    /// in the menu bar looks like the app failed to start.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: Self.showWindow, object: nil)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `LSUIElement` makes the app accessory before any code runs, and an
        // accessory app suppresses the window a scene asked to present at
        // launch. When a window is expected, start regular and let the observer
        // below drop back to accessory once it closes.
        NSApp.setActivationPolicy(AppSettings.presentsWindowAtLaunch ? .regular : .accessory)
        Log.shared.write("Coppice \(Updater.currentVersion) (\(Channel.current.rawValue)) launched")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let described = NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) title=\($0.title)" }
            Log.shared.write("windows after launch: \(described.isEmpty ? "none" : described.joined(separator: " | "))")
        }

        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowVisibilityChanged),
                name: name,
                object: nil
            )
        }
    }

    /// Any ordinary window on screen means regular; none means back to accessory.
    /// Panels and the status item's own window are excluded, or opening the menu
    /// would flash a Dock icon.
    @objc private func windowVisibilityChanged() {
        DispatchQueue.main.async {
            let hasWindow = NSApp.windows.contains { window in
                window.isVisible
                    && !(window is NSPanel)
                    && window.canBecomeMain
                    && !window.className.contains("MenuBarExtra")
            }
            let target: NSApplication.ActivationPolicy = hasWindow ? .regular : .accessory
            guard NSApp.activationPolicy() != target else { return }
            NSApp.setActivationPolicy(target)
            if target == .regular { NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

/// The status item. Icon reflects state; the figure only appears once it is worth
/// acting on, so a tidy machine shows a plain icon.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    // The label is the one view guaranteed to exist for the life of the app, so
    // it is where the "show the window" request is answered from. The panel's
    // content is built lazily and cannot serve as the listener.
    @Environment(\.openWindow) private var openWindow

    private var shouldShowSize: Bool {
        settings.showSizeInMenuBar
            && Double(model.reclaimableBytes) >= settings.notifyThresholdGB * 1_073_741_824
    }

    private var symbol: String {
        if model.isWorking { return "scissors.circle.fill" }
        return shouldShowSize ? "scissors.circle.fill" : "scissors"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            if shouldShowSize {
                Text(Format.compactBytes(model.reclaimableBytes))
            }
        }
        // Without this VoiceOver reads the item as "Cut", the system name of the
        // scissors symbol, which says nothing about what the item is.
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

/// Onboarding until it has been through once, then the app.
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

/// Opens the main window from the status item. `activate` is required or the
/// window appears behind whatever the user was in.
@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    openWindow(id: WindowID.main)
    NSApp.activate(ignoringOtherApps: true)
}
