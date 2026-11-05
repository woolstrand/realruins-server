import Vapor

/// Adds an `X-Robots-Tag` header so well-behaved crawlers neither index the map
/// browser / API responses nor follow links found in them. The landing page
/// (`/view`) may still be indexed, but its links are not followed.
struct RobotsTagMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let response = try await next.respond(to: request)
        let path = request.url.path

        if path == "/view" || path == "/view/" {
            response.headers.replaceOrAdd(name: "X-Robots-Tag", value: "nofollow")
        } else if path.hasPrefix("/view/") || path == "/maps" || path.hasPrefix("/maps/") {
            response.headers.replaceOrAdd(name: "X-Robots-Tag", value: "noindex, nofollow")
        }
        return response
    }
}
