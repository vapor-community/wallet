import APNS
import APNSCore
import Fluent
import FluentWalletOrders
import NIOSSL
import Vapor
import VaporAPNS
import VaporWallet
import WalletOrders
import Zip

/// Class to handle ``OrdersService``.
///
/// The generics should be passed in this order:
/// - `OrderDataModel`
/// - `OrderModel`
/// - `DeviceModel`
/// - `OrdersRegistrationModel`
public final class OrdersServiceCustom<
    OrderDataType: OrderDataModel,
    OrderType: OrderModel,
    DeviceType: DeviceModel,
    OrdersRegistrationType: OrdersRegistrationModel
>: Sendable
where
    OrderDataType.OrderType == OrderType,
    OrdersRegistrationType.OrderType == OrderType,
    OrdersRegistrationType.DeviceType == DeviceType
{
    private unowned let app: Application
    let builder: OrderBuilder

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - app: The `Vapor.Application` to use in route handlers and APNs.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing orders.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing orders.
    ///   - pemPrivateKeyPassword: The password to the private key. If the key is not encrypted it must be `nil`. Defaults to `nil`.
    ///   - openSSLPath: The location of the `openssl` command as a file path.
    public init(
        app: Application,
        pemWWDRCertificate: String,
        pemCertificate: String,
        pemPrivateKey: String,
        pemPrivateKeyPassword: String? = nil,
        openSSLPath: String = "/usr/bin/openssl"
    ) throws {
        self.app = app
        self.builder = OrderBuilder(
            pemWWDRCertificate: pemWWDRCertificate,
            pemCertificate: pemCertificate,
            pemPrivateKey: pemPrivateKey,
            pemPrivateKeyPassword: pemPrivateKeyPassword,
            openSSLPath: openSSLPath
        )

        let privateKeyBytes = pemPrivateKey.data(using: .utf8)!.map { UInt8($0) }
        let certificateBytes = pemCertificate.data(using: .utf8)!.map { UInt8($0) }
        let apnsConfig: APNSClientConfiguration
        if let pemPrivateKeyPassword {
            apnsConfig = APNSClientConfiguration(
                authenticationMethod: try .tls(
                    privateKey: .privateKey(
                        NIOSSLPrivateKey(bytes: privateKeyBytes, format: .pem) { passphraseCallback in
                            passphraseCallback(pemPrivateKeyPassword.utf8)
                        }
                    ),
                    certificateChain: NIOSSLCertificate.fromPEMBytes(certificateBytes).map { .certificate($0) }
                ),
                environment: .production
            )
        } else {
            apnsConfig = APNSClientConfiguration(
                authenticationMethod: try .tls(
                    privateKey: .privateKey(NIOSSLPrivateKey(bytes: privateKeyBytes, format: .pem)),
                    certificateChain: NIOSSLCertificate.fromPEMBytes(certificateBytes).map { .certificate($0) }
                ),
                environment: .production
            )
        }
        app.apns.containers.use(
            apnsConfig,
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            responseDecoder: JSONDecoder(),
            requestEncoder: JSONEncoder(),
            as: .init(string: "orders"),
            isDefault: false
        )
    }
}

// MARK: - Push Notifications
extension OrdersServiceCustom {
    /// Sends push notifications for a given order.
    ///
    /// - Parameters:
    ///   - orderData: The order to send the notifications for.
    ///   - db: The `Database` to use.
    public func sendPushNotifications(for orderData: OrderDataType, on db: any Database) async throws {
        try await sendPushNotifications(for: orderData._$order.get(on: db), on: db)
    }

    func sendPushNotifications(for order: OrderType, on db: any Database) async throws {
        let registrations = try await Self.registrations(for: order, on: db)
        for reg in registrations {
            let backgroundNotification = APNSBackgroundNotification(
                expiration: .immediately,
                topic: reg.order.typeIdentifier,
                payload: EmptyPayload()
            )
            do {
                try await app.apns.client(.init(string: "orders")).sendBackgroundNotification(
                    backgroundNotification,
                    deviceToken: reg.device.pushToken
                )
            } catch let error as APNSCore.APNSError where error.reason == .badDeviceToken {
                try await reg.device.delete(on: db)
                try await reg.delete(on: db)
            }
        }
    }

    private static func registrations(for order: OrderType, on db: any Database) async throws -> [OrdersRegistrationType] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await OrdersRegistrationType.query(on: db)
            .join(parent: \._$order)
            .join(parent: \._$device)
            .with(\._$order)
            .with(\._$device)
            .filter(OrderType.self, \._$typeIdentifier == OrderDataType.typeIdentifier)
            .filter(OrderType.self, \._$id == order.requireID())
            .all()
    }
}

// MARK: - Order Building
extension OrdersServiceCustom {
    /// Generates the order content bundle for a given order.
    ///
    /// - Parameters:
    ///   - order: The order to generate the content for.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The generated order content as `Data`.
    public func build(order: OrderDataType, on db: any Database) async throws -> Data {
        try await self.builder.build(
            order: order.orderJSON(on: db),
            sourceFilesDirectoryPath: order.sourceFilesDirectoryPath(on: db)
        )
    }
}
