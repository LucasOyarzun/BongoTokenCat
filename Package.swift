// swift-tools-version: 6.0
import PackageDescription

// The app is split so its logic can be tested. This machine has Command Line Tools
// but no Xcode, and neither XCTest nor swift-testing ships a usable module there —
// so tests are a plain executable target (`swift run BongoTests`) rather than a
// `.testTarget`. Everything they exercise lives in BongoKit; the app executable is
// a six-line shim.
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
        .executableTarget(
            name: "BongoTests",
            dependencies: ["BongoKit"],
            path: "Sources/BongoTests"
        ),
    ]
)
