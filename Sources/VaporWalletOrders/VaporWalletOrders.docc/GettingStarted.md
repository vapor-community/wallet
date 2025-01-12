# Getting Started with Orders

Create the order data model, build an order for Apple Wallet and distribute it with a Vapor server.

## Overview

The `FluentWalletOrders` framework provides models to save all the basic information for orders, user devices and their registration to each order.
For all the other custom data needed to generate the order, such as the barcodes, merchant info, etc., you have to create your own model and its model middleware to handle the creation and update of order.
The order data model will be used to generate the `order.json` file contents.

See `FluentWalletOrders`'s documentation on `OrderDataModel` to understand how to implement the order data model and do it before continuing with this guide.

> Important: You **must** add `api/orders/` to the `webServiceURL` key of the `OrderJSON.Properties` struct.

The order you distribute to a user is a signed bundle that contains the `order.json` file, images, and optional localizations.
The `VaporWalletOrders` framework provides the ``OrdersService`` class that handles the creation of the order JSON file and the signing of the order bundle.
The ``OrdersService`` class also provides methods to send push notifications to all devices registered when you update an order, and all the routes that Apple Wallet uses to retrieve orders.

### Initialize the Service

After creating the order data model and the order JSON data struct, initialize the ``OrdersService`` inside the `configure.swift` file.
This will implement all of the routes that Apple Wallet expects to exist on your server.

> Tip: Obtaining the three certificates files could be a bit tricky. You could get some guidance from [this guide](https://github.com/alexandercerutti/passkit-generator/wiki/Generating-Certificates) and [this video](https://www.youtube.com/watch?v=rJZdPoXHtzI). Those guides are for Wallet passes, but the process is similar for Wallet orders.

```swift
import Fluent
import Vapor
import VaporWalletOrders

public func configure(_ app: Application) async throws {
    ...
    let ordersService = try OrdersService<OrderData>(
        app: app,
        pemWWDRCertificate: Environment.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: Environment.get("PEM_CERTIFICATE")!,
        pemPrivateKey: Environment.get("PEM_PRIVATE_KEY")!
    )
}
```

If you wish to include routes specifically for sending push notifications to updated orders, you can also pass to the ``OrdersService`` initializer whatever `Middleware` you want Vapor to use to authenticate the two routes. Doing so will add two routes, the first one sends notifications and the second one retrieves a list of push tokens which would be sent a notification.

```http
POST https://example.com/api/orders/v1/push/{orderTypeIdentifier}/{orderIdentifier} HTTP/2
```

```http
GET https://example.com/api/orders/v1/push/{orderTypeIdentifier}/{orderIdentifier} HTTP/2
```

### Custom Implementation of OrdersService

If you don't like the schema names provided by `FluentWalletOrders`, you can create your own models conforming to `OrderModel`, `DeviceModel` and `OrdersRegistrationModel` and instantiate the generic ``OrdersServiceCustom``, providing it your model types.

```swift
import Fluent
import FluentWalletOrders
import Vapor
import VaporWalletOrders

public func configure(_ app: Application) async throws {
    ...
    let ordersService = try OrdersServiceCustom<
        OrderData,
        MyOrderType,
        MyDeviceType,
        MyOrdersRegistrationType
    >(
        app: app,
        pemWWDRCertificate: Environment.get("PEM_WWDR_CERTIFICATE")!,
        pemCertificate: Environment.get("PEM_CERTIFICATE")!,
        pemPrivateKey: Environment.get("PEM_PRIVATE_KEY")!
    )
}
```

### Register Migrations

If you're using the default schemas provided by `FluentWalletOrders`, you can register the default models in your `configure(_:)` method:

```swift
OrdersService<OrderData>.register(migrations: app.migrations)
```

> Important: Register the default models before the migration of your order data model.

### Order Data Model Middleware

This framework provides a model middleware to handle the creation and update of the order data model.

When you create an `OrderDataModel` object, it will automatically create an `OrderModel` object with a random auth token and the correct type identifier and link it to the order data model.
When you update an order data model, it will update the `OrderModel` object and send a push notification to all devices registered to that order.

You can register it like so (either with an ``OrdersService`` or an ``OrdersServiceCustom``):

```swift
app.databases.middleware.use(ordersService, on: .psql)
```

> Note: If you don't like the default implementation of the model middleware, it is highly recommended that you create your own. But remember: whenever your order data changes, you must update the `Order.updatedAt` time of the linked `Order` so that Wallet knows to retrieve a new order.

### Generate the Order Content

To generate and distribute the `.order` bundle, pass the ``OrdersService`` object to your `RouteCollection`.

```swift
import Fluent
import Vapor
import VaporWalletOrders

struct OrdersController: RouteCollection {
    let ordersService: OrdersService

    func boot(routes: RoutesBuilder) throws {
        ...
    }
}
```

> Note: You'll have to register the `OrdersController` in the `configure.swift` file, in order to pass it the ``OrdersService`` object.

Then use the object inside your route handlers to generate the order bundle with the ``OrdersService/build(order:on:)`` method and distribute it with the "`application/vnd.apple.order`" MIME type.

```swift
fileprivate func orderHandler(_ req: Request) async throws -> Response {
    ...
    guard let order = try await OrderData.query(on: req.db)
        .filter(...)
        .first()
    else {
        throw Abort(.notFound)
    }

    let bundle = try await ordersService.build(order: order, on: req.db)
    let body = Response.Body(data: bundle)
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "application/vnd.apple.order")
    headers.add(name: .contentDisposition, value: "attachment; filename=name.order")
    headers.lastModified = HTTPHeaders.LastModified(order.updatedAt ?? Date.distantPast)
    headers.add(name: .contentTransferEncoding, value: "binary")
    return Response(status: .ok, headers: headers, body: body)
}
```
