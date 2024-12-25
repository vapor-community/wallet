import FluentWalletPasses
import WalletPasses

struct PassJSONData: PassJSON.Properties {
    var description: String
    var formatVersion = PassJSON.FormatVersion.v1
    var organizationName = "vapor-community"
    var passTypeIdentifier = PassData.typeIdentifier
    var serialNumber: String
    var teamIdentifier = "K6512ZA2S5"
    var webServiceURL = "https://www.example.com/api/passes/"
    var authenticationToken: String
    var logoText = "Vapor Community"
    var sharingProhibited = true
    var backgroundColor = "rgb(207, 77, 243)"
    var foregroundColor = "rgb(255, 255, 255)"

    var barcodes = Barcode(message: "test")
    struct Barcode: PassJSON.Barcodes {
        var format = PassJSON.BarcodeFormat.qr
        var message: String
        var messageEncoding = "iso-8859-1"
    }

    var boardingPass = Boarding(transitType: .air)
    struct Boarding: PassJSON.BoardingPass {
        let transitType: PassJSON.TransitType
        let headerFields: [PassField]
        let primaryFields: [PassField]
        let secondaryFields: [PassField]
        let auxiliaryFields: [PassField]
        let backFields: [PassField]

        struct PassField: PassJSON.PassFieldContent {
            let key: String
            let label: String
            let value: String
        }

        init(transitType: PassJSON.TransitType) {
            self.headerFields = [.init(key: "header", label: "Header", value: "Header")]
            self.primaryFields = [.init(key: "primary", label: "Primary", value: "Primary")]
            self.secondaryFields = [.init(key: "secondary", label: "Secondary", value: "Secondary")]
            self.auxiliaryFields = [.init(key: "auxiliary", label: "Auxiliary", value: "Auxiliary")]
            self.backFields = [.init(key: "back", label: "Back", value: "Back")]
            self.transitType = transitType
        }
    }

    init(data: PassData, pass: Pass) {
        self.description = data.title
        self.serialNumber = pass.id!.uuidString
        self.authenticationToken = pass.authenticationToken
    }
}
