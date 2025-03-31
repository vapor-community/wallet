import APNS
import APNSCore
import Fluent
import FluentWalletPasses
import NIOSSL
import Vapor
import VaporAPNS
import VaporWallet
import WalletPasses
import ZipArchive

/// Class to handle ``PassesService``.
///
/// The generics should be passed in this order:
/// - `PassDataModel`
/// - `PassModel`
/// - `PersonalizationInfoModel`
/// - `DeviceModel`
/// - `PassesRegistrationModel`
public final class PassesServiceCustom<
    PassDataType: PassDataModel,
    PassType: PassModel,
    PersonalizationInfoType: PersonalizationInfoModel,
    DeviceType: DeviceModel,
    PassesRegistrationType: PassesRegistrationModel
>: Sendable
where
    PassDataType.PassType == PassType,
    PersonalizationInfoType.PassType == PassType,
    PassesRegistrationType.PassType == PassType,
    PassesRegistrationType.DeviceType == DeviceType
{
    private unowned let app: Application
    let builder: PassBuilder

    /// Initializes the service and registers all the routes required for Apple Wallet to work.
    ///
    /// - Parameters:
    ///   - app: The `Vapor.Application` to use in route handlers and APNs.
    ///   - pemWWDRCertificate: Apple's WWDR.pem certificate in PEM format.
    ///   - pemCertificate: The PEM Certificate for signing passes.
    ///   - pemPrivateKey: The PEM Certificate's private key for signing passes.
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
    }
}

// MARK: - Push Notifications
extension PassesServiceCustom {
    /// Sends push notifications for a given pass.
    ///
    /// - Parameters:
    ///   - passData: The pass to send the notifications for.
    ///   - db: The `Database` to use.
    public func sendPushNotifications(for passData: PassDataType, on db: any Database) async throws {
        try await self.sendPushNotifications(for: passData._$pass.get(on: db), on: db)
    }

    func sendPushNotifications(for pass: PassType, on db: any Database) async throws {
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

    private static func registrations(for pass: PassType, on db: any Database) async throws -> [PassesRegistrationType] {
        // This could be done by enforcing the caller to have a Siblings property wrapper,
        // but there's not really any value to forcing that on them when we can just do the query ourselves like this.
        try await PassesRegistrationType.query(on: db)
            .join(parent: \._$pass)
            .join(parent: \._$device)
            .with(\._$pass)
            .with(\._$device)
            .filter(PassType.self, \._$typeIdentifier == PassDataType.typeIdentifier)
            .filter(PassType.self, \._$id == pass.requireID())
            .all()
    }
}

// MARK: - Pass Building
extension PassesServiceCustom {
    /// Generates the pass content bundle for a given pass.
    ///
    /// - Parameters:
    ///   - pass: The pass to generate the content for.
    ///   - db: The `Database` to use.
    ///
    /// - Returns: The generated pass content as `Data`.
    public func build(pass: PassDataType, on db: any Database) async throws -> Data {
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
    public func build(passes: [PassDataType], on db: any Database) async throws -> Data {
        guard passes.count > 1 && passes.count <= 10 else {
            throw WalletPassesError.invalidNumberOfPasses
        }

        let writer = ZipArchiveWriter()
        for (i, pass) in passes.enumerated() {
            try await writer.writeFile(filename: "pass\(i).pkpass", contents: Array(self.build(pass: pass, on: db)))
        }
        return try Data(writer.finalizeBuffer())
    }
}
