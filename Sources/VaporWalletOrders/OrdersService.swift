import FluentKit
import FluentWalletOrders
import Vapor

/// The main class that handles Wallet orders.
public final class OrdersService<OD: OrderDataModel>: Sendable where Order == OD.OrderType {
    private let service: OrdersServiceCustom<OD, Order, OrdersDevice, OrdersRegistration>

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
        self.service = try .init(
            app: app,
            pemWWDRCertificate: pemWWDRCertificate,
            pemCertificate: pemCertificate,
            pemPrivateKey: pemPrivateKey,
            pemPrivateKeyPassword: pemPrivateKeyPassword,
            openSSLPath: openSSLPath
        )
    }

    /// Generates the order content bundle for a given order.
    ///
    /// - Parameters:
    ///   - order: The order to generate the content for.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The generated order content.
    public func build(order: OD, on db: any Database) async throws -> Data {
        try await service.build(order: order, on: db)
    }

    /// Adds the migrations for Wallet orders models.
    ///
    /// - Parameter migrations: The `Migrations` object to add the migrations to.
    public static func register(migrations: Migrations) {
        migrations.add(CreateOrder())
        migrations.add(CreateOrdersDevice())
        migrations.add(CreateOrdersRegistration())
    }

    /// Sends push notifications for a given order.
    ///
    /// - Parameters:
    ///   - order: The order to send the notifications for.
    ///   - db: The `Database` to use.
    public func sendPushNotifications(for order: OD, on db: any Database) async throws {
        try await service.sendPushNotifications(for: order, on: db)
    }
}

extension OrdersService: RouteCollection {
    public func boot(routes: any RoutesBuilder) throws {
        try service.boot(routes: routes)
    }
}
