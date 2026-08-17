// swift-tools-version: 6.0
import PackageDescription

// Coppice is dependency-free on purpose. Everything it needs (FSEvents, git,
// lsof, AppKit, SwiftUI) ships with macOS, so a build is `swift build` and
// nothing else — no package resolution, no supply chain, no lockfile drift.
let package = Package(
    name: "Coppice",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Coppice",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("CoreServices")]
        ),
        .testTarget(
            name: "CoppiceTests",
            dependencies: ["Coppice"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
