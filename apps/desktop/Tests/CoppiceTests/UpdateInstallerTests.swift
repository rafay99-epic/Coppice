import XCTest
@testable import Coppice

final class UpdateInstallerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appending(path: "coppice-update-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    private func makeApp(version: String, in folder: URL) throws -> URL {
        let app = folder.appending(path: "Coppice.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appending(path: "Coppice").path)
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.coppice-update-test",
            "CFBundleExecutable": "Coppice",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appending(path: "Contents/Info.plist"))
        XCTAssertTrue(Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path]).succeeded)
        return app
    }

    private func makeImage(version: String) throws -> URL {
        let content = root.appending(path: "image-\(version)")
        _ = try makeApp(version: version, in: content)
        let dmg = root.appending(path: "Coppice-\(version).dmg")
        let arguments = ["create", "-quiet", "-srcfolder", content.path, "-volname", "Coppice", "-format", "UDZO", dmg.path]
        let result = Shell.run("/usr/bin/hdiutil", arguments, timeout: 120)
        XCTAssertTrue(result.succeeded, result.stderr)
        return dmg
    }

    private func runScript(app: URL, version: String, image: URL, brew: String) throws -> String {
        let script = root.appending(path: "update.sh")
        try UpdateInstaller.script.write(to: script, atomically: true, encoding: .utf8)
        let log = root.appending(path: "activity.log")
        let result = Shell.run("/bin/sh", [
            script.path, "999999", app.path, version, image.absoluteString, log.path, brew, brew.isEmpty ? "" : "example/tap/coppice", "0",
        ], timeout: 120)
        XCTAssertTrue(result.succeeded, result.stderr)
        return (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    }

    private func version(of app: URL) -> String? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))?["CFBundleShortVersionString"] as? String
    }

    func testFallsBackToGitHubWhenHomebrewFails() throws {
        let installed = root.appending(path: "Applications")
        let app = try makeApp(version: "1.0", in: installed)
        let image = try makeImage(version: "2.0")

        let log = try runScript(app: app, version: "2.0", image: image, brew: "/usr/bin/false")

        XCTAssertEqual(version(of: app), "2.0")
        XCTAssertTrue(log.contains("Homebrew could not upgrade"), log)
        XCTAssertTrue(log.contains("updated to 2.0"), log)
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path + ".old"))
    }

    func testKeepsTheInstalledAppWhenTheImageIsTheWrongVersion() throws {
        let installed = root.appending(path: "Applications")
        let app = try makeApp(version: "1.0", in: installed)
        let image = try makeImage(version: "1.5")

        let log = try runScript(app: app, version: "2.0", image: image, brew: "")

        XCTAssertEqual(version(of: app), "1.0")
        XCTAssertTrue(log.contains("ERROR  update to 2.0 failed"), log)
    }
}
