import Foundation

/// Represents an NFT (ERC-721 or ERC-1155)
struct NFT: Identifiable, Codable, Hashable {
    /// Unique identifier (contract:tokenId)
    var id: String { "\(contractAddress):\(tokenId)" }

    /// Contract address
    let contractAddress: String

    /// Token ID
    let tokenId: String

    /// Token standard
    let standard: NFTStandard

    /// Collection/contract name
    let collectionName: String?

    /// NFT name
    let name: String?

    /// NFT description
    let description: String?

    /// Image URL (from metadata)
    let imageURL: URL?

    /// Raw image data (if available)
    var imageData: Data?

    /// Metadata attributes/traits
    let attributes: [NFTAttribute]?

    /// Amount owned (for ERC-1155)
    let balance: Int

    /// Chain ID
    let chainId: Int

    // MARK: - Display Helpers

    var displayName: String {
        name ?? "Token #\(tokenId)"
    }

    var shortTokenId: String {
        if tokenId.count > 10 {
            return "\(tokenId.prefix(6))..."
        }
        return tokenId
    }
}

enum NFTStandard: String, Codable {
    case erc721 = "ERC-721"
    case erc1155 = "ERC-1155"
}

struct NFTAttribute: Codable, Hashable {
    let traitType: String
    let value: String
    let displayType: String?

    enum CodingKeys: String, CodingKey {
        case traitType = "trait_type"
        case value
        case displayType = "display_type"
    }

    init(traitType: String, value: String, displayType: String? = nil) {
        self.traitType = traitType
        self.value = value
        self.displayType = displayType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        traitType = try container.decode(String.self, forKey: .traitType)
        // Value can be string, number, etc - convert to string
        if let stringValue = try? container.decode(String.self, forKey: .value) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self, forKey: .value) {
            value = String(doubleValue)
        } else {
            value = ""
        }
        displayType = try container.decodeIfPresent(String.self, forKey: .displayType)
    }
}

/// NFT collection info
struct NFTCollection: Identifiable, Codable {
    let address: String
    let name: String
    let symbol: String?
    let imageURL: URL?
    let totalSupply: Int?
    let floorPrice: Double?

    var id: String { address }
}
