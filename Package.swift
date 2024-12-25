// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "PassKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "VaporPasses", targets: ["VaporPasses"]),
        .library(name: "VaporOrders", targets: ["VaporOrders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/fpseverino/swift-wallet.git", branch: "main"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.108.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/fpseverino/fluent-wallet.git", branch: "main"),
        .package(url: "https://github.com/vapor/apns.git", from: "4.2.0"),
        // used in tests
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "PassKit",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporPasses",
            dependencies: [
                .target(name: "PassKit"),
                .product(name: "WalletPasses", package: "swift-wallet"),
                .product(name: "FluentWalletPasses", package: "fluent-wallet"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporPassesTests",
            dependencies: [
                .target(name: "VaporPasses"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ],
            resources: [
                .copy("SourceFiles")
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "VaporOrders",
            dependencies: [
                .target(name: "PassKit"),
                .product(name: "WalletOrders", package: "swift-wallet"),
                .product(name: "FluentWalletOrders", package: "fluent-wallet"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "VaporOrdersTests",
            dependencies: [
                .target(name: "VaporOrders"),
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
