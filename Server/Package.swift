// swift-tools-version: 6.2

import PackageDescription

// Alert service: a thin shell around AuroraCore's alert logic (constitution Principle III).
// Its server-only dependencies stay in this package and never reach the app.
let package = Package(
    name: "AlertServer",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.28.0"),
        .package(url: "https://github.com/kylebrowning/APNSwift.git", from: "7.1.0"),
        .package(url: "https://github.com/vapor/sqlite-nio.git", from: "1.13.2"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.2"),
        .package(name: "AuroraCore", path: "../Packages/AuroraCore"),
    ],
    targets: [
        .target(
            name: "AlertServer",
            dependencies: [
                .product(name: "AuroraCore", package: "AuroraCore"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "APNS", package: "APNSwift"),
                .product(name: "SQLiteNIO", package: "sqlite-nio"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
        .executableTarget(
            name: "alert-service",
            dependencies: ["AlertServer"]
        ),
        .testTarget(
            name: "AlertServerTests",
            dependencies: [
                "AlertServer",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
