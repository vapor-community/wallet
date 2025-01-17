import Fluent
import FluentWalletPasses
import Vapor
import VaporWallet

extension PassesServiceCustom: RouteCollection {
    public func boot(routes: any RoutesBuilder) throws {
        let passTypeIdentifier = PathComponent(stringLiteral: PassDataType.typeIdentifier)

        let v1 = routes.grouped("v1")
        v1.get("devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier, use: self.updatablePasses)
        v1.post("log", use: self.logMessage)
        v1.post("passes", passTypeIdentifier, ":passSerial", "personalize", use: self.personalizedPass)

        let v1auth = v1.grouped(ApplePassMiddleware<PassType>())
        v1auth.post("devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier, ":passSerial", use: self.registerPass)
        v1auth.get("passes", passTypeIdentifier, ":passSerial", use: self.updatedPass)
        v1auth.delete("devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier, ":passSerial", use: self.unregisterPass)
    }

    private func registerPass(req: Request) async throws -> HTTPStatus {
        req.logger.debug("Called register pass")

        let pushToken: String
        do {
            pushToken = try req.content.decode(PushTokenDTO.self).pushToken
        } catch {
            throw Abort(.badRequest)
        }

        guard let serial = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!
        guard
            let pass = try await PassType.query(on: req.db)
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .filter(\._$id == serial)
                .first()
        else {
            throw Abort(.notFound)
        }

        let device = try await DeviceType.query(on: req.db)
            .filter(\._$libraryIdentifier == deviceLibraryIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        if let device = device {
            return try await Self.createRegistration(device: device, pass: pass, db: req.db)
        } else {
            let newDevice = DeviceType(libraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
            try await newDevice.create(on: req.db)
            return try await Self.createRegistration(device: newDevice, pass: pass, db: req.db)
        }
    }

    private static func createRegistration(device: DeviceType, pass: PassType, db: any Database) async throws -> HTTPStatus {
        let r = try await PassesRegistrationType.for(
            deviceLibraryIdentifier: device.libraryIdentifier,
            typeIdentifier: pass.typeIdentifier,
            on: db
        )
        .filter(PassType.self, \._$id == pass.requireID())
        .first()
        // If the registration already exists, docs say to return 200 OK
        if r != nil { return .ok }

        let registration = PassesRegistrationType()
        registration._$pass.id = try pass.requireID()
        registration._$device.id = try device.requireID()
        try await registration.create(on: db)
        return .created
    }

    private func updatablePasses(req: Request) async throws -> SerialNumbersDTO {
        req.logger.debug("Called updatablePasses")

        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!

        var query = PassesRegistrationType.for(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            typeIdentifier: PassDataType.typeIdentifier,
            on: req.db
        )
        if let since: TimeInterval = req.query["passesUpdatedSince"] {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(PassType.self, \._$updatedAt > when)
        }

        let registrations = try await query.all()
        guard !registrations.isEmpty else {
            throw Abort(.noContent)
        }

        var serialNumbers: [String] = []
        var maxDate = Date.distantPast
        for registration in registrations {
            let pass = try await registration._$pass.get(on: req.db)
            try serialNumbers.append(pass.requireID().uuidString)
            if let updatedAt = pass.updatedAt, updatedAt > maxDate {
                maxDate = updatedAt
            }
        }

        return SerialNumbersDTO(with: serialNumbers, maxDate: maxDate)
    }

    private func updatedPass(req: Request) async throws -> Response {
        req.logger.debug("Called updatedPass")

        var ifModifiedSince: TimeInterval = 0
        if let header = req.headers[.ifModifiedSince].first, let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard
            let pass = try await PassType.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        guard ifModifiedSince < pass.updatedAt?.timeIntervalSince1970 ?? 0 else {
            throw Abort(.notModified)
        }

        guard
            let passData = try await PassDataType.query(on: req.db)
                .filter(\._$pass.$id == id)
                .first()
        else {
            throw Abort(.notFound)
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/vnd.apple.pkpass")
        headers.lastModified = HTTPHeaders.LastModified(pass.updatedAt ?? Date.distantPast)
        headers.add(name: .contentTransferEncoding, value: "binary")
        return try await Response(
            status: .ok,
            headers: headers,
            body: Response.Body(data: self.build(pass: passData, on: req.db))
        )
    }

    private func unregisterPass(req: Request) async throws -> HTTPStatus {
        req.logger.debug("Called unregisterPass")

        guard let passId = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!

        guard
            let r = try await PassesRegistrationType.for(
                deviceLibraryIdentifier: deviceLibraryIdentifier,
                typeIdentifier: PassDataType.typeIdentifier,
                on: req.db
            )
            .filter(PassType.self, \._$id == passId)
            .first()
        else {
            throw Abort(.notFound)
        }
        try await r.delete(on: req.db)
        return .ok
    }

    private func logMessage(req: Request) async throws -> HTTPStatus {
        let entries = try req.content.decode(LogEntriesDTO.self)

        for log in entries.logs {
            req.logger.notice("VaporWalletPasses: \(log)")
        }

        return .ok
    }

    private func personalizedPass(req: Request) async throws -> Response {
        req.logger.debug("Called personalizedPass")

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard
            try await PassType.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PassDataType.typeIdentifier)
                .first() != nil
        else {
            throw Abort(.notFound)
        }

        let userInfo = try req.content.decode(PersonalizationDictionaryDTO.self)

        let personalization = PersonalizationInfoType()
        personalization.fullName = userInfo.requiredPersonalizationInfo.fullName
        personalization.givenName = userInfo.requiredPersonalizationInfo.givenName
        personalization.familyName = userInfo.requiredPersonalizationInfo.familyName
        personalization.emailAddress = userInfo.requiredPersonalizationInfo.emailAddress
        personalization.postalCode = userInfo.requiredPersonalizationInfo.postalCode
        personalization.isoCountryCode = userInfo.requiredPersonalizationInfo.isoCountryCode
        personalization.phoneNumber = userInfo.requiredPersonalizationInfo.phoneNumber
        personalization._$pass.id = id
        try await personalization.create(on: req.db)

        guard let token = userInfo.personalizationToken.data(using: .utf8) else {
            throw Abort(.internalServerError)
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/octet-stream")
        headers.add(name: .contentTransferEncoding, value: "binary")
        return try Response(status: .ok, headers: headers, body: Response.Body(data: self.builder.signature(for: token)))
    }
}
