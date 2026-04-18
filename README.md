<div align="center">

<img src="https://avatars.githubusercontent.com/u/26165732?s=200&v=4" width="200" height="200" alt="avatar">
</div>

# Vapor Wallet

<div align="center">

[![Documentation](https://design.vapor.codes/images/readthedocs.svg)](https://swiftpackageindex.com/vapor-community/wallet/documentation)
[![Team Chat](https://design.vapor.codes/images/discordchat.svg)](https://vapor.team)
[![MIT License](https://design.vapor.codes/images/mitlicense.svg)](./LICENSE)
[![Continuous Integration](https://img.shields.io/github/actions/workflow/status/vapor-community/wallet/test.yml?event=push&style=plastic&logo=github&label=tests&logoColor=ccc)](https://github.com/vapor-community/wallet/actions/workflows/test.yml)
[![Code Coverage](https://img.shields.io/codecov/c/github/vapor-community/wallet?style=plastic&logo=codecov&label=codecov)](https://codecov.io/github/vapor-community/wallet)
[![Swift 6.1+](https://design.vapor.codes/images/swift61up.svg)](https://swift.org/)

</div>
<br>

🎟️ 📦 Create, distribute, and update passes and orders for the Apple Wallet app with Vapor.

Use the SPM string to easily include the dependendency in your `Package.swift` file.

```swift
.package(url: "https://github.com/vapor-community/wallet.git", from: "0.8.0")
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
