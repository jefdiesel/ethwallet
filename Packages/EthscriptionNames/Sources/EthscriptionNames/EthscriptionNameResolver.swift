import Foundation

// MARK: - EthscriptionNameResolver

/// Resolves Ethscription names to Ethereum addresses
///
/// The resolver queries the Ethscriptions API to find the current owner
/// of a name by looking up the ethscription with the matching content hash.
///
/// ## Usage
///
/// ```swift
/// let resolver = EthscriptionNameResolver()
///
/// // Resolve a name to an address
/// let owner = try await resolver.resolve("alice")
/// print(owner)  // "0x1234...abcd"
///
/// // Reverse lookup: find names owned by an address
/// let names = try await resolver.reverseResolve("0x1234...abcd")
/// print(names)  // ["alice", "bob"]
/// ```
///
/// ## Caching
///
/// The resolver caches results for 5 minutes to reduce API calls.
/// Use `clearCache()` to force fresh lookups.
public actor EthscriptionNameResolver {

    /// The base URL for the Ethscriptions API
    public let apiBaseURL: String

    /// Cache for resolved names
    private var cache: [String: CachedResult] = [:]

    /// Cache expiry time in seconds (default: 5 minutes)
    public var cacheExpiry: TimeInterval = 300

    /// URLSession for making requests
    private let session: URLSession

    // MARK: - Initialization

    /// Create a resolver with default configuration
    public init() {
        self.apiBaseURL = "https://api.ethscriptions.com/v2"
        self.session = .shared
    }

    /// Create a resolver with custom API URL
    /// - Parameter apiBaseURL: The base URL for the Ethscriptions API
    public init(apiBaseURL: String) {
        self.apiBaseURL = apiBaseURL
        self.session = .shared
    }

    /// Create a resolver with custom configuration
    /// - Parameters:
    ///   - apiBaseURL: The base URL for the Ethscriptions API
    ///   - session: Custom URLSession for requests
    public init(apiBaseURL: String, session: URLSession) {
        self.apiBaseURL = apiBaseURL
        self.session = session
    }

    // MARK: - Resolution

    /// Resolve an Ethscription name to an Ethereum address
    ///
    /// - Parameter name: The name to resolve (e.g., "alice" or "alice.eths")
    /// - Returns: The Ethereum address that owns this name
    /// - Throws: `EthscriptionNameError.nameNotFound` if the name hasn't been claimed
    public func resolve(_ name: String) async throws -> String {
        let ethName = try EthscriptionName(name)
        return try await resolve(ethName)
    }

    /// Resolve an EthscriptionName to an Ethereum address
    ///
    /// - Parameter name: The EthscriptionName to resolve
    /// - Returns: The Ethereum address that owns this name
    /// - Throws: `EthscriptionNameError.nameNotFound` if the name hasn't been claimed
    public func resolve(_ name: EthscriptionName) async throws -> String {
        // Check cache
        let cacheKey = "resolve:\(name.name)"
        if let cached = cache[cacheKey], !isExpired(cached) {
            if let address = cached.value {
                return address
            }
            throw EthscriptionNameError.nameNotFound(name.name)
        }

        // Query API using content hash
        let result = try await lookupByHash(name.contentHash)

        // Cache result
        cache[cacheKey] = CachedResult(value: result?.owner, timestamp: Date())

        guard let owner = result?.owner else {
            throw EthscriptionNameError.nameNotFound(name.name)
        }

        return owner.lowercased()
    }

    /// Check if a name has been claimed
    ///
    /// - Parameter name: The name to check
    /// - Returns: `true` if the name has been claimed, `false` otherwise
    public func exists(_ name: String) async throws -> Bool {
        let ethName = try EthscriptionName(name)
        return try await exists(ethName)
    }

    /// Check if an EthscriptionName has been claimed
    ///
    /// - Parameter name: The EthscriptionName to check
    /// - Returns: `true` if the name has been claimed, `false` otherwise
    public func exists(_ name: EthscriptionName) async throws -> Bool {
        let result = try await lookupByHash(name.contentHash)
        return result != nil
    }

    /// Get full details about a name
    ///
    /// - Parameter name: The name to look up
    /// - Returns: Resolution result with owner and transaction details, or nil if not claimed
    public func lookup(_ name: String) async throws -> NameResolutionResult? {
        let ethName = try EthscriptionName(name)
        return try await lookupByHash(ethName.contentHash)
    }

    // MARK: - Reverse Resolution

    /// Find all Ethscription names owned by an address
    ///
    /// - Parameter address: The Ethereum address to look up
    /// - Returns: Array of names owned by this address
    public func reverseResolve(_ address: String) async throws -> [EthscriptionName] {
        let cleanAddress = address.lowercased()

        // Check cache
        let cacheKey = "reverse:\(cleanAddress)"
        if let cached = cache[cacheKey], !isExpired(cached) {
            if let namesJson = cached.value,
               let data = namesJson.data(using: .utf8),
               let names = try? JSONDecoder().decode([String].self, from: data) {
                return names.compactMap { try? EthscriptionName($0) }
            }
        }

        // Query API for text/plain ethscriptions owned by this address
        guard var urlComponents = URLComponents(string: "\(apiBaseURL)/ethscriptions") else {
            throw EthscriptionNameError.apiUnavailable
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "current_owner", value: cleanAddress),
            URLQueryItem(name: "mimetype", value: "text/plain"),
            URLQueryItem(name: "per_page", value: "100")
        ]

        guard let url = urlComponents.url else {
            throw EthscriptionNameError.apiUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EthscriptionNameError.invalidResponse
        }

        try checkStatusCode(httpResponse.statusCode)

        let apiResponse = try JSONDecoder().decode(EthscriptionsListResponse.self, from: data)

        // Filter to only valid names (content_uri starts with "data:,")
        var names: [EthscriptionName] = []
        for item in apiResponse.result {
            if let contentURI = item.content_uri,
               contentURI.hasPrefix("data:,") {
                let nameString = String(contentURI.dropFirst(6))
                if let name = try? EthscriptionName(nameString) {
                    names.append(name)
                }
            }
        }

        // Cache result
        let namesArray = names.map { $0.name }
        if let jsonData = try? JSONEncoder().encode(namesArray),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            cache[cacheKey] = CachedResult(value: jsonString, timestamp: Date())
        }

        return names
    }

    // MARK: - Cache Management

    /// Clear the resolver cache
    public func clearCache() {
        cache.removeAll()
    }

    /// Remove expired entries from cache
    public func pruneCache() {
        cache = cache.filter { !isExpired($0.value) }
    }

    // MARK: - Private Helpers

    private func lookupByHash(_ hash: String) async throws -> NameResolutionResult? {
        guard let url = URL(string: "\(apiBaseURL)/ethscriptions/exists/\(hash)") else {
            throw EthscriptionNameError.apiUnavailable
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EthscriptionNameError.invalidResponse
        }

        try checkStatusCode(httpResponse.statusCode)

        let apiResponse = try JSONDecoder().decode(NameExistsResponse.self, from: data)

        guard apiResponse.result.exists,
              let ethscription = apiResponse.result.ethscription else {
            return nil
        }

        return NameResolutionResult(
            owner: ethscription.current_owner,
            transactionHash: ethscription.transaction_hash,
            contentHash: hash
        )
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw EthscriptionNameError.networkError(error.localizedDescription)
        }
    }

    private func checkStatusCode(_ statusCode: Int) throws {
        switch statusCode {
        case 200...299:
            return
        case 429:
            throw EthscriptionNameError.rateLimited
        case 500...599:
            throw EthscriptionNameError.apiUnavailable
        default:
            throw EthscriptionNameError.networkError("HTTP \(statusCode)")
        }
    }

    private func isExpired(_ cached: CachedResult) -> Bool {
        Date().timeIntervalSince(cached.timestamp) > cacheExpiry
    }
}

// MARK: - Resolution Result

/// Result of resolving an Ethscription name
public struct NameResolutionResult: Sendable {
    /// The current owner's Ethereum address
    public let owner: String

    /// The transaction hash that created this name
    public let transactionHash: String

    /// The SHA-256 content hash
    public let contentHash: String
}

// MARK: - Private Types

private struct CachedResult {
    let value: String?
    let timestamp: Date
}

// MARK: - API Response Types

private struct NameExistsResponse: Codable {
    let result: NameExistsResult
}

private struct NameExistsResult: Codable {
    let exists: Bool
    let ethscription: NameEthscription?
}

private struct NameEthscription: Codable {
    let transaction_hash: String
    let current_owner: String
}

private struct EthscriptionsListResponse: Codable {
    let result: [EthscriptionItem]
}

private struct EthscriptionItem: Codable {
    let transaction_hash: String
    let current_owner: String
    let content_uri: String?
}
