// EthscriptionNames
// A Swift package for working with Ethscription names
//
// Ethscription names are human-readable identifiers stored on Ethereum.
// They work similarly to ENS names but use ethscriptions instead of smart contracts.
//
// ## Quick Start
//
// ```swift
// import EthscriptionNames
//
// // Parse and validate a name
// let name = try EthscriptionName("alice")
//
// // Resolve a name to an address
// let resolver = EthscriptionNameResolver()
// let owner = try await resolver.resolve("alice")
//
// // Build a transaction to claim a name
// let tx = try EthscriptionNameTransaction.claim("myname", from: myAddress)
// ```
//
// ## How Ethscription Names Work
//
// 1. **Format**: Names are stored as `data:,{name}` in transaction calldata
// 2. **Uniqueness**: The SHA-256 hash of the content identifies the name
// 3. **First-come-first-serve**: Only the first valid inscription counts
// 4. **Transferable**: Names can be transferred like any ethscription
//
// ## Resources
//
// - Ethscriptions Protocol: https://docs.ethscriptions.com
// - API Documentation: https://api.ethscriptions.com
// - Explorer: https://ethscriptions.com

import Foundation

// MARK: - Convenience Extensions

extension String {

    /// Check if this string is a valid Ethscription name format
    public var isValidEthscriptionName: Bool {
        EthscriptionName.isValid(self)
    }

    /// Parse this string as an Ethscription name
    /// - Returns: The parsed EthscriptionName, or nil if invalid
    public var asEthscriptionName: EthscriptionName? {
        try? EthscriptionName(self)
    }

    /// Check if this string looks like an Ethereum address
    public var isEthereumAddress: Bool {
        let clean = self.lowercased()
        guard clean.hasPrefix("0x") && clean.count == 42 else {
            return false
        }
        let hex = String(clean.dropFirst(2))
        return hex.allSatisfy { $0.isHexDigit }
    }
}

// MARK: - Version

/// The version of the EthscriptionNames package
public let ethscriptionNamesVersion = "1.0.0"
