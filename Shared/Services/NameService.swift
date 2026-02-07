import Foundation
import CryptoKit

/// Service for resolving Ethscription names and ENS names to addresses
/// - Ethscription names: stored as ethscriptions with content "data:,{name}"
/// - ENS names: resolved via ENS Registry on Ethereum mainnet
final class NameService {
    static let shared = NameService()

    private let appChainService = AppChainService.shared
    private let ensService = ENSService.shared

    private init() {}

    // MARK: - Name Resolution

    /// Resolve a name to an Ethereum address
    /// Supports both ENS names (.eth) and ethscription names (.eths or no suffix)
    /// - Parameter name: The name to resolve (e.g., "vitalik.eth", "alice", or "alice.eths")
    /// - Returns: The resolved Ethereum address, or nil if not found
    func resolveAddress(for name: String) async throws -> String? {
        // Try ENS first for .eth names
        if ensService.isENSName(name) {
            if let address = try await ensService.resolve(name) {
                return address.lowercased()
            }
            return nil
        }

        // Fallback to ethscription name resolution via AppChain RPC
        let cleanName = normalizeName(name)

        // Create the content string: data:,{name}
        let content = "data:,\(cleanName)"

        // Calculate SHA-256 hash
        guard let contentData = content.data(using: .utf8) else {
            throw NameServiceError.invalidName
        }
        let hash = SHA256.hash(data: contentData)
        let sha = "0x" + hash.compactMap { String(format: "%02x", $0) }.joined()

        // Check if the ethscription exists via AppChain RPC
        if let result = try await appChainService.ethscriptionExists(contentHash: sha),
           result.exists,
           let owner = result.currentOwner {
            return owner.lowercased()
        }

        return nil
    }

    /// Reverse resolve an address to find ethscription names they own
    /// - Parameter address: The Ethereum address
    /// - Returns: List of names owned by this address
    func resolveNames(for address: String) async throws -> [String] {
        // Get owned ethscriptions via AppChain RPC
        let ethscriptions = try await appChainService.getOwnedEthscriptions(
            address: address,
            offset: 0,
            limit: 100
        )

        // Find ethscriptions that are names (content_uri starts with "data:,")
        var names: [String] = []
        for item in ethscriptions {
            if let contentURI = item.contentURI,
               contentURI.hasPrefix("data:,") {
                // Extract the name
                let name = String(contentURI.dropFirst(6)) // Remove "data:,"
                if isValidName(name) {
                    names.append(name)
                }
            }
        }

        return names
    }

    /// Check if a string looks like a name to resolve (not an address)
    /// Supports ENS names (.eth) and ethscription names (.eths or no suffix)
    func isEthscriptionName(_ input: String) -> Bool {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Not an address
        if normalized.hasPrefix("0x") && normalized.count == 42 {
            return false
        }

        // Check if it's an ENS name
        if ensService.isENSName(normalized) {
            return true
        }

        // Accept both "name" and "name.eths" formats for ethscription names
        var name = normalized
        if name.hasSuffix(".eths") {
            name = String(name.dropLast(5))
        }

        return isValidName(name)
    }

    /// Check if a string is specifically an ENS name
    func isENSName(_ input: String) -> Bool {
        return ensService.isENSName(input)
    }

    /// Reverse lookup ENS name for an address
    func resolveENSName(for address: String) async throws -> String? {
        return try await ensService.reverseLookup(address)
    }

    /// Validate a name format
    func isValidName(_ name: String) -> Bool {
        // Names must be alphanumeric, can include hyphens, underscores, dots
        // Length between 1 and 64 characters
        // No spaces
        guard !name.isEmpty && name.count <= 64 else { return false }
        let pattern = "^[a-zA-Z0-9._-]+$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Helpers

    private func normalizeName(_ name: String) -> String {
        var normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
        if normalized.hasSuffix(".eths") {
            normalized = String(normalized.dropLast(5))
        }
        return normalized
    }
}

// MARK: - Errors

enum NameServiceError: Error, LocalizedError {
    case invalidRequest
    case networkError
    case nameNotFound
    case invalidName

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid name service request"
        case .networkError:
            return "Network error while resolving name"
        case .nameNotFound:
            return "Name not found"
        case .invalidName:
            return "Invalid name format"
        }
    }
}

// Note: Now uses AppChainService RPC methods instead of API
