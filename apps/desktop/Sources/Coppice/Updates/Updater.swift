import Foundation
import AppKit

@MainActor
final class Updater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
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

    var nextCheck: Date? { timer?.fireDate }

    var isBusy: Bool {
        switch status {
        case .checking, .installing: return true
        default: return false
        }
    }

    var statusText: String {
        switch status {
        case .idle: return lastChecked == nil ? "Not checked yet" : "Up to date"
        case .checking: return "Checking…"
        case .upToDate: return "Up to date (\(Self.currentVersion))"
        case .available(let release): return "Version \(release.version) available"
        case .installing: return "Installing with \(UpdateInstaller.method().label)…"
        case .failed(let message): return message
        }
    }

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
            Log.shared.error("update check failed: \(error.localizedDescription)")
            status = silent ? .idle : .failed("Check failed: \(error.localizedDescription)")
        }
    }

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

    func installUpdate() {
        guard case .available(let release) = status else { return }
        let method = UpdateInstaller.method()
        status = .installing
        do {
            try UpdateInstaller.start(version: release.version, assetURL: release.assetURL, method: method)
            Log.shared.write("updating to \(release.version) with \(method.label); Coppice reopens when it is done")
            NSApplication.shared.terminate(nil)
        } catch {
            status = .failed("Update failed: \(error.localizedDescription)")
            Log.shared.error("update failed: \(error.localizedDescription)")
        }
    }
}

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
