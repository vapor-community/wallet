import FluentKit
import FluentSQLiteDriver
import FluentWalletPasses
import Testing
import Vapor
import VaporWalletPasses
import WalletPasses

func withApp(
    useEncryptedKey: Bool = false,
    _ body: (Application, PassesService<PassData>) async throws -> Void
) async throws {
    let app = try await Application.make(.testing)
    do {
        try #require(isLoggingConfigured)

        app.databases.use(.sqlite(.memory), as: .sqlite)
        PassesService<PassData>.register(migrations: app.migrations, withPersonalization: true)
        app.migrations.add(CreatePassData())
        try await app.autoMigrate()

        let passesService = try PassesService<PassData>(
            app: app,
            pemWWDRCertificate: TestCertificate.pemWWDRCertificate,
            pemCertificate: useEncryptedKey ? TestCertificate.encryptedPemCertificate : TestCertificate.pemCertificate,
            pemPrivateKey: useEncryptedKey ? TestCertificate.encryptedPemPrivateKey : TestCertificate.pemPrivateKey,
            pemPrivateKeyPassword: useEncryptedKey ? "password" : nil
        )

        app.databases.middleware.use(passesService, on: .sqlite)

        try app.grouped("api", "passes").register(collection: passesService)

        try await body(app, passesService)

        try await app.autoRevert()
    } catch {
        try? await app.autoRevert()
        try await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}
