import Foundation
import CryptoKit

// MARK: - EthscriptionName

/// Represents an Ethscription name - a human-readable identifier stored on Ethereum
///
/// Ethscription names are inscribed as plain text with the format `data:,{name}`.
/// The name's identity is determined by the SHA-256 hash of this content.
/// Ownership is determined by the current holder of the ethscription.
///
/// ## How Ethscription Names Work
///
/// 1. **Creation**: A name is "claimed" by sending a transaction with calldata
///    containing the UTF-8 hex encoding of `data:,{name}`
///
/// 2. **Uniqueness**: Only the first valid inscription of a name is recognized.
///    The SHA-256 hash of the content serves as a unique identifier.
///
/// 3. **Ownership**: The current owner of the ethscription owns the name.
///    Names can be transferred like any other ethscription.
///
/// 4. **Resolution**: To find who owns a name, compute the content hash and
///    query the ethscriptions API for the current owner.
///
/// ## Example
///
/// ```swift
/// // Parse a name
/// let name = EthscriptionName("alice")
///
/// // Get the content that would be inscribed
/// print(name.contentURI)  // "data:,alice"
///
/// // Get the SHA-256 hash for API lookups
/// print(name.contentHash)  // "0x..."
///
/// // Resolve the owner
/// let resolver = EthscriptionNameResolver()
/// let owner = try await resolver.resolve(name)
/// ```
public struct EthscriptionName: Sendable {

    /// The normalized name (lowercase, no suffix)
    public let name: String

    /// The original input before normalization
    public let originalInput: String

    // MARK: - Initialization

    /// Create an EthscriptionName from a string
    /// - Parameter input: The name string (e.g., "alice", "alice.eths", "Alice")
    /// - Throws: `EthscriptionNameError.invalidFormat` if the name is invalid
    public init(_ input: String) throws {
        self.originalInput = input
        self.name = try Self.normalize(input)

        guard Self.isValidName(self.name) else {
            throw EthscriptionNameError.invalidFormat(
                "Name contains invalid characters or is too long"
            )
        }
    }

    /// Create an EthscriptionName without validation (internal use)
    internal init(validated name: String, original: String) {
        self.name = name
        self.originalInput = original
    }

    // MARK: - Content Properties

    /// The content URI that would be inscribed for this name
    ///
    /// This is the exact string that gets hex-encoded and sent as transaction calldata
    /// when claiming a name. Format: `data:,{name}`
    public var contentURI: String {
        "data:,\(name)"
    }

    /// The hex-encoded calldata for inscribing this name
    ///
    /// This is what you send as the `data` field in a transaction to claim the name.
    /// The transaction should be sent to your own address (self-inscription).
    public var calldata: String {
        let bytes = Array(contentURI.utf8)
        return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The SHA-256 hash of the content URI
    ///
    /// This hash is used to:
    /// - Check if a name has been claimed (via API)
    /// - Identify the ethscription that represents this name
    public var contentHash: String {
        guard let data = contentURI.data(using: .utf8) else {
            return ""
        }
        let hash = SHA256.hash(data: data)
        return "0x" + hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// The name with `.eths` suffix for display
    public var displayName: String {
        "\(name).eths"
    }

    // MARK: - Validation

    /// Check if a raw string is a valid ethscription name
    /// - Parameter input: The input string to validate
    /// - Returns: `true` if the input can be parsed as a valid name
    public static func isValid(_ input: String) -> Bool {
        guard let normalized = try? normalize(input) else {
            return false
        }
        return isValidName(normalized)
    }

    /// Validate name characters and length
    private static func isValidName(_ name: String) -> Bool {
        // Rules:
        // - Length: 1-64 characters
        // - Characters: alphanumeric, hyphens, underscores, dots
        // - No spaces
        // - Cannot start or end with hyphen/underscore/dot (special chars)
        guard !name.isEmpty && name.count <= 64 else { return false }

        // Single character: must be alphanumeric
        if name.count == 1 {
            return name.range(of: "^[a-z0-9]$", options: .regularExpression) != nil
        }

        // Multiple characters: start/end with alphanumeric, middle can have .-_
        let pattern = "^[a-z0-9][a-z0-9._-]*[a-z0-9]$"
        return name.range(of: pattern, options: .regularExpression) != nil
    }

    /// Normalize a name input
    /// - Converts to lowercase
    /// - Removes `.eths` suffix if present
    /// - Trims whitespace
    private static func normalize(_ input: String) throws -> String {
        var normalized = input.lowercased().trimmingCharacters(in: .whitespaces)

        // Remove .eths suffix if present
        if normalized.hasSuffix(".eths") {
            normalized = String(normalized.dropLast(5))
        }

        guard !normalized.isEmpty else {
            throw EthscriptionNameError.emptyName
        }

        return normalized
    }
}

// MARK: - Codable

extension EthscriptionName: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let input = try container.decode(String.self)
        try self.init(input)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

// MARK: - CustomStringConvertible

extension EthscriptionName: CustomStringConvertible {
    public var description: String {
        displayName
    }
}

// MARK: - Equatable & Hashable

extension EthscriptionName: Equatable {
    public static func == (lhs: EthscriptionName, rhs: EthscriptionName) -> Bool {
        // Two names are equal if their normalized names match
        lhs.name == rhs.name
    }
}

extension EthscriptionName: Hashable {
    public func hash(into hasher: inout Hasher) {
        // Hash only the normalized name to match Equatable
        hasher.combine(name)
    }
}

// Note: ExpressibleByStringLiteral is intentionally not implemented
// because it cannot throw errors for invalid names. Use the throwing
// initializer `try EthscriptionName("...")` instead.
