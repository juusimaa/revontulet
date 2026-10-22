// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AuroraCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "AuroraCore", targets: ["AuroraCore"]),
    ],
    targets: [
        .target(
            name: "AuroraCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AuroraCoreTests",
            dependencies: ["AuroraCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
