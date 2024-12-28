import APNS
import APNSCore
import Fluent
import FluentWalletOrders
import NIOSSL
import PassKit
import Vapor
import VaporAPNS
import WalletOrders
@_spi(CMS) import X509
import Zip

/// Class to handle ``OrdersService``.
///
/// The generics should be passed in this order:
/// - Order Data Model
/// - Order Type
/// - Device Type
/// - Registration Type
public final class OrdersServiceCustom<
    OD: OrderDataModel,
    O: OrderModel,
    D: DeviceModel,
    R: OrdersRegistrationModel
>: Sendable where O == OD.OrderType, O == R.OrderType, D == R.DeviceType {
    private unowned let app: Application
    private let logger: Logger?
    private let builder: OrderBuilder

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - app: The `Vapor.Application` to use in route handlers and APNs.
    ///   - pushRoutesMiddleware: The `Middleware` to use for push notification routes. If `nil`, push routes will not be registered.
    ///   - logger: The `Logger` to use.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing orders.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing orders.
    ///   - pemPrivateKeyPassword: The password to the private key. If the key is not encrypted it must be `nil`. Defaults to `nil`.
    ///   - openSSLPath: The location of the `openssl` command as a file path.
    public init(
        app: Application,
        pushRoutesMiddleware: (any Middleware)? = nil,
        logger: Logger? = nil,
        pemWWDRCertificate: String,
        pemCertificate: String,
        pemPrivateKey: String,
        pemPrivateKeyPassword: String? = nil,
        openSSLPath: String = "/usr/bin/openssl"
    ) throws {
        self.app = app
        self.logger = logger
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

        let orderTypeIdentifier = PathComponent(stringLiteral: OD.typeIdentifier)
        let v1 = app.grouped("api", "orders", "v1")
        v1.get("devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, use: { try await self.ordersForDevice(req: $0) })
        v1.post("log", use: { try await self.logMessage(req: $0) })

        let v1auth = v1.grouped(AppleOrderMiddleware<O>())
        v1auth.post(
            "devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, ":orderIdentifier",
            use: { try await self.registerDevice(req: $0) }
        )
        v1auth.get("orders", orderTypeIdentifier, ":orderIdentifier", use: { try await self.latestVersionOfOrder(req: $0) })
        v1auth.delete(
            "devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, ":orderIdentifier",
            use: { try await self.unregisterDevice(req: $0) }
        )

        if let pushRoutesMiddleware {
            let pushAuth = v1.grouped(pushRoutesMiddleware)
            pushAuth.post("push", orderTypeIdentifier, ":orderIdentifier", use: { try await self.pushUpdatesForOrder(req: $0) })
            pushAuth.get("push", orderTypeIdentifier, ":orderIdentifier", use: { try await self.tokensForOrderUpdate(req: $0) })
        }
    }
}

// MARK: - API Routes
extension OrdersServiceCustom {
    fileprivate func latestVersionOfOrder(req: Request) async throws -> Response {
        logger?.debug("Called latestVersionOfOrder")

        var ifModifiedSince: TimeInterval = 0
        if let header = req.headers[.ifModifiedSince].first, let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }

        guard let id = req.parameters.get("orderIdentifier", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard
            let order = try await O.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == OD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        guard ifModifiedSince < order.updatedAt?.timeIntervalSince1970 ?? 0 else {
            throw Abort(.notModified)
        }

        guard
            let orderData = try await OD.query(on: req.db)
                .filter(\._$order.$id == id)
                .first()
        else {
            throw Abort(.notFound)
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/vnd.apple.order")
        headers.lastModified = HTTPHeaders.LastModified(order.updatedAt ?? Date.distantPast)
        headers.add(name: .contentTransferEncoding, value: "binary")
        return try await Response(
            status: .ok,
            headers: headers,
            body: Response.Body(data: self.build(order: orderData, on: req.db))
        )
    }

    fileprivate func registerDevice(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called register device")

        let pushToken: String
        do {
            pushToken = try req.content.decode(RegistrationDTO.self).pushToken
        } catch {
            throw Abort(.badRequest)
        }

        guard let orderIdentifier = req.parameters.get("orderIdentifier", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deviceIdentifier = req.parameters.get("deviceIdentifier")!
        guard
            let order = try await O.query(on: req.db)
                .filter(\._$id == orderIdentifier)
                .filter(\._$typeIdentifier == OD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        let device = try await D.query(on: req.db)
            .filter(\._$libraryIdentifier == deviceIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        if let device = device {
            return try await Self.createRegistration(device: device, order: order, db: req.db)
        } else {
            let newDevice = D(libraryIdentifier: deviceIdentifier, pushToken: pushToken)
            try await newDevice.create(on: req.db)
            return try await Self.createRegistration(device: newDevice, order: order, db: req.db)
        }
    }

    private static func createRegistration(
        device: D, order: O, db: any Database
    ) async throws -> HTTPStatus {
        let r = try await R.for(
            deviceLibraryIdentifier: device.libraryIdentifier,
            typeIdentifier: order.typeIdentifier,
            on: db
        )
        .filter(O.self, \._$id == order.requireID())
        .first()
        // If the registration already exists, docs say to return 200 OK
        if r != nil { return .ok }

        let registration = R()
        registration._$order.id = try order.requireID()
        registration._$device.id = try device.requireID()
        try await registration.create(on: db)
        return .created
    }

    fileprivate func ordersForDevice(req: Request) async throws -> OrdersForDeviceDTO {
        logger?.debug("Called ordersForDevice")

        let deviceIdentifier = req.parameters.get("deviceIdentifier")!

        var query = R.for(
            deviceLibraryIdentifier: deviceIdentifier,
            typeIdentifier: OD.typeIdentifier,
            on: req.db
        )
        if let since: TimeInterval = req.query["ordersModifiedSince"] {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(O.self, \._$updatedAt > when)
        }

        let registrations = try await query.all()
        guard !registrations.isEmpty else {
            throw Abort(.noContent)
        }

        var orderIdentifiers: [String] = []
        var maxDate = Date.distantPast
        for registration in registrations {
            let order = try await registration._$order.get(on: req.db)
            try orderIdentifiers.append(order.requireID().uuidString)
            if let updatedAt = order.updatedAt, updatedAt > maxDate {
                maxDate = updatedAt
            }
        }

        return OrdersForDeviceDTO(with: orderIdentifiers, maxDate: maxDate)
    }

    fileprivate func logMessage(req: Request) async throws -> HTTPStatus {
        if let logger {
            let body: LogEntryDTO
            do {
                body = try req.content.decode(LogEntryDTO.self)
            } catch {
                throw Abort(.badRequest)
            }

            for log in body.logs {
                logger.notice("VaporWalletOrders: \(log)")
            }
            return .ok
        } else {
            return .badRequest
        }
    }

    fileprivate func unregisterDevice(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called unregisterDevice")

        guard let orderIdentifier = req.parameters.get("orderIdentifier", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deviceIdentifier = req.parameters.get("deviceIdentifier")!

        guard
            let r = try await R.for(
                deviceLibraryIdentifier: deviceIdentifier,
                typeIdentifier: OD.typeIdentifier,
                on: req.db
            )
            .filter(O.self, \._$id == orderIdentifier)
            .first()
        else {
            throw Abort(.notFound)
        }
        try await r.delete(on: req.db)
        return .ok
    }

    // MARK: - Push Routes
    fileprivate func pushUpdatesForOrder(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called pushUpdatesForOrder")

        guard let id = req.parameters.get("orderIdentifier", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard
            let order = try await O.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == OD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        try await sendPushNotifications(for: order, on: req.db)
        return .noContent
    }

    fileprivate func tokensForOrderUpdate(req: Request) async throws -> [String] {
        logger?.debug("Called tokensForOrderUpdate")

        guard let id = req.parameters.get("orderIdentifier", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard
            let order = try await O.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == OD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        return try await Self.registrations(for: order, on: req.db).map { $0.device.pushToken }
    }
}

// MARK: - Push Notifications
extension OrdersServiceCustom {
    /// Sends push notifications for a given order.
    ///
    /// - Parameters:
    ///   - orderData: The order to send the notifications for.
    ///   - db: The `Database` to use.
    public func sendPushNotifications(for orderData: OD, on db: any Database) async throws {
        try await sendPushNotifications(for: orderData._$order.get(on: db), on: db)
    }

    private func sendPushNotifications(for order: O, on db: any Database) async throws {
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

    private static func registrations(for order: O, on db: any Database) async throws -> [R] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await R.query(on: db)
            .join(parent: \._$order)
            .join(parent: \._$device)
            .with(\._$order)
            .with(\._$device)
            .filter(O.self, \._$typeIdentifier == OD.typeIdentifier)
            .filter(O.self, \._$id == order.requireID())
            .all()
    }
}

// MARK: - order file generation
extension OrdersServiceCustom {
    /// Generates the order content bundle for a given order.
    ///
    /// - Parameters:
    ///   - order: The order to generate the content for.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The generated order content as `Data`.
    public func build(order: OD, on db: any Database) async throws -> Data {
        try await self.builder.build(
            order: order.orderJSON(on: db),
            sourceFilesDirectoryPath: order.sourceFilesDirectoryPath(on: db)
        )
    }
}
