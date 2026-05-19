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
            if let ip = lastIP, ip.isValidIPAddress {
                return ip
            }
        }

        if let realIP = headers.first(name: "X-Real-IP"), realIP.isValidIPAddress {
            return realIP
        }

        return remoteAddress?.ipAddress
    }
}

private extension String {
    /// Returns true for bare IPv4 (`1.2.3.4`) and IPv6 addresses, including
    /// the bracketed form used in some headers (`[::1]`).  Port suffixes are
    /// not accepted so junk injected by clients is rejected.
    var isValidIPAddress: Bool {
        let candidate = hasPrefix("[") && hasSuffix("]")
            ? String(dropFirst().dropLast())   // strip brackets from [::1]
            : self
        var addr = in_addr()
        var addr6 = in6_addr()
        return candidate.withCString {
            inet_pton(AF_INET, $0, &addr) == 1 ||
            inet_pton(AF_INET6, $0, &addr6) == 1
        }
    }
}
