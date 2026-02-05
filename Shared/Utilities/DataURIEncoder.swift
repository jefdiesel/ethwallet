import Foundation

/// Encoder for creating data URIs for ethscription calldata
enum DataURIEncoder {

    // MARK: - Encoding

    /// Encode content as a data URI
    /// - Parameters:
    ///   - content: The raw content data
    ///   - mimeType: MIME type of the content
    ///   - allowDuplicate: If true, adds ESIP-6 rule=esip6 parameter
    ///   - compress: If true, applies ESIP-7 gzip compression
    /// - Returns: Data URI string
    static func encode(
        content: Data,
        mimeType: String,
        allowDuplicate: Bool = false,
        compress: Bool = false
    ) throws -> String {
        // Build the data URI
        var dataURI = "data:\(mimeType)"

        // Add ESIP-6 rule for duplicates
        if allowDuplicate {
            dataURI += ";rule=esip6"
        }

        // Encode content as base64
        let base64Content = content.base64EncodedString()
        dataURI += ";base64,\(base64Content)"

        // Optionally compress (ESIP-7)
        if compress {
            guard let compressedData = gzipCompress(dataURI.data(using: .utf8)!) else {
                throw DataURIError.compressionFailed
            }
            // Return compressed data as hex
            return compressedData.hexString
        }

        return dataURI
    }

    /// Convert a data URI to hex calldata for transaction
    static func toCalldata(_ dataURI: String) -> String {
        guard let data = dataURI.data(using: .utf8) else {
            return "0x"
        }
        return data.hexString
    }

    /// Full encoding pipeline: content -> data URI -> hex calldata
    static func encodeToCalldata(
        content: Data,
        mimeType: String,
        allowDuplicate: Bool = false,
        compress: Bool = false
    ) throws -> String {
        if compress {
            // ESIP-7: gzip the entire data URI, then hex encode
            let dataURI = try encode(
                content: content,
                mimeType: mimeType,
                allowDuplicate: allowDuplicate,
                compress: false
            )
            guard let dataURIBytes = dataURI.data(using: .utf8),
                  let compressed = gzipCompress(dataURIBytes) else {
                throw DataURIError.compressionFailed
            }
            return compressed.hexString
        } else {
            // Standard: data URI -> hex
            let dataURI = try encode(
                content: content,
                mimeType: mimeType,
                allowDuplicate: allowDuplicate,
                compress: false
            )
            return toCalldata(dataURI)
        }
    }

    // MARK: - Decoding

    /// Parse a data URI into its components
    static func parse(_ dataURI: String) -> DataURIComponents? {
        guard dataURI.hasPrefix("data:") else { return nil }

        let withoutPrefix = String(dataURI.dropFirst(5))

        // Find the comma separator
        guard let commaIndex = withoutPrefix.firstIndex(of: ",") else { return nil }

        let metadataPart = String(withoutPrefix[..<commaIndex])
        let dataPart = String(withoutPrefix[withoutPrefix.index(after: commaIndex)...])

        // Parse metadata
        let metadataComponents = metadataPart.split(separator: ";")

        guard let firstComponent = metadataComponents.first else { return nil }

        let mimeType = String(firstComponent)
        var isBase64 = false
        var parameters: [String: String] = [:]

        for component in metadataComponents.dropFirst() {
            let componentStr = String(component)
            if componentStr == "base64" {
                isBase64 = true
            } else if let equalIndex = componentStr.firstIndex(of: "=") {
                let key = String(componentStr[..<equalIndex])
                let value = String(componentStr[componentStr.index(after: equalIndex)...])
                parameters[key] = value
            }
        }

        // Decode data
        let decodedData: Data?
        if isBase64 {
            decodedData = Data(base64Encoded: dataPart)
        } else {
            // URL-encoded or raw
            decodedData = dataPart.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data = decodedData else { return nil }

        return DataURIComponents(
            mimeType: mimeType,
            isBase64: isBase64,
            parameters: parameters,
            data: data
        )
    }

    /// Decode hex calldata back to data URI (if it is one)
    static func decodeCalldata(_ hex: String) -> DataURIComponents? {
        guard let data = HexUtils.decode(hex) else { return nil }

        // Check if it's gzipped (ESIP-7)
        if isGzipped(data), let decompressed = gzipDecompress(data) {
            if let dataURI = String(data: decompressed, encoding: .utf8) {
                return parse(dataURI)
            }
        }

        // Try as plain data URI
        if let dataURI = String(data: data, encoding: .utf8) {
            return parse(dataURI)
        }

        return nil
    }

    // MARK: - Gzip Compression (ESIP-7)

    private static func gzipCompress(_ data: Data) -> Data? {
        // ESIP-7 gzip compression is optional
        // For a full implementation, use a proper gzip library
        // Returning nil indicates compression is not available
        return nil
    }

    private static func gzipDecompress(_ data: Data) -> Data? {
        guard isGzipped(data) else { return nil }

        // ESIP-7 gzip decompression
        // For a full implementation, use a proper gzip library
        // Returning nil indicates decompression is not available
        return nil
    }

    private static func isGzipped(_ data: Data) -> Bool {
        // Gzip magic number: 0x1f 0x8b
        guard data.count >= 2 else { return false }
        return data[0] == 0x1f && data[1] == 0x8b
    }
}

// MARK: - Supporting Types

struct DataURIComponents {
    let mimeType: String
    let isBase64: Bool
    let parameters: [String: String]
    let data: Data

    var isESIP6: Bool {
        parameters["rule"] == "esip6"
    }
}

enum DataURIError: Error, LocalizedError {
    case invalidFormat
    case compressionFailed
    case decodingFailed
    case contentTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid data URI format"
        case .compressionFailed:
            return "Failed to compress data"
        case .decodingFailed:
            return "Failed to decode data"
        case .contentTooLarge:
            return "Content exceeds maximum size (90KB)"
        }
    }
}
