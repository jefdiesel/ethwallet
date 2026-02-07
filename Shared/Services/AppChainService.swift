import Foundation

/// Service for interacting with the Ethscriptions AppChain L2
final class AppChainService {
    static let shared = AppChainService()

    private let rpcURL = URL(string: "https://mainnet.ethscriptions.com")!
    private let managerContract = AppChainContract.managerAddress

    private init() {}

    // MARK: - Collection Queries

    /// Get collection membership for an ethscription
    /// - Parameter ethscriptionId: The ethscription ID (transaction hash)
    /// - Returns: Collection info if the ethscription belongs to a collection
    func getEthscriptionCollection(_ ethscriptionId: String) async throws -> CollectionMembership? {
        // Build calldata: getMembershipOfEthscription(bytes32)
        let selector = AppChainContract.Selector.getMembership
        let paddedId = padHex(ethscriptionId, to: 64)
        let calldata = selector + paddedId

        let result = try await ethCall(to: managerContract, data: calldata)

        // Decode result: (address collectionContract, uint256 tokenId, ...)
        // If collection address is zero, ethscription is not in a collection
        guard let collectionAddress = ABIEncoder.decodeAddress(result),
              collectionAddress != "0x0000000000000000000000000000000000000000" else {
            return nil
        }

        // Get token ID (second 32-byte word)
        let tokenIdHex = String(result.dropFirst(2).dropFirst(64).prefix(64))
        guard let tokenId = UInt64(tokenIdHex, radix: 16) else {
            return nil
        }

        // Try to get collection name
        let collectionName = try? await getCollectionName(collectionAddress)

        return CollectionMembership(
            collectionAddress: collectionAddress,
            tokenId: String(tokenId),
            collectionName: collectionName
        )
    }

    /// Get token metadata for a collection item
    /// - Parameters:
    ///   - collectionAddress: The collection contract address
    ///   - tokenId: The token ID within the collection
    /// - Returns: Token metadata including traits
    func getTokenMetadata(collection: String, tokenId: String) async throws -> TokenMetadata {
        // Build calldata: tokenURI(uint256)
        let selector = AppChainContract.Selector.tokenURI
        let paddedTokenId = padHex(tokenId, to: 64)
        let calldata = selector + paddedTokenId

        let result = try await ethCall(to: collection, data: calldata)

        // Decode the ABI-encoded string
        guard let tokenURI = ABIEncoder.decodeString(result) else {
            throw AppChainError.invalidResponse
        }

        // Parse the data URI (usually base64-encoded JSON)
        return try parseTokenURI(tokenURI)
    }

    /// Get collection name from contract
    func getCollectionName(_ collectionAddress: String) async throws -> String {
        // name() function selector
        let selector = "0x06fdde03"

        let result = try await ethCall(to: collectionAddress, data: selector)
        return ABIEncoder.decodeString(result) ?? "Unknown Collection"
    }

    /// Get collection symbol from contract
    func getCollectionSymbol(_ collectionAddress: String) async throws -> String {
        // symbol() function selector
        let selector = "0x95d89b41"

        let result = try await ethCall(to: collectionAddress, data: selector)
        return ABIEncoder.decodeString(result) ?? ""
    }

    /// Get total supply of a collection
    func getCollectionTotalSupply(_ collectionAddress: String) async throws -> UInt64 {
        // totalSupply() function selector
        let selector = "0x18160ddd"

        let result = try await ethCall(to: collectionAddress, data: selector)
        return ABIEncoder.decodeUInt256(result) ?? 0
    }

    // MARK: - Ownership Queries

    /// Get the owner of a token in a collection
    func getTokenOwner(collection: String, tokenId: String) async throws -> String {
        // ownerOf(uint256) function selector
        let selector = AppChainContract.Selector.ownerOf
        let paddedTokenId = padHex(tokenId, to: 64)
        let calldata = selector + paddedTokenId

        let result = try await ethCall(to: collection, data: calldata)

        guard let owner = ABIEncoder.decodeAddress(result) else {
            throw AppChainError.invalidResponse
        }

        return owner
    }

    /// Get the number of tokens owned by an address in a collection
    func getBalance(of address: String, in collection: String) async throws -> UInt64 {
        // balanceOf(address) function selector
        let selector = AppChainContract.Selector.balanceOf
        let paddedAddress = padHex(address, to: 64)
        let calldata = selector + paddedAddress

        let result = try await ethCall(to: collection, data: calldata)
        return ABIEncoder.decodeUInt256(result) ?? 0
    }

    // MARK: - Ethscription Queries

