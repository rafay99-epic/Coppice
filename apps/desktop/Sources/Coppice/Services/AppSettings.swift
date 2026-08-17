import Foundation
import SwiftUI

/// User preferences, persisted in `UserDefaults`.
///
/// Deliberately small. Everything here changes behaviour; nothing is a knob for
/// its own sake. Note what is absent: there is no "sweep automatically" option,
/// because a background process deleting files unattended is exactly the thing
/// this app is designed not to do.
@MainActor
final class AppSettings: ObservableObject {
    /// Directories that may contain repositories.
    @AppStorage("codeRoots") private var codeRootsRaw: String = ""
    /// Harnesses the user chose to include, empty meaning "all detected".
    @AppStorage("enabledHarnesses") private var enabledHarnessesRaw: String = ""
    /// Menu bar shows reclaimable space once it crosses this, in gigabytes.
    @AppStorage("notifyThresholdGB") var notifyThresholdGB: Double = 5.0
    @AppStorage("showSizeInMenuBar") var showSizeInMenuBar: Bool = true
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("autoUpdateCheck") var autoUpdateCheck: Bool = true
    /// Rescue gitignored config to a folder before removing a worktree.
    @AppStorage("rescueIgnoredConfig") var rescueIgnoredConfig: Bool = true
    /// Show a Dock icon and the app menu bar. Off by default: this is a
    /// background utility and the menu bar item is the way in.
    ///
    /// Read only at launch and never re-applied, because changing the activation
    /// policy while the app is running shows or hides the system menu bar, which
    /// resizes every window mid-layout. That crashed 0.6.
    @AppStorage("showsDockIcon") var showsDockIcon: Bool = false
    /// Look up pull request state so a finished branch can be recognised.
    @AppStorage("checkPullRequests") var checkPullRequests: Bool = true
    /// How recently an agent session counts as recent, in hours.
    @AppStorage("recentSessionHours") var recentSessionHours: Double = 24

    var codeRoots: [URL] {
        get {
            let paths = codeRootsRaw
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
            let resolved = paths.isEmpty ? Self.defaultCodeRootPaths() : paths
            return resolved.map { URL(fileURLWithPath: $0) }
        }
        set {
            codeRootsRaw = newValue.map(\.path).joined(separator: "\n")
            objectWillChange.send()
        }
    }

    var enabledHarnesses: Set<Harness> {
        get {
            let names = enabledHarnessesRaw
                .split(separator: ",", omittingEmptySubsequences: true)
                .map(String.init)
            if names.isEmpty { return Set(Harness.allCases) }
            return Set(names.compactMap(Harness.init(rawValue:)))
        }
        set {
            enabledHarnessesRaw = newValue.map(\.rawValue).joined(separator: ",")
            objectWillChange.send()
        }
    }

    var rescueDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Documents/Coppice Rescue")
    }

    /// Whether the main window should come up at launch.
    ///
    /// Static because both the scene modifier and the app delegate need the same
    /// answer before any instance exists. Reads `UserDefaults` directly for the
    /// same reason.
    /// The launch-time reading of `showsDockIcon`, for the app delegate, which
    /// runs before any instance exists.
    /// `nonisolated` because the app delegate reads it before the main actor is
    /// meaningfully established, and it only reads UserDefaults, which is
    /// thread safe.
    nonisolated static var showsDockIcon: Bool {
        UserDefaults.standard.bool(forKey: "showsDockIcon")
    }

    nonisolated static var presentsWindowAtLaunch: Bool {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        return !completed || Channel.current == .dev
    }

    /// Code directories that actually exist, so a fresh install starts with
    /// sensible roots and the onboarding screen has something to show.
    static func defaultCodeRootPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [String] {
        ["Code", "Developer", "Projects", "dev", "work", "src"]
            .map { home.appending(path: $0).path }
            .filter { fileManager.fileExists(atPath: $0) }
    }
}

/// Which build this is. Stable and Nightly install side by side with different
/// bundle ids, settings and icons; Dev is local-only and never auto-updates.
enum Channel: String, Sendable {
    case stable, nightly, dev

    static var current: Channel {
        let raw = Bundle.main.infoDictionary?["CoppiceChannel"] as? String ?? "stable"
        return Channel(rawValue: raw) ?? .stable
    }

    var displayName: String {
        switch self {
        case .stable: return "Coppice"
        case .nightly: return "Coppice Nightly"
        case .dev: return "Coppice Dev"
        }
    }

    /// The DMG this channel updates from. Dev publishes nothing.
    var assetName: String? {
        switch self {
        case .stable: return "Coppice.dmg"
        case .nightly: return "Coppice-Nightly.dmg"
        case .dev: return nil
        }
    }

    var updatesEnabled: Bool { self != .dev }
    /// Nightly tracks pre-releases; Stable tracks full releases.
    var usesPrereleases: Bool { self == .nightly }
}
