import Foundation

/// Service for fetching NFT data
final class NFTService {
    static let shared = NFTService()

    private let alchemyApiKey = "aLBw6VuSaJyufMkS2zgEZ"

    private init() {}

    // MARK: - Fetch NFTs

    /// Fetch NFTs owned by an address using Alchemy API
    func getOwnedNFTs(
        address: String,
        chainId: Int = 1,
        apiKey: String? = nil
    ) async throws -> [NFT] {
        let key = apiKey ?? alchemyApiKey

        // Alchemy endpoint based on chain
        let baseURL: String
        switch chainId {
        case 1:
            baseURL = "https://eth-mainnet.g.alchemy.com/nft/v3/\(key)"
        case 11155111:
            baseURL = "https://eth-sepolia.g.alchemy.com/nft/v3/\(key)"
        case 8453:
            baseURL = "https://base-mainnet.g.alchemy.com/nft/v3/\(key)"
        default:
            baseURL = "https://eth-mainnet.g.alchemy.com/nft/v3/\(key)"
        }

        let urlString = "\(baseURL)/getNFTsForOwner?owner=\(address)&withMetadata=true&pageSize=100"
        guard let url = URL(string: urlString) else {
            throw NFTServiceError.invalidURI
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(AlchemyNFTResponse.self, from: data)

        var nfts: [NFT] = []
        for nft in response.ownedNfts {
            // Parse token ID
            let tokenId = nft.tokenId

            // Get image data if available
            var imageData: Data? = nil
            if let imageURL = nft.image?.cachedUrl ?? nft.image?.originalUrl ?? nft.raw?.metadata?.image {
                imageData = try? await fetchImageData(from: imageURL)
            }

            let parsedNFT = NFT(
                contractAddress: nft.contract.address,
                tokenId: tokenId,
                standard: NFTStandard(rawValue: nft.tokenType) ?? .erc721,
                collectionName: nft.contract.name ?? nft.contract.openSeaMetadata?.collectionName,
                name: nft.name ?? nft.raw?.metadata?.name,
                description: nft.description ?? nft.raw?.metadata?.description,
                imageURL: URL(string: nft.image?.cachedUrl ?? nft.image?.originalUrl ?? ""),
                imageData: imageData,
                attributes: nft.raw?.metadata?.attributes?.map { attr in
                    NFTAttribute(traitType: attr.trait_type ?? "", value: attr.value ?? "")
                },
                balance: Int(nft.balance ?? "1") ?? 1,
                chainId: chainId
            )
            nfts.append(parsedNFT)
        }
        return nfts
    }

    private func fetchImageData(from urlString: String) async throws -> Data? {
        var fetchURL: URL?

        if urlString.hasPrefix("ipfs://") {
            let hash = urlString.replacingOccurrences(of: "ipfs://", with: "")
            fetchURL = URL(string: "https://ipfs.io/ipfs/\(hash)")
        } else if urlString.hasPrefix("http") {
            fetchURL = URL(string: urlString)
        }

        guard let url = fetchURL else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    /// Fetch NFT metadata from tokenURI
    func getNFTMetadata(
        contractAddress: String,
        tokenId: String,
        web3Service: Web3Service
    ) async throws -> NFTMetadataResponse {
        // Get tokenURI
        let tokenURI = try await getTokenURI(
            contractAddress: contractAddress,
            tokenId: tokenId,
            web3Service: web3Service
        )

        // Fetch metadata from URI
        return try await fetchMetadata(from: tokenURI)
    }

    /// Get tokenURI from contract
    private func getTokenURI(
        contractAddress: String,
        tokenId: String,
        web3Service: Web3Service
    ) async throws -> String {
        // tokenURI(uint256) selector: 0xc87b56dd
        let selector = "0xc87b56dd"
        guard let tokenIdInt = UInt64(tokenId) else {
            throw NFTServiceError.invalidTokenId
        }
        let paddedTokenId = String(tokenIdInt, radix: 16).leftPadded(to: 64)
        let calldata = selector + paddedTokenId

        let result = try await web3Service.call(to: contractAddress, data: calldata)

        // Decode ABI-encoded string
        guard let uri = decodeString(result) else {
            throw NFTServiceError.invalidMetadata
        }

        return uri
    }

    /// Fetch metadata from URI (HTTP or IPFS)
    private func fetchMetadata(from uri: String) async throws -> NFTMetadataResponse {
        var fetchURL: URL?

        if uri.hasPrefix("ipfs://") {
            // Convert IPFS URI to HTTP gateway
            let ipfsHash = uri.replacingOccurrences(of: "ipfs://", with: "")
            fetchURL = URL(string: "https://ipfs.io/ipfs/\(ipfsHash)")
        } else if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
            fetchURL = URL(string: uri)
        } else if uri.hasPrefix("data:application/json") {
            // Handle data URI
            return try parseDataURI(uri)
        }

        guard let url = fetchURL else {
            throw NFTServiceError.invalidURI
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(NFTMetadataResponse.self, from: data)
    }

    /// Parse data URI containing JSON
    private func parseDataURI(_ uri: String) throws -> NFTMetadataResponse {
        // Handle base64 encoded JSON
        if let range = uri.range(of: ";base64,") {
            let base64Part = String(uri[range.upperBound...])
            guard let data = Data(base64Encoded: base64Part) else {
                throw NFTServiceError.invalidMetadata
            }
            return try JSONDecoder().decode(NFTMetadataResponse.self, from: data)
        }

        // Handle plain JSON
        if let range = uri.range(of: ",") {
            let jsonPart = String(uri[range.upperBound...])
            guard let data = jsonPart.removingPercentEncoding?.data(using: .utf8) else {
                throw NFTServiceError.invalidMetadata
            }
            return try JSONDecoder().decode(NFTMetadataResponse.self, from: data)
        }

        throw NFTServiceError.invalidMetadata
    }

    /// Decode ABI-encoded string
    private func decodeString(_ hex: String) -> String? {
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        guard clean.count >= 128 else { return nil }

        let lengthHex = String(clean.dropFirst(64).prefix(64))
        guard let length = Int(lengthHex, radix: 16), length > 0, length < 10000 else { return nil }

        let dataHex = String(clean.dropFirst(128).prefix(length * 2))
        guard dataHex.count == length * 2 else { return nil }

        var data = Data()
        var index = dataHex.startIndex
        while index < dataHex.endIndex {
            let nextIndex = dataHex.index(index, offsetBy: 2)
            guard let byte = UInt8(dataHex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Alchemy Response Types

struct AlchemyNFTResponse: Codable {
    let ownedNfts: [AlchemyNFT]
    let totalCount: Int?
    let pageKey: String?
}

struct AlchemyNFT: Codable {
    let contract: AlchemyContract
    let tokenId: String
    let tokenType: String
    let name: String?
    let description: String?
    let image: AlchemyImage?
    let raw: AlchemyRaw?
    let balance: String?
}

struct AlchemyContract: Codable {
    let address: String
    let name: String?
    let symbol: String?
    let tokenType: String?
    let openSeaMetadata: AlchemyOpenSeaMetadata?
}

struct AlchemyOpenSeaMetadata: Codable {
    let collectionName: String?
    let collectionSlug: String?
    let floorPrice: Double?
}

struct AlchemyImage: Codable {
    let cachedUrl: String?
    let originalUrl: String?
    let thumbnailUrl: String?
}

struct AlchemyRaw: Codable {
    let metadata: AlchemyMetadata?
}

struct AlchemyMetadata: Codable {
    let name: String?
    let description: String?
    let image: String?
    let attributes: [AlchemyAttribute]?
}

struct AlchemyAttribute: Codable {
    let trait_type: String?
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trait_type = try container.decodeIfPresent(String.self, forKey: .trait_type)
        // Value can be string, int, or double
        if let stringValue = try? container.decode(String.self, forKey: .value) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self, forKey: .value) {
            value = String(intValue)
        } else if let doubleValue = try? container.decode(Double.self, forKey: .value) {
            value = String(doubleValue)
        } else {
            value = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case trait_type, value
    }
}

// MARK: - Response Types

struct NFTMetadataResponse: Codable {
    let name: String?
    let description: String?
    let image: String?
    let attributes: [NFTAttribute]?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case image
        case attributes
    }
}

// MARK: - Errors

enum NFTServiceError: Error, LocalizedError {
    case invalidTokenId
    case invalidURI
    case invalidMetadata
    case fetchFailed

    var errorDescription: String? {
        switch self {
        case .invalidTokenId: return "Invalid token ID"
        case .invalidURI: return "Invalid metadata URI"
        case .invalidMetadata: return "Failed to parse metadata"
        case .fetchFailed: return "Failed to fetch NFT data"
        }
    }
}

// MARK: - Helpers

private extension String {
    func leftPadded(to length: Int, with char: Character = "0") -> String {
        if count >= length { return self }
        return String(repeating: char, count: length - count) + self
    }
}
