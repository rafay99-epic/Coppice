import SwiftUI
import AppKit

@main
struct CoppiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel
    @StateObject private var updater: Updater

    init() {
        let settings = AppSettings()
        let model = AppModel(settings: settings)
        let updater = Updater()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: model)
        _updater = StateObject(wrappedValue: updater)

        // Start scanning at launch, not when a window opens. This is a menu bar
        // app, so the window may never open at all — and the menu bar item has
        // to show a reclaimable figure before anyone clicks anything.
        Task { @MainActor in
            model.start()
            updater.startAutomaticChecks(settings: settings)
        }
    }

    var body: some Scene {
        // The whole app lives here. `LSUIElement` in Info.plist keeps it out of
        // the Dock and the app switcher, so the menu bar item is the only way in.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
        } label: {
            MenuBarLabel(model: model, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Window("Coppice", id: WindowID.main) {
            RootView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .frame(minWidth: 880, minHeight: 560)
                .background(Theme.background)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1020, height: 660)
        .commands { CommandGroup(replacing: .newItem) {} }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(settings)
                .environmentObject(updater)
                .preferredColorScheme(.dark)
        }
    }
}

enum WindowID {
    static let main = "coppice.main"
}

/// Keeps the process alive with no windows open, which a menu bar utility needs,
/// and makes window activation work from an accessory app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory, not regular: no Dock tile, no menu bar app menu, but windows
        // still focus properly when opened from the menu bar item.
        NSApp.setActivationPolicy(.accessory)
        Log.shared.write("Coppice \(Updater.currentVersion) (\(Channel.current.rawValue)) launched")
    }
}

/// The menu bar item. Shows reclaimable space once it crosses the threshold, so
/// a quiet machine shows a bare icon and a messy one shows a number worth acting on.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    private var shouldShowSize: Bool {
        settings.showSizeInMenuBar
            && Double(model.reclaimableBytes) >= settings.notifyThresholdGB * 1_073_741_824
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
            if shouldShowSize {
                Text(Format.bytes(model.reclaimableBytes))
                    .font(.system(size: 11, weight: .medium))
            }
        }
        // Without this VoiceOver reads the item as "Cut", the system name of the
        // scissors symbol, which says nothing about what the item is or does.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coppice")
        .accessibilityValue(
            shouldShowSize
                ? "\(Format.bytes(model.reclaimableBytes)) reclaimable"
                : "No reclaimable space"
        )
    }
}

/// Chooses between onboarding and the main view. Onboarding is not a tour: it
/// only appears until the user has been through it once.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .animation(Theme.motion, value: settings.hasCompletedOnboarding)
    }
}

/// Opens the main window from an accessory app. `activate` is required: without
/// it the window appears behind whatever the user was in.
@MainActor
func openMainWindow(_ openWindow: OpenWindowAction) {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: WindowID.main)
}
