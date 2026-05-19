import Vapor

extension Request {
    /// Returns the real client IP address, preferring the value forwarded by the
    /// reverse proxy (Caddy) over the raw TCP connection address.
    ///
    /// Caddy appends the connecting client's address to `X-Forwarded-For`, so the
    /// **rightmost** entry is the one Caddy itself inserted and is therefore
    /// trustworthy regardless of any values a client may have injected beforehand.
    /// We fall back to `X-Real-IP` (if Caddy is configured to set it) and finally
    /// to `remoteAddress` so that local / direct connections still work.
    var realIPAddress: String? {
        if let forwarded = headers.first(name: "X-Forwarded-For") {
            // Take the last (rightmost) entry — the one appended by Caddy.
            let lastIP = forwarded
                .split(separator: ",")
                .last
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if let ip = lastIP, !ip.isEmpty {
                return ip
            }
        }

        if let realIP = headers.first(name: "X-Real-IP"), !realIP.isEmpty {
            return realIP
        }

        return remoteAddress?.ipAddress
    }
}
