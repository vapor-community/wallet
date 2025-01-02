import APNS
import APNSCore
import Fluent
import FluentWalletPasses
import NIOSSL
import VaporWallet
import Vapor
import VaporAPNS
import WalletPasses
@_spi(CMS) import X509
import Zip

/// Class to handle ``PassesService``.
///
/// The generics should be passed in this order:
/// - Pass Data Model
/// - Pass Type
/// - User Personalization Type
/// - Device Type
/// - Registration Type
public final class PassesServiceCustom<
    PD: PassDataModel,
    P: PassModel,
    U: PersonalizationModel,
    D: DeviceModel,
    R: PassesRegistrationModel
>: Sendable where P == PD.PassType, P == R.PassType, D == R.DeviceType, U.PassType == P {
    private unowned let app: Application
    private let logger: Logger?
    private let builder: PassBuilder

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - app: The `Vapor.Application` to use in route handlers and APNs.
    ///   - pushRoutesMiddleware: The `Middleware` to use for push notification routes. If `nil`, push routes will not be registered.
    ///   - logger: The `Logger` to use.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing passes.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing passes.
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
        self.builder = PassBuilder(
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
            as: .init(string: "passes"),
            isDefault: false
        )

        let passTypeIdentifier = PathComponent(stringLiteral: PD.typeIdentifier)
        let v1 = app.grouped("api", "passes", "v1")
        v1.get(
            "devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier,
            use: { try await self.passesForDevice(req: $0) }
        )
        v1.post("log", use: { try await self.logMessage(req: $0) })
        v1.post("passes", passTypeIdentifier, ":passSerial", "personalize", use: { try await self.personalizedPass(req: $0) })

        let v1auth = v1.grouped(ApplePassMiddleware<P>())
        v1auth.post(
            "devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier, ":passSerial",
            use: { try await self.registerDevice(req: $0) }
        )
        v1auth.get("passes", passTypeIdentifier, ":passSerial", use: { try await self.latestVersionOfPass(req: $0) })
        v1auth.delete(
            "devices", ":deviceLibraryIdentifier", "registrations", passTypeIdentifier, ":passSerial",
            use: { try await self.unregisterDevice(req: $0) }
        )

        if let pushRoutesMiddleware {
            let pushAuth = v1.grouped(pushRoutesMiddleware)
            pushAuth.post("push", passTypeIdentifier, ":passSerial", use: { try await self.pushUpdatesForPass(req: $0) })
            pushAuth.get("push", passTypeIdentifier, ":passSerial", use: { try await self.tokensForPassUpdate(req: $0) })
        }
    }
}

// MARK: - API Routes
extension PassesServiceCustom {
    fileprivate func registerDevice(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called register device")

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
            let pass = try await P.query(on: req.db)
                .filter(\._$typeIdentifier == PD.typeIdentifier)
                .filter(\._$id == serial)
                .first()
        else {
            throw Abort(.notFound)
        }

        let device = try await D.query(on: req.db)
            .filter(\._$libraryIdentifier == deviceLibraryIdentifier)
            .filter(\._$pushToken == pushToken)
            .first()
        if let device = device {
            return try await Self.createRegistration(device: device, pass: pass, db: req.db)
        } else {
            let newDevice = D(libraryIdentifier: deviceLibraryIdentifier, pushToken: pushToken)
            try await newDevice.create(on: req.db)
            return try await Self.createRegistration(device: newDevice, pass: pass, db: req.db)
        }
    }

    private static func createRegistration(device: D, pass: P, db: any Database) async throws -> HTTPStatus {
        let r = try await R.for(
            deviceLibraryIdentifier: device.libraryIdentifier,
            typeIdentifier: pass.typeIdentifier,
            on: db
        )
        .filter(P.self, \._$id == pass.requireID())
        .first()
        // If the registration already exists, docs say to return 200 OK
        if r != nil { return .ok }

        let registration = R()
        registration._$pass.id = try pass.requireID()
        registration._$device.id = try device.requireID()
        try await registration.create(on: db)
        return .created
    }