    /// Get ethscriptions owned by an address via AppChain RPC
    func getOwnedEthscriptions(
        address: String,
        offset: Int = 0,
        limit: Int = 50
    ) async throws -> [Ethscription] {
        // Use AppChain's native RPC method for querying owned ethscriptions
        let result = try await appChainRPC(
            method: "ethscriptions_getEthscriptionsByOwner",
            params: [address.lowercased(), offset, limit]
        )

        guard let items = result as? [[String: Any]] else {
            // Fallback: empty result if method not available
            print("[AppChain] ethscriptions_getEthscriptionsByOwner returned unexpected format")
            return []
        }

        return items.compactMap { item -> Ethscription? in
            guard let txHash = item["transaction_hash"] as? String ?? item["transactionHash"] as? String,
                  let owner = item["current_owner"] as? String ?? item["currentOwner"] as? String else {
                return nil
            }

            let timestamp: Date
            if let ts = item["block_timestamp"] as? String ?? item["blockTimestamp"] as? String,
               let unixTime = Double(ts) {
                timestamp = Date(timeIntervalSince1970: unixTime)
            } else if let unixTime = item["block_timestamp"] as? Double ?? item["blockTimestamp"] as? Double {
                timestamp = Date(timeIntervalSince1970: unixTime)
            } else {
                timestamp = Date()
            }

            let blockNum: Int
            if let blockStr = item["block_number"] as? String ?? item["blockNumber"] as? String {
                blockNum = Int(blockStr) ?? 0
            } else if let blockInt = item["block_number"] as? Int ?? item["blockNumber"] as? Int {
                blockNum = blockInt
            } else {
                blockNum = 0
            }

            return Ethscription(
                id: txHash,
                creator: item["creator"] as? String ?? "",
                owner: owner,
                contentHash: item["content_sha"] as? String ?? item["contentSha"] as? String ?? "",
                mimeType: item["mimetype"] as? String ?? item["mimeType"] as? String ?? "application/octet-stream",
                contentURI: item["content_uri"] as? String ?? item["contentUri"] as? String,
                contentSize: (item["content_uri"] as? String ?? item["contentUri"] as? String)?.count ?? 0,
                blockNumber: blockNum,
                createdAt: timestamp,
                collection: nil,
                isDuplicate: false
            )
        }
    }

    /// Check if an ethscription exists by its content hash via AppChain RPC
    func ethscriptionExists(contentHash: String) async throws -> EthscriptionExistsResult? {
        let result = try await appChainRPC(
            method: "ethscriptions_exists",
            params: [contentHash]
        )

        guard let dict = result as? [String: Any] else {
            return nil
        }

        let exists = dict["exists"] as? Bool ?? false
        guard exists,
              let ethscription = dict["ethscription"] as? [String: Any],
              let txHash = ethscription["transaction_hash"] as? String ?? ethscription["transactionHash"] as? String,
              let owner = ethscription["current_owner"] as? String ?? ethscription["currentOwner"] as? String else {
            return EthscriptionExistsResult(exists: false, transactionHash: nil, currentOwner: nil)
        }

        return EthscriptionExistsResult(exists: true, transactionHash: txHash, currentOwner: owner)
    }

    // MARK: - RPC Helpers

    /// Make a custom RPC call to the AppChain
    func appChainRPC(method: String, params: [Any]) async throws -> Any {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppChainError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AppChainError.invalidResponse
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AppChainError.rpcError(message)
        }

        return json["result"] ?? NSNull()
    }

    private func ethCall(to: String, data: String) async throws -> String {
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_call",
            "params": [
                ["to": to, "data": data],
                "latest"
            ],
            "id": 1
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppChainError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw AppChainError.invalidResponse
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw AppChainError.rpcError(message)
        }

        guard let result = json["result"] as? String else {
            throw AppChainError.invalidResponse
        }

        return result
    }

    private func padHex(_ hex: String, to length: Int) -> String {
        var clean = hex.lowercased()
        if clean.hasPrefix("0x") {
            clean = String(clean.dropFirst(2))
        }

        if clean.count >= length {
            return String(clean.suffix(length))
        }

        return String(repeating: "0", count: length - clean.count) + clean
    }

    private func parseTokenURI(_ uri: String) throws -> TokenMetadata {
        // Handle data URIs
        if uri.hasPrefix("data:") {
            guard let components = DataURIEncoder.parse(uri) else {
                throw AppChainError.invalidTokenURI
            }

            // Decode JSON
            return try JSONDecoder().decode(TokenMetadata.self, from: components.data)
        }

        // Handle HTTP URLs (would need to fetch)
        if uri.hasPrefix("http") {
            throw AppChainError.externalURINotSupported
        }

        throw AppChainError.invalidTokenURI
    }
}

// MARK: - Errors

enum AppChainError: Error, LocalizedError {
    case httpError
    case invalidResponse
    case rpcError(String)
    case invalidTokenURI
    case externalURINotSupported

    var errorDescription: String? {
        switch self {
        case .httpError:
            return "HTTP request failed"
        case .invalidResponse:
            return "Invalid response from AppChain"
        case .rpcError(let message):
            return "RPC error: \(message)"
        case .invalidTokenURI:
            return "Invalid token URI format"
        case .externalURINotSupported:
            return "External URI fetching not supported"
        }
    }
}

// MARK: - RPC Response Types

struct EthscriptionExistsResult {
    let exists: Bool
    let transactionHash: String?
    let currentOwner: String?
}

// MARK: - Explorer URLs

extension AppChainService {
    /// Get explorer URL for an ethscription
    func explorerURL(for ethscriptionId: String) -> URL? {
        URL(string: "https://explorer.ethscriptions.com/ethscriptions/\(ethscriptionId)")
    }

    /// Get explorer URL for a collection token
    func explorerURL(collection: String, tokenId: String) -> URL? {
        URL(string: "https://explorer.ethscriptions.com/token/\(collection)/instance/\(tokenId)")
    }

    /// Get explorer URL for a collection
    func explorerURL(collection: String) -> URL? {
        URL(string: "https://explorer.ethscriptions.com/token/\(collection)")
    }
}
