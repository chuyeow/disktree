// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DiskTree",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DiskTreeCore"),
        .executableTarget(name: "DiskTree", dependencies: ["DiskTreeCore"]),
        .testTarget(name: "DiskTreeCoreTests", dependencies: ["DiskTreeCore"]),
    ],
    swiftLanguageModes: [.v5]
)
