import Foundation
import AppKit

/// Checks GitHub Releases, downloads the channel's DMG, and swaps the installed
/// app in place.
///
/// Stable tracks full releases, Nightly tracks pre-releases, Dev has no feed at
/// all. The repository is public, so no token and no auth path.
@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    struct Release: Equatable, Sendable {
        let version: String
        let tag: String
        let assetURL: URL
        let notes: String
    }

    nonisolated static let repository = "rafay99-epic/Coppice"

    nonisolated static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    private var timer: Timer?
    private weak var settings: AppSettings?
    private static let checkInterval: TimeInterval = 6 * 3600

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var statusText: String {
        switch status {
        case .idle: return lastChecked == nil ? "Not checked yet" : "Up to date"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (\(Self.currentVersion))"
        case .available(let release): return "Version \(release.version) available"
        case .downloading(let fraction): return "Downloading \(Int(fraction * 100))%"
        case .installing: return "Installing…"
        case .failed(let message): return message
        }
    }

    /// Checks at launch and every six hours. Dev never checks, because it
    /// publishes nothing to check against.
    ///
    /// The toggle is read when the timer fires rather than subscribed to, so
    /// turning it off takes effect on the next tick with no observation
    /// machinery to keep in sync. One timer for the life of the app.
    func startAutomaticChecks(settings: AppSettings) {
        guard Channel.current.updatesEnabled, timer == nil else { return }
        self.settings = settings

        if settings.autoUpdateCheck {
            Task { await checkNow(silent: true) }
        }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.settings?.autoUpdateCheck == true else { return }
                await self.checkNow(silent: true)
            }
        }
        // Keep firing while a menu or resize tracking loop is running.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkNow(silent: Bool = false) async {
        guard Channel.current.updatesEnabled, !isBusy else { return }
        status = .checking
        do {
            if let release = try await fetchLatest() {
                status = .available(release)
                Log.shared.write("update available: \(release.version)")
            } else {
                status = .upToDate
            }
            lastChecked = Date()
        } catch {
            status = silent ? .idle : .failed("Check failed: \(error.localizedDescription)")
        }
    }

    /// The newest release for this channel, or nil when the running build is
    /// already current.
    private func fetchLatest() async throws -> Release? {
        guard let assetName = Channel.current.assetName,
              let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=20")
        else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Coppice/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Coppice.Updater", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "GitHub returned an unexpected response.",
            ])
        }

        let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
        let wantsPrerelease = Channel.current.usesPrereleases

        for release in releases where release.draft == false && release.prerelease == wantsPrerelease {
            guard let asset = release.assets.first(where: { $0.name == assetName }),
                  let assetURL = URL(string: asset.downloadURL) else { continue }
            let version = release.tagName.hasPrefix("v")
                ? String(release.tagName.dropFirst())
                : release.tagName
            guard Self.isNewer(version, than: Self.currentVersion) else { return nil }
            return Release(
                version: version,
                tag: release.tagName,
                assetURL: assetURL,
                notes: release.body ?? ""
            )
        }
        return nil
    }

    /// Versions are `0.<commit count>`, so a numeric component compare is exact.
    /// A missing or unparseable component sorts as zero rather than throwing.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func components(_ value: String) -> [Int] {
            value.split(separator: "-").first.map(String.init)?
                .split(separator: ".")
                .map { Int($0) ?? 0 } ?? []
        }
        let lhs = components(candidate), rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    /// Downloads the DMG, mounts it, replaces the running bundle, and relaunches.
    func installUpdate() async {
        guard case .available(let release) = status else { return }
        status = .downloading(0)
        do {
            let dmg = try await download(release.assetURL)
            status = .installing
            try install(dmg: dmg)
            Log.shared.write("updated to \(release.version); relaunching")
            relaunch()
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
            Log.shared.write("update failed: \(error.localizedDescription)")
        }
    }

    private func download(_ url: URL) async throws -> URL {
        let (temporary, _) = try await URLSession.shared.download(from: url)
        let destination = FileManager.default.temporaryDirectory
            .appending(path: "Coppice-update-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// Mounts the image, copies the bundle over the running one, unmounts.
    /// `ditto` preserves the code signature, which `cp` does not, and the
    /// signature is what keeps the user's permission grants across updates.
    private func install(dmg: URL) throws {
        let mountPoint = FileManager.default.temporaryDirectory
            .appending(path: "coppice-mount-\(UUID().uuidString)")

        let attach = Shell.run("/usr/bin/hdiutil", [
            "attach", dmg.path, "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path,
        ], timeout: 120)
        guard attach.succeeded else {
            throw NSError(domain: "Coppice.Updater", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Could not open the downloaded image.",
            ])
        }
        defer {
            _ = Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"], timeout: 60)
            try? FileManager.default.removeItem(at: dmg)
        }

        let source = mountPoint.appending(path: "\(Channel.current.displayName).app")
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw NSError(domain: "Coppice.Updater", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "The image did not contain \(Channel.current.displayName).app.",
            ])
        }

        // Replace whatever bundle is actually running, so an app launched from a
        // non-standard location still updates itself in place.
        let installPath = Bundle.main.bundlePath
        let backup = installPath + ".old"
        try? FileManager.default.removeItem(atPath: backup)
        if FileManager.default.fileExists(atPath: installPath) {
            try FileManager.default.moveItem(atPath: installPath, toPath: backup)
        }
        let copy = Shell.run("/usr/bin/ditto", [source.path, installPath], timeout: 180)
        guard copy.succeeded else {
            // Put the working app back rather than leaving the user with nothing.
            try? FileManager.default.moveItem(atPath: backup, toPath: installPath)
            throw NSError(domain: "Coppice.Updater", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Could not install the new version.",
            ])
        }
        try? FileManager.default.removeItem(atPath: backup)
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            Task { @MainActor in NSApplication.shared.terminate(nil) }
        }
    }
}

// MARK: - GitHub payloads

private struct GitHubRelease: Decodable {
    let tagName: String
    let prerelease: Bool
    let draft: Bool
    let body: String?
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case prerelease, draft, body, assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let downloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}
