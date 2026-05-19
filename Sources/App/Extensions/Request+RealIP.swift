import Vapor

extension Request {
    /// Returns the real client IP address, preferring the value forwarded by the
    /// reverse proxy (Caddy) over the raw TCP connection address.
    ///
    /// Caddy sets the `X-Forwarded-For` header to the original client IP.
    /// When multiple proxies are chained the header is a comma-separated list;
    /// the leftmost value is the original client.  We fall back to `X-Real-IP`
    /// and finally to `remoteAddress` so that local / direct connections still work.
    var realIPAddress: String? {
        if let forwarded = headers.first(name: "X-Forwarded-For") {
            let firstIP = forwarded
                .split(separator: ",")
                .first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let ip = firstIP, !ip.isEmpty {
                return ip
            }
        }

        if let realIP = headers.first(name: "X-Real-IP"), !realIP.isEmpty {
            return realIP
        }

        return remoteAddress?.ipAddress
    }
}
