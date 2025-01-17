<div align="center">
    <img src="https://avatars.githubusercontent.com/u/26165732?s=200&v=4" width="100" height="100" alt="avatar" />
    <h1>Vapor Wallet</h1>
    <a href="https://swiftpackageindex.com/vapor-community/wallet/documentation">
        <img src="https://design.vapor.codes/images/readthedocs.svg" alt="Documentation">
    </a>
    <a href="https://discord.gg/vapor"><img src="https://design.vapor.codes/images/discordchat.svg" alt="Team Chat"></a>
    <a href="LICENSE"><img src="https://design.vapor.codes/images/mitlicense.svg" alt="MIT License"></a>
    <a href="https://github.com/vapor-community/wallet/actions/workflows/test.yml">
        <img src="https://img.shields.io/github/actions/workflow/status/vapor-community/wallet/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=%23ccc" alt="Continuous Integration">
    </a>
    <a href="https://codecov.io/github/vapor-community/wallet">
        <img src="https://img.shields.io/codecov/c/github/vapor-community/wallet?style=plastic&logo=codecov&label=codecov">
    </a>
    <a href="https://swift.org">
        <img src="https://design.vapor.codes/images/swift60up.svg" alt="Swift 6.0+">
    </a>
</div>
<br>

🎟️ 📦 Create, distribute, and update passes and orders for the Apple Wallet app with Vapor.

Use the SPM string to easily include the dependendency in your `Package.swift` file.

```swift
.package(url: "https://github.com/vapor-community/wallet.git", from: "0.7.0")
```

> Note: This package is made for Vapor 4.

## 🎟️ Wallet Passes

The `VaporWalletPasses` framework provides a set of tools to help you create, build, and distribute digital passes for the Apple Wallet app using a Vapor server.
It also provides a way to update passes after they have been distributed, using APNs, and models to store pass and device data.

Add the `VaporWalletPasses` product to your target's dependencies:

```swift
.product(name: "VaporWalletPasses", package: "wallet")
```

See the framework's [documentation](https://swiftpackageindex.com/vapor-community/wallet/documentation/vaporwalletpasses) for information and guides on how to use it.

For information on Apple Wallet passes, see the [Apple Developer Documentation](https://developer.apple.com/documentation/walletpasses).

## 📦 Wallet Orders

The `VaporWalletOrders` framework provides a set of tools to help you create, build, and distribute orders that users can track and manage in Apple Wallet using a Vapor server.
It also provides a way to update orders after they have been distributed, using APNs, and models to store order and device data.

Add the `VaporWalletOrders` product to your target's dependencies:

```swift
.product(name: "VaporWalletOrders", package: "wallet")
```

See the framework's [documentation](https://swiftpackageindex.com/vapor-community/wallet/documentation/vaporwalletorders) for information and guides on how to use it.

For information on Apple Wallet orders, see the [Apple Developer Documentation](https://developer.apple.com/documentation/walletorders).
