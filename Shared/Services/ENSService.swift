import Foundation
import BigInt
import CryptoKit

/// Service for resolving ENS (Ethereum Name Service) names
/// Supports forward resolution (.eth names to addresses) and reverse resolution
final class ENSService {
    static let shared = ENSService()

    /// ENS Registry contract address (same on all networks)
    private let registryAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e"

    /// ENS Public Resolver address (mainnet)
    private let publicResolverAddress = "0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63"

    /// Reverse registrar base domain
    private let reverseRegistrarSuffix = ".addr.reverse"

    /// Cache for resolved names (expires after 5 minutes)
    private var cache: [String: CachedResult] = [:]
    private let cacheExpiry: TimeInterval = 300 // 5 minutes

    private var web3Service: Web3Service

    private init() {
        self.web3Service = Web3Service()
    }

    // MARK: - Public API

    /// Resolve an ENS name to an Ethereum address
    /// - Parameter name: The ENS name (e.g., "vitalik.eth")
    /// - Returns: The resolved Ethereum address, or nil if not found
    func resolve(_ name: String) async throws -> String? {
        guard isENSName(name) else {
            return nil
        }

        // Check cache
        let cacheKey = "forward:\(name.lowercased())"
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.value
        }

        // Compute namehash
        let node = namehash(name.lowercased())

        // Get resolver address
        guard let resolverAddress = try await getResolver(node: node) else {
            return nil
        }

        // Call resolver's addr(bytes32) function
        let address = try await resolveAddress(node: node, resolver: resolverAddress)

        // Cache result
        cache[cacheKey] = CachedResult(value: address, timestamp: Date())

        return address
    }

    /// Reverse lookup: get ENS name for an address
    /// - Parameter address: The Ethereum address
    /// - Returns: The primary ENS name, or nil if not set
    func reverseLookup(_ address: String) async throws -> String? {
        let cleanAddress = address.lowercased().replacingOccurrences(of: "0x", with: "")

        // Check cache
        let cacheKey = "reverse:\(cleanAddress)"
        if let cached = cache[cacheKey], !cached.isExpired {
            return cached.value
        }

        // Compute reverse record node
        let reverseName = "\(cleanAddress)\(reverseRegistrarSuffix)"
        let node = namehash(reverseName)

        // Get resolver for reverse record
        guard let resolverAddress = try await getResolver(node: node) else {
            return nil
        }

        // Call resolver's name(bytes32) function
        let name = try await resolveName(node: node, resolver: resolverAddress)

        // Cache result
        cache[cacheKey] = CachedResult(value: name, timestamp: Date())

        return name
    }

    /// Check if a string is an ENS name
    func isENSName(_ input: String) -> Bool {
        let normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Must end with .eth (or other supported TLDs)
        guard normalized.hasSuffix(".eth") else {
            return false
        }

        // Must have at least one character before .eth
        let name = String(normalized.dropLast(4))
        guard !name.isEmpty else {
            return false
        }

        // Valid characters: alphanumeric, hyphens, underscores
        let pattern = "^[a-z0-9-_]+$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// Switch the network for the service
    func switchNetwork(_ network: Network) {
        self.web3Service = Web3Service(network: network)
        // Clear cache when switching networks
        cache.removeAll()
    }

    // MARK: - ENS Resolution

    private func getResolver(node: String) async throws -> String? {
        // resolver(bytes32) selector: 0x0178b8bf
        let calldata = "0x0178b8bf" + node.replacingOccurrences(of: "0x", with: "")

        let result = try await web3Service.call(to: registryAddress, data: calldata)

        // Parse address from result (last 40 hex chars)
        let clean = result.replacingOccurrences(of: "0x", with: "")
        guard clean.count >= 40 else { return nil }

        let addressHex = String(clean.suffix(40))
        let address = "0x" + addressHex

        // Check if resolver is set (not zero address)
        if address == "0x0000000000000000000000000000000000000000" {
            return nil
        }

        return address
    }

    private func resolveAddress(node: String, resolver: String) async throws -> String? {
        // addr(bytes32) selector: 0x3b3b57de
        let calldata = "0x3b3b57de" + node.replacingOccurrences(of: "0x", with: "")

        let result = try await web3Service.call(to: resolver, data: calldata)

        // Parse address from result
        let clean = result.replacingOccurrences(of: "0x", with: "")
        guard clean.count >= 40 else { return nil }

        let addressHex = String(clean.suffix(40))
        let address = "0x" + addressHex

        // Check if address is set (not zero address)
        if address == "0x0000000000000000000000000000000000000000" {
            return nil
        }

        return address
    }

    private func resolveName(node: String, resolver: String) async throws -> String? {
        // name(bytes32) selector: 0x691f3431
        let calldata = "0x691f3431" + node.replacingOccurrences(of: "0x", with: "")

        let result = try await web3Service.call(to: resolver, data: calldata)

        // Parse string from result (ABI-encoded string)
        return decodeString(result)
    }

    // MARK: - Namehash

    /// Compute the namehash of an ENS name
    /// https://docs.ens.domains/contract-api-reference/name-processing#algorithm
    func namehash(_ name: String) -> String {
        var node = Data(repeating: 0, count: 32)

        if !name.isEmpty {
            let labels = name.split(separator: ".").reversed()

            for label in labels {
                // Hash the label
                let labelData = String(label).data(using: .utf8)!
                let labelHash = SHA256.hash(data: labelData)

                // Concatenate current node with label hash and hash again
                var combined = node
                combined.append(contentsOf: labelHash)
                node = Data(SHA256.hash(data: combined))
            }
        }

        return "0x" + node.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func decodeString(_ hex: String) -> String? {
        // ABI-encoded string: offset (32 bytes) + length (32 bytes) + data
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        guard clean.count >= 128 else { return nil }

        // Get length from second 32-byte word
        let lengthHex = String(clean.dropFirst(64).prefix(64))
        guard let length = Int(lengthHex, radix: 16), length > 0 else { return nil }

        // Get string data
        let dataHex = String(clean.dropFirst(128).prefix(length * 2))
        guard let data = Data(hexString: dataHex) else { return nil }

        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Cache

private struct CachedResult {
    let value: String?
    let timestamp: Date

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > 300 // 5 minutes
    }
}

// MARK: - Data Extension

private extension Data {
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
