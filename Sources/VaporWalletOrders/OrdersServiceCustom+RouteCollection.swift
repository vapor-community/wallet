import Fluent
import FluentWalletOrders
import Vapor
import VaporWallet

extension OrdersServiceCustom: RouteCollection {
    public func boot(routes: any RoutesBuilder) throws {
        let orderTypeIdentifier = PathComponent(stringLiteral: OD.typeIdentifier)

        let v1 = routes.grouped("v1")
        v1.get("devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, use: self.ordersForDevice)
        v1.post("log", use: self.logMessage)

        let v1auth = v1.grouped(AppleOrderMiddleware<O>())
        v1auth.post("devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, ":orderIdentifier", use: self.registerDevice)
        v1auth.get("orders", orderTypeIdentifier, ":orderIdentifier", use: self.latestVersionOfOrder)
        v1auth.delete("devices", ":deviceIdentifier", "registrations", orderTypeIdentifier, ":orderIdentifier", use: self.unregisterDevice)
    }

    private func latestVersionOfOrder(req: Request) async throws -> Response {
        req.logger.debug("Called latestVersionOfOrder")

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

    private func registerDevice(req: Request) async throws -> HTTPStatus {
        req.logger.debug("Called register device")

        let pushToken: String
        do {
            pushToken = try req.content.decode(PushTokenDTO.self).pushToken
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

    private static func createRegistration(device: D, order: O, db: any Database) async throws -> HTTPStatus {
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

    private func ordersForDevice(req: Request) async throws -> OrderIdentifiersDTO {
        req.logger.debug("Called ordersForDevice")

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

        return OrderIdentifiersDTO(with: orderIdentifiers, maxDate: maxDate)
    }

    private func logMessage(req: Request) async throws -> HTTPStatus {
        let entries = try req.content.decode(LogEntriesDTO.self)

        for log in entries.logs {
            req.logger.notice("VaporWalletOrders: \(log)")
        }

        return .ok
    }

    private func unregisterDevice(req: Request) async throws -> HTTPStatus {
        req.logger.debug("Called unregisterDevice")

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
}
