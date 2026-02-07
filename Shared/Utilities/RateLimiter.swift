import Foundation

/// Thread-safe rate limiter for API calls
/// Prevents excessive requests to external services
actor RateLimiter {
    /// Shared instance for app-wide rate limiting
    static let shared = RateLimiter()

    /// Rate limit configurations per domain pattern
    private struct RateLimit {
        let maxRequests: Int
        let windowSeconds: TimeInterval
    }

    /// Tracks requests per domain
    private var requestHistory: [String: [Date]] = [:]

    /// Domain-specific rate limits
    private let limits: [String: RateLimit] = [
        "etherscan": RateLimit(maxRequests: 5, windowSeconds: 1),      // Etherscan: 5/sec free tier
        "alchemy": RateLimit(maxRequests: 30, windowSeconds: 1),       // Alchemy: generous limits
        "pimlico": RateLimit(maxRequests: 10, windowSeconds: 1),       // Bundler calls
        "coingecko": RateLimit(maxRequests: 10, windowSeconds: 60),    // CoinGecko: 10-30/min
        "opensea": RateLimit(maxRequests: 4, windowSeconds: 1),        // OpenSea: 4/sec
        "default": RateLimit(maxRequests: 20, windowSeconds: 1)        // Default fallback
    ]

    private init() {}

    /// Check if a request to the given URL should be allowed
    /// - Parameter url: The URL being requested
    /// - Returns: true if request is allowed, false if rate limited
    func shouldAllowRequest(to url: URL) -> Bool {
        let domain = extractDomainKey(from: url)
        let limit = limits[domain] ?? limits["default"]!
        let now = Date()

        // Clean up old entries
        let windowStart = now.addingTimeInterval(-limit.windowSeconds)
        var history = requestHistory[domain] ?? []
        history = history.filter { $0 > windowStart }

        if history.count >= limit.maxRequests {
            return false
        }

        history.append(now)
        requestHistory[domain] = history
        return true
    }

    /// Wait until a request is allowed (with timeout)
    /// - Parameters:
    ///   - url: The URL being requested
    ///   - timeout: Maximum time to wait
    /// - Returns: true if request is now allowed, false if timed out
    func waitForAllowance(to url: URL, timeout: TimeInterval = 5.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if shouldAllowRequest(to: url) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        return false
    }

    /// Record a request (for manual tracking)
    func recordRequest(to url: URL) {
        let domain = extractDomainKey(from: url)
        var history = requestHistory[domain] ?? []
        history.append(Date())
        requestHistory[domain] = history
    }

    /// Extract a domain key for rate limiting
    private func extractDomainKey(from url: URL) -> String {
        guard let host = url.host?.lowercased() else { return "default" }

        // Map hosts to rate limit keys
        if host.contains("etherscan") { return "etherscan" }
        if host.contains("alchemy") { return "alchemy" }
        if host.contains("pimlico") { return "pimlico" }
        if host.contains("coingecko") { return "coingecko" }
        if host.contains("opensea") || host.contains("seadn") { return "opensea" }

        return "default"
    }

    /// Reset rate limits (for testing)
    func reset() {
        requestHistory.removeAll()
    }
}

// MARK: - URLSession Extension

extension URLSession {
    /// Perform a data request with rate limiting
    /// - Parameters:
    ///   - url: The URL to fetch
    ///   - rateLimited: Whether to apply rate limiting (default: true)
    /// - Returns: The data and response
    func rateLimitedData(from url: URL, rateLimited: Bool = true) async throws -> (Data, URLResponse) {
        if rateLimited {
            let allowed = await RateLimiter.shared.waitForAllowance(to: url)
            if !allowed {
                throw RateLimitError.rateLimitExceeded(url.host ?? "unknown")
            }
        }
        return try await self.data(from: url)
    }

    /// Perform a data request with rate limiting
    /// - Parameters:
    ///   - request: The URLRequest to execute
    ///   - rateLimited: Whether to apply rate limiting (default: true)
    /// - Returns: The data and response
    func rateLimitedData(for request: URLRequest, rateLimited: Bool = true) async throws -> (Data, URLResponse) {
        if rateLimited, let url = request.url {
            let allowed = await RateLimiter.shared.waitForAllowance(to: url)
            if !allowed {
                throw RateLimitError.rateLimitExceeded(url.host ?? "unknown")
            }
        }
        return try await self.data(for: request)
    }
}

// MARK: - Error

enum RateLimitError: Error, LocalizedError {
    case rateLimitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .rateLimitExceeded(let domain):
            return "Too many requests to \(domain). Please wait and try again."
        }
    }
}
