import Foundation

/// Represents an Ethscription - data inscribed on Ethereum via calldata
struct Ethscription: Identifiable, Codable, Hashable {
    /// The transaction hash that created this ethscription (also serves as ID)
    let id: String  // 0x + 64 hex chars

    /// The address that created the ethscription
    let creator: String

    /// The current owner address
    var owner: String

    /// The content hash (SHA256 of the content)
    let contentHash: String

    /// MIME type of the content
    let mimeType: String

    /// The content URI (data URI with the actual content)
    let contentURI: String?

    /// Content size in bytes
    let contentSize: Int

    /// Block number when created
    let blockNumber: Int

    /// Timestamp when created
    let createdAt: Date

    /// Collection information if part of a collection
    var collection: CollectionMembership?

    /// Whether this is a duplicate (ESIP-6)
    let isDuplicate: Bool

    // MARK: - Display Helpers

    var shortId: String {
        guard id.count >= 10 else { return id }
        let start = id.prefix(6)
        let end = id.suffix(4)
        return "\(start)...\(end)"
    }

    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    var isText: Bool {
        mimeType.hasPrefix("text/") || mimeType == "application/json"
    }

    /// URL to view on Ethscriptions explorer
    var explorerURL: URL? {
        URL(string: "https://explorer.ethscriptions.com/ethscriptions/\(id)")
    }

    /// Decoded text content (for text/plain ethscriptions)
    var textContent: String? {
        guard let uri = contentURI else { return nil }

        // Handle "data:,content" format (simple text)
        if uri.hasPrefix("data:,") {
            return String(uri.dropFirst(6))
        }

        // Handle "data:text/plain;base64,..." format
        if let range = uri.range(of: ";base64,") {
            let base64Part = String(uri[range.upperBound...])
            if let data = Data(base64Encoded: base64Part),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }

        // Handle "data:text/plain," format (URL encoded)
        if let range = uri.range(of: "data:text/plain,") {
            let textPart = String(uri[range.upperBound...])
            return textPart.removingPercentEncoding ?? textPart
        }

        return nil
    }

    /// Image data (for image ethscriptions)
    var imageData: Data? {
        guard let uri = contentURI, isImage else { return nil }

        // Handle base64 encoded images
        if let range = uri.range(of: ";base64,") {
            let base64Part = String(uri[range.upperBound...])
            return Data(base64Encoded: base64Part)
        }

        return nil
    }
}

// MARK: - Content Types

enum EthscriptionContentType: String, CaseIterable {
    case png = "image/png"
    case gif = "image/gif"
    case jpeg = "image/jpeg"
    case webp = "image/webp"
    case svg = "image/svg+xml"
    case plainText = "text/plain"
    case html = "text/html"
    case json = "application/json"

    var displayName: String {
        switch self {
        case .png: return "PNG Image"
        case .gif: return "GIF Animation"
        case .jpeg: return "JPEG Image"
        case .webp: return "WebP Image"
        case .svg: return "SVG Image"
        case .plainText: return "Plain Text"
        case .html: return "HTML"
        case .json: return "JSON"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .gif: return "gif"
        case .jpeg: return "jpg"
        case .webp: return "webp"
        case .svg: return "svg"
        case .plainText: return "txt"
        case .html: return "html"
        case .json: return "json"
        }
    }
}

// MARK: - Creation Options

struct EthscriptionCreationOptions {
    var content: Data
    var mimeType: String
    var recipient: String  // Address to send to (self for inscribing to own address)
    var allowDuplicate: Bool  // ESIP-6
    var compress: Bool  // ESIP-7 gzip compression

    /// Maximum size for ethscription content (90KB)
    static let maxContentSize = 90 * 1024

    var isValidSize: Bool {
        content.count <= Self.maxContentSize
    }

    var estimatedCalldataSize: Int {
        // Base64 encoding increases size by ~33%
        let base64Size = (content.count * 4 + 2) / 3
        // Add data URI prefix overhead
        let prefixSize = "data:\(mimeType);base64,".count
        return base64Size + prefixSize
    }
}

// MARK: - Transfer Types

enum EthscriptionTransfer {
    /// Single ethscription transfer
    case single(ethscriptionId: String, to: String)

    /// ESIP-5 bulk transfer (multiple ethscriptions to same recipient)
    case bulk(ethscriptionIds: [String], to: String)

    var recipient: String {
        switch self {
        case .single(_, let to), .bulk(_, let to):
            return to
        }
    }

    var calldata: String {
        switch self {
        case .single(let id, _):
            return id
        case .bulk(let ids, _):
            // ESIP-5: concatenate IDs without 0x prefix
            return "0x" + ids.map { $0.dropFirst(2) }.joined()
        }
    }
}
