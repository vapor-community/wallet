import FluentKit
import FluentWalletOrders
import Vapor

struct AppleOrderMiddleware<OrderType: OrderModel>: AsyncMiddleware {
    func respond(
        to request: Request, chainingTo next: any AsyncResponder
    ) async throws -> Response {
        guard
            let id = request.parameters.get("orderIdentifier", as: UUID.self),
            let authToken = request.headers["Authorization"].first?.replacingOccurrences(of: "AppleOrder ", with: ""),
            (try await OrderType.query(on: request.db)
                .filter(\._$id == id)
                .filter(\._$authenticationToken == authToken)
                .first()) != nil
        else {
            throw Abort(.unauthorized)
        }
        return try await next.respond(to: request)
    }
}
