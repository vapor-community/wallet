// swift-tools-version:6.0
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
        .package(url: "https://github.com/vapor/vapor.git", from: "4.111.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/fpseverino/fluent-wallet.git", branch: "main"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.2.0"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "VaporWallet",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            swiftSettings: swiftSettings
        ),
        // MARK: - Wallet Passes
        .target(
            name: "VaporWalletPasses",
            dependencies: [
                .target(name: "VaporWallet"),
                .product(name: "FluentWalletPasses", package: "fluent-wallet"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporWalletPassesTests",
            dependencies: [
                .target(name: "VaporWalletPasses"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
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
        .enableUpcomingFeature("ExistentialAny")
    ]
}
