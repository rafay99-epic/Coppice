// swift-tools-version: 6.0
import PackageDescription

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
