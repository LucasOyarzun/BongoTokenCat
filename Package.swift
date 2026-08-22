// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BongoTokenBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BongoKit",
            path: "Sources/BongoKit",
            resources: [.copy("Resources/images")]
        ),
        .executableTarget(
            name: "BongoTokenBar",
            dependencies: ["BongoKit"],
            path: "Sources/BongoTokenBar"
        ),
    ]
)
