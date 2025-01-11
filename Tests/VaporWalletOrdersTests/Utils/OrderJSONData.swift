import FluentWalletOrders
import Foundation
import WalletOrders

struct OrderJSONData: OrderJSON.Properties, Decodable {
    var schemaVersion = OrderJSON.SchemaVersion.v1
    var orderTypeIdentifier = OrderData.typeIdentifier
    var orderIdentifier: String
    var orderType = OrderJSON.OrderType.ecommerce
    var orderNumber = "HM090772020864"
    var createdAt: String
    var updatedAt: String
    var status = OrderJSON.OrderStatus.open
    var merchant: MerchantData
    var orderManagementURL = "https://www.example.com/"
    var authenticationToken: String
    var webServiceURL = "https://www.example.com/api/orders/"

    struct MerchantData: OrderJSON.Merchant, Decodable {
        var merchantIdentifier = "com.example.pet-store"
        var displayName: String
        var url = "https://www.example.com/"
        var logo = "pet_store_logo.png"
    }

    init(data: OrderData, order: Order) {
        self.orderIdentifier = order.id!.uuidString
        self.authenticationToken = order.authenticationToken
        self.merchant = MerchantData(displayName: data.title)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = .withInternetDateTime
        self.createdAt = dateFormatter.string(from: order.createdAt!)
        self.updatedAt = dateFormatter.string(from: order.updatedAt!)
    }
}
