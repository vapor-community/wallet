import FluentKit
import FluentWalletOrders
import Foundation

extension OrdersService: AsyncModelMiddleware {
    public func create(model: OrderDataType, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        let order = Order(
            typeIdentifier: OrderDataType.typeIdentifier,
            authenticationToken: Data([UInt8].random(count: 12)).base64EncodedString()
        )
        try await order.save(on: db)
        model._$order.id = try order.requireID()
        try await next.create(model, on: db)
    }

    public func update(model: OrderDataType, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        let order = try await model._$order.get(on: db)
        order.updatedAt = Date.now
        try await order.save(on: db)
        try await next.update(model, on: db)
        try await self.sendPushNotifications(for: model, on: db)
    }
}

extension OrdersServiceCustom: AsyncModelMiddleware {
    public func create(model: OrderDataType, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        let order = OrderType(
            typeIdentifier: OrderDataType.typeIdentifier,
            authenticationToken: Data([UInt8].random(count: 12)).base64EncodedString()
        )
        try await order.save(on: db)
        model._$order.id = try order.requireID()
        try await next.create(model, on: db)
    }

    public func update(model: OrderDataType, on db: any Database, next: any AnyAsyncModelResponder) async throws {
        let order = try await model._$order.get(on: db)
        order.updatedAt = Date.now
        try await order.save(on: db)
        try await next.update(model, on: db)
        try await self.sendPushNotifications(for: model, on: db)
    }
}
