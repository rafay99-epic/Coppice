import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("codeRoots") private var codeRootsRaw: String?
    @AppStorage("enabledHarnesses") private var enabledHarnessesRaw: String?
    @AppStorage("notifyThresholdGB") var notifyThresholdGB: Double = 5.0
    @AppStorage("showSizeInMenuBar") var showSizeInMenuBar: Bool = true
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("autoUpdateCheck") var autoUpdateCheck: Bool = true
    @AppStorage("rescueIgnoredConfig") var rescueIgnoredConfig: Bool = true
    @AppStorage("showsDockIcon") var showsDockIcon: Bool = false
    @AppStorage("checkPullRequests") var checkPullRequests: Bool = true
    @AppStorage("recentSessionHours") var recentSessionHours: Double = 24

    var codeRoots: [URL] {
        get {
            guard let codeRootsRaw else {
                return Self.defaultCodeRootPaths().map { URL(fileURLWithPath: $0) }
            }
            return codeRootsRaw
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { URL(fileURLWithPath: String($0)) }
        }
        set {
            codeRootsRaw = newValue.map(\.path).joined(separator: "\n")
            objectWillChange.send()
        }
    }

    var enabledHarnesses: Set<Harness> {
        get {
            guard let enabledHarnessesRaw else { return Set(Harness.allCases) }
            return Set(
                enabledHarnessesRaw
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .compactMap { Harness(rawValue: String($0)) }
            )
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

    nonisolated static var showsDockIcon: Bool {
        UserDefaults.standard.bool(forKey: "showsDockIcon")
    }

    nonisolated static var presentsWindowAtLaunch: Bool {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        return !completed || Channel.current == .dev
    }

    static func defaultCodeRootPaths(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [String] {
        ["Code", "Developer", "Projects", "dev", "work", "src"]
            .map { home.appending(path: $0).path }
            .filter { fileManager.fileExists(atPath: $0) }
    }
}

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

    var assetName: String? {
        switch self {
        case .stable: return "Coppice.dmg"
        case .nightly: return "Coppice-Nightly.dmg"
        case .dev: return nil
        }
    }

    var updatesEnabled: Bool { self != .dev }
    var usesPrereleases: Bool { self == .nightly }
}
