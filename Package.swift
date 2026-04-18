// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "wallet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VaporWalletPasses", targets: ["VaporWalletPasses"]),
        .library(name: "VaporWalletOrders", targets: ["VaporWalletOrders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/fpseverino/swift-wallet.git", from: "1.0.0"),
        .package(url: "https://github.com/fpseverino/fluent-wallet.git", from: "0.2.0"),
        .package(url: "https://github.com/vapor/apns.git", from: "5.0.0"),
        .package(url: "https://github.com/adam-fowler/swift-zip-archive.git", from: "0.6.4"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.9.0"),
    ],
    targets: [
        .target(
            name: "VaporWallet",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentWallet", package: "fluent-wallet"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            swiftSettings: swiftSettings
        ),
        // MARK: - Wallet Passes
        .target(
            name: "VaporWalletPasses",
            dependencies: [
                .target(name: "VaporWallet"),
                .product(name: "WalletPasses", package: "swift-wallet"),
                .product(name: "FluentWalletPasses", package: "fluent-wallet"),
                .product(name: "ZipArchive", package: "swift-zip-archive"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporWalletPassesTests",
            dependencies: [
                .target(name: "VaporWalletPasses"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "ZipArchive", package: "swift-zip-archive"),
            ],
            resources: [
                .copy("SourceFiles")
            ],
            swiftSettings: swiftSettings
        ),
        // MARK: - Wallet Orders
        .target(
            name: "VaporWalletOrders",
            dependencies: [
                .target(name: "VaporWallet"),
                .product(name: "WalletOrders", package: "swift-wallet"),
                .product(name: "FluentWalletOrders", package: "fluent-wallet"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporWalletOrdersTests",
            dependencies: [
                .target(name: "VaporWalletOrders"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "ZipArchive", package: "swift-zip-archive"),
            ],
            resources: [
                .copy("SourceFiles")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("ImmutableWeakCaptures"),
    ]
}
