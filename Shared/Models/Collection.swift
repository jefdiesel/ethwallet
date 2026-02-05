import Foundation

/// Represents an Ethscriptions collection on the AppChain
struct Collection: Identifiable, Codable, Hashable {
    /// The collection contract address on AppChain
    let id: String  // Contract address

    /// Collection name
    let name: String

    /// Collection symbol
    let symbol: String

    /// Total supply of items in collection
    let totalSupply: Int

    /// Collection description
    let description: String?

    /// Collection image URL
    let imageURL: URL?

    /// External website
    let externalURL: URL?

    /// Floor price in ETH (if available)
    var floorPrice: Double?

    // MARK: - Display Helpers

    var shortAddress: String {
        guard id.count >= 10 else { return id }
        let start = id.prefix(6)
        let end = id.suffix(4)
        return "\(start)...\(end)"
    }

    /// URL to view collection on explorer
    var explorerURL: URL? {
        URL(string: "https://explorer.ethscriptions.com/token/\(id)")
    }
}

// MARK: - Collection Membership

struct CollectionMembership: Codable, Hashable {
    /// The collection contract address
    let collectionAddress: String

    /// Token ID within the collection
    let tokenId: String  // uint256 as string

    /// Collection name (cached for display)
    let collectionName: String?

    /// Token number (e.g., #1234)
    var displayNumber: String {
        "#\(tokenId)"
    }

    /// URL to view this specific token on explorer
    var explorerURL: URL? {
        URL(string: "https://explorer.ethscriptions.com/token/\(collectionAddress)/instance/\(tokenId)")
    }
}

// MARK: - Token Metadata

struct TokenMetadata: Codable {
    let name: String?
    let description: String?
    let image: String?  // Could be data URI or URL
    let attributes: [TokenAttribute]?

    struct TokenAttribute: Codable, Hashable {
        let traitType: String
        let value: AttributeValue

        enum CodingKeys: String, CodingKey {
            case traitType = "trait_type"
            case value
        }
    }
}

/// Flexible value type for token attributes
enum AttributeValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case boolean(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode attribute value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .boolean(let value):
            try container.encode(value)
        }
    }

    var displayValue: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(format: "%.2f", value)
        case .boolean(let value): return value ? "Yes" : "No"
        }
    }
}

// MARK: - AppChain Manager Contract

enum AppChainContract {
    /// The manager contract address on Ethscriptions AppChain
    static let managerAddress = "0x3300000000000000000000000000000000000006"

    /// Function selectors
    enum Selector {
        /// getMembershipOfEthscription(bytes32) -> (address, uint256, ...)
        static let getMembership = "0x73a3a428"

        /// tokenURI(uint256) -> string
        static let tokenURI = "0xc87b56dd"

        /// ownerOf(uint256) -> address
        static let ownerOf = "0x6352211e"

        /// balanceOf(address) -> uint256
        static let balanceOf = "0x70a08231"
    }
}