    fileprivate func passesForDevice(req: Request) async throws -> SerialNumbersDTO {
        logger?.debug("Called passesForDevice")

        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!

        var query = R.for(
            deviceLibraryIdentifier: deviceLibraryIdentifier,
            typeIdentifier: PD.typeIdentifier,
            on: req.db
        )
        if let since: TimeInterval = req.query["passesUpdatedSince"] {
            let when = Date(timeIntervalSince1970: since)
            query = query.filter(P.self, \._$updatedAt > when)
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

    fileprivate func latestVersionOfPass(req: Request) async throws -> Response {
        logger?.debug("Called latestVersionOfPass")

        var ifModifiedSince: TimeInterval = 0
        if let header = req.headers[.ifModifiedSince].first, let ims = TimeInterval(header) {
            ifModifiedSince = ims
        }

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard
            let pass = try await P.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        guard ifModifiedSince < pass.updatedAt?.timeIntervalSince1970 ?? 0 else {
            throw Abort(.notModified)
        }

        guard
            let passData = try await PD.query(on: req.db)
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

    fileprivate func unregisterDevice(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called unregisterDevice")

        guard let passId = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        let deviceLibraryIdentifier = req.parameters.get("deviceLibraryIdentifier")!

        guard
            let r = try await R.for(
                deviceLibraryIdentifier: deviceLibraryIdentifier,
                typeIdentifier: PD.typeIdentifier,
                on: req.db
            )
            .filter(P.self, \._$id == passId)
            .first()
        else {
            throw Abort(.notFound)
        }
        try await r.delete(on: req.db)
        return .ok
    }

    fileprivate func logMessage(req: Request) async throws -> HTTPStatus {
        if let logger {
            let body: LogEntriesDTO
            do {
                body = try req.content.decode(LogEntriesDTO.self)
            } catch {
                throw Abort(.badRequest)
            }

            for log in body.logs {
                logger.notice("VaporWalletPasses: \(log)")
            }
            return .ok
        } else {
            return .badRequest
        }
    }

    fileprivate func personalizedPass(req: Request) async throws -> Response {
        logger?.debug("Called personalizedPass")

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }
        guard
            try await P.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PD.typeIdentifier)
                .first() != nil
        else {
            throw Abort(.notFound)
        }

        let userInfo = try req.content.decode(PersonalizationDictionaryDTO.self)

        let userPersonalization = U()
        userPersonalization.fullName = userInfo.requiredPersonalizationInfo.fullName
        userPersonalization.givenName = userInfo.requiredPersonalizationInfo.givenName
        userPersonalization.familyName = userInfo.requiredPersonalizationInfo.familyName
        userPersonalization.emailAddress = userInfo.requiredPersonalizationInfo.emailAddress
        userPersonalization.postalCode = userInfo.requiredPersonalizationInfo.postalCode
        userPersonalization.isoCountryCode = userInfo.requiredPersonalizationInfo.isoCountryCode
        userPersonalization.phoneNumber = userInfo.requiredPersonalizationInfo.phoneNumber
        userPersonalization._$pass.id = id
        try await userPersonalization.create(on: req.db)

        guard let token = userInfo.personalizationToken.data(using: .utf8) else {
            throw Abort(.internalServerError)
        }

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "application/octet-stream")
        headers.add(name: .contentTransferEncoding, value: "binary")
        return try Response(status: .ok, headers: headers, body: Response.Body(data: self.builder.signature(for: token)))
    }

    // MARK: - Push Routes
    fileprivate func pushUpdatesForPass(req: Request) async throws -> HTTPStatus {
        logger?.debug("Called pushUpdatesForPass")

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard
            let pass = try await P.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        try await sendPushNotifications(for: pass, on: req.db)
        return .noContent
    }

    fileprivate func tokensForPassUpdate(req: Request) async throws -> [String] {
        logger?.debug("Called tokensForPassUpdate")

        guard let id = req.parameters.get("passSerial", as: UUID.self) else {
            throw Abort(.badRequest)
        }

        guard
            let pass = try await P.query(on: req.db)
                .filter(\._$id == id)
                .filter(\._$typeIdentifier == PD.typeIdentifier)
                .first()
        else {
            throw Abort(.notFound)
        }

        return try await Self.registrations(for: pass, on: req.db).map { $0.device.pushToken }
    }
}

// MARK: - Push Notifications
extension PassesServiceCustom {
    /// Sends push notifications for a given pass.
    ///
    /// - Parameters:
    ///   - passData: The pass to send the notifications for.
    ///   - db: The `Database` to use.
    public func sendPushNotifications(for passData: PD, on db: any Database) async throws {
        try await self.sendPushNotifications(for: passData._$pass.get(on: db), on: db)
    }

    private func sendPushNotifications(for pass: P, on db: any Database) async throws {
        let registrations = try await Self.registrations(for: pass, on: db)
        for reg in registrations {
            let backgroundNotification = APNSBackgroundNotification(
                expiration: .immediately,
                topic: reg.pass.typeIdentifier,
                payload: EmptyPayload()
            )
            do {
                try await app.apns.client(.init(string: "passes")).sendBackgroundNotification(
                    backgroundNotification,
                    deviceToken: reg.device.pushToken
                )
            } catch let error as APNSCore.APNSError where error.reason == .badDeviceToken {
                try await reg.device.delete(on: db)
                try await reg.delete(on: db)
            }
        }
    }

    private static func registrations(for pass: P, on db: any Database) async throws -> [R] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await R.query(on: db)
            .join(parent: \._$pass)
            .join(parent: \._$device)
            .with(\._$pass)
            .with(\._$device)
            .filter(P.self, \._$typeIdentifier == PD.typeIdentifier)
            .filter(P.self, \._$id == pass.requireID())
            .all()
    }
}

// MARK: - pkpass file generation
extension PassesServiceCustom {
    /// Generates the pass content bundle for a given pass.
    ///
    /// - Parameters:
    ///   - pass: The pass to generate the content for.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The generated pass content as `Data`.
    public func build(pass: PD, on db: any Database) async throws -> Data {
        try await self.builder.build(
            pass: pass.passJSON(on: db),
            sourceFilesDirectoryPath: pass.sourceFilesDirectoryPath(on: db),
            personalization: pass.personalizationJSON(on: db)
        )
    }

    /// Generates a bundle of passes to enable your user to download multiple passes at once.
    ///
    /// > Note: You can have up to 10 passes or 150 MB for a bundle of passes.
    ///
    /// > Important: Bundles of passes are supported only in Safari. You can't send the bundle via AirDrop or other methods.
    ///
    /// - Parameters:
    ///   - passes: The passes to include in the bundle.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The bundle of passes as `Data`.
    public func build(passes: [PD], on db: any Database) async throws -> Data {
        guard passes.count > 1 && passes.count <= 10 else {
            throw WalletPassesError.invalidNumberOfPasses
        }

        var files: [ArchiveFile] = []
        for (i, pass) in passes.enumerated() {
            try await files.append(ArchiveFile(filename: "pass\(i).pkpass", data: self.build(pass: pass, on: db)))
        }

        let zipFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pkpass")
        try Zip.zipData(archiveFiles: files, zipFilePath: zipFile)
        return try Data(contentsOf: zipFile)
    }
}
