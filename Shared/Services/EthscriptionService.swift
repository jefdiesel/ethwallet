import Foundation
import web3swift
import Web3Core
import BigInt

/// Service for creating and transferring ethscriptions
final class EthscriptionService {
    private let web3Service: Web3Service
    private let appChainService: AppChainService

    /// Maximum content size for ethscriptions (90KB)
    static let maxContentSize = 90 * 1024

    init(web3Service: Web3Service, appChainService: AppChainService = .shared) {
        self.web3Service = web3Service
        self.appChainService = appChainService
    }

    // MARK: - Create Ethscription

    /// Create an ethscription from content
    /// - Parameters:
    ///   - content: The raw content data
    ///   - mimeType: MIME type of the content
    ///   - recipient: Address to send to (use sender's address to inscribe to self)
    ///   - allowDuplicate: Allow duplicate content (ESIP-6)
    ///   - compress: Use gzip compression (ESIP-7)
    ///   - from: Sender address
    ///   - privateKey: Private key for signing
    /// - Returns: Transaction hash of the created ethscription
    func createEthscription(
        content: Data,
        mimeType: String,
        recipient: String,
        allowDuplicate: Bool = false,
        compress: Bool = false,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // Validate content size
        guard content.count <= Self.maxContentSize else {
            throw EthscriptionError.contentTooLarge
        }

        // Encode as calldata
        let calldata = try DataURIEncoder.encodeToCalldata(
            content: content,
            mimeType: mimeType,
            allowDuplicate: allowDuplicate,
            compress: compress
        )

        // Convert hex calldata to Data
        guard let calldataBytes = HexUtils.decode(calldata) else {
            throw EthscriptionError.encodingFailed
        }

        // Build transaction (0-value transfer with calldata)
        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: recipient,
            value: 0,
            data: calldataBytes
        )

        // Sign and send
        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    /// Create an ethscription from a file URL
    func createEthscriptionFromFile(
        fileURL: URL,
        recipient: String,
        allowDuplicate: Bool = false,
        compress: Bool = false,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // Read file data
        let data = try Data(contentsOf: fileURL)

        // Determine MIME type from file extension
        let mimeType = mimeTypeForExtension(fileURL.pathExtension)

        return try await createEthscription(
            content: data,
            mimeType: mimeType,
            recipient: recipient,
            allowDuplicate: allowDuplicate,
            compress: compress,
            from: from,
            privateKey: privateKey
        )
    }

    /// Create a text ethscription
    func createTextEthscription(
        text: String,
        recipient: String,
        allowDuplicate: Bool = false,
        from: String,
        privateKey: Data
    ) async throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw EthscriptionError.encodingFailed
        }

        return try await createEthscription(
            content: data,
            mimeType: "text/plain",
            recipient: recipient,
            allowDuplicate: allowDuplicate,
            compress: false,
            from: from,
            privateKey: privateKey
        )
    }

    // MARK: - Raw Mode Ethscription

    /// Create an ethscription with raw calldata (no data URI encoding)
    /// Use this for content that is already properly formatted (e.g., "data:,name")
    /// - Parameters:
    ///   - rawCalldata: The raw content to be hex-encoded as calldata
    ///   - recipient: Address to send to
    ///   - from: Sender address
    ///   - privateKey: Private key for signing
    /// - Returns: Transaction hash
    func createRawEthscription(
        rawCalldata: Data,
        recipient: String,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // Validate content size
        guard rawCalldata.count <= Self.maxContentSize else {
            throw EthscriptionError.contentTooLarge
        }

        // Build transaction with raw calldata (directly hex encoded)
        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: recipient,
            value: 0,
            data: rawCalldata
        )

        // Sign and send
        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    // MARK: - Transfer Ethscription

    /// Transfer a single ethscription
    /// - Parameters:
    ///   - ethscriptionId: The ethscription ID (creation transaction hash)
    ///   - to: Recipient address
    ///   - from: Sender address
    ///   - privateKey: Private key for signing
    /// - Returns: Transaction hash
    func transferEthscription(
        ethscriptionId: String,
        to recipient: String,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // Validate ethscription ID format
        guard HexUtils.isValidTxHash(ethscriptionId) else {
            throw EthscriptionError.invalidEthscriptionId
        }

        // Calldata is the ethscription ID (32 bytes)
        guard let calldataBytes = HexUtils.decode(ethscriptionId) else {
            throw EthscriptionError.invalidEthscriptionId
        }

        // Build 0-value transaction with ethscription ID as calldata
        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: recipient,
            value: 0,
            data: calldataBytes
        )

        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    /// Bulk transfer multiple ethscriptions (ESIP-5)
    /// - Parameters:
    ///   - ethscriptionIds: Array of ethscription IDs to transfer
    ///   - to: Recipient address
    ///   - from: Sender address
    ///   - privateKey: Private key for signing
    /// - Returns: Transaction hash
    func bulkTransferEthscriptions(
        ethscriptionIds: [String],
        to recipient: String,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // Validate all IDs
        for id in ethscriptionIds {
            guard HexUtils.isValidTxHash(id) else {
                throw EthscriptionError.invalidEthscriptionId
            }
        }

        // ESIP-5: Concatenate IDs without 0x prefix
        let concatenatedIds = ethscriptionIds.map { id -> String in
            if id.hasPrefix("0x") {
                return String(id.dropFirst(2))
            }
            return id
        }.joined()

        let calldata = "0x" + concatenatedIds

        guard let calldataBytes = HexUtils.decode(calldata) else {
            throw EthscriptionError.encodingFailed
        }

        // Build 0-value transaction
        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: recipient,
            value: 0,
            data: calldataBytes
        )

        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    // MARK: - Gas Estimation

    /// Estimate gas for creating an ethscription
    func estimateCreateGas(
        content: Data,
        mimeType: String,
        recipient: String,
        allowDuplicate: Bool = false,
        compress: Bool = false,
        from: String
    ) async throws -> GasEstimate {
        let calldata = try DataURIEncoder.encodeToCalldata(
            content: content,
            mimeType: mimeType,
            allowDuplicate: allowDuplicate,
            compress: compress
        )

        guard let calldataBytes = HexUtils.decode(calldata) else {
            throw EthscriptionError.encodingFailed
        }

        let request = TransactionRequest(
            from: from,
            to: recipient,
            value: 0,
            data: calldataBytes,
            chainId: web3Service.network.id
        )

        let gasLimit = try await web3Service.estimateGas(for: request)
        let gasPrice = try await web3Service.getGasPrice()

        return GasEstimate(
            gasLimit: gasLimit,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice / 10,
            estimatedCost: gasLimit * gasPrice
        )
    }

    /// Estimate gas for transferring an ethscription
    func estimateTransferGas(
        ethscriptionId: String,
        to recipient: String,
        from: String
    ) async throws -> GasEstimate {
        guard let calldataBytes = HexUtils.decode(ethscriptionId) else {
            throw EthscriptionError.invalidEthscriptionId
        }

        let request = TransactionRequest(
            from: from,
            to: recipient,
            value: 0,
            data: calldataBytes,
            chainId: web3Service.network.id
        )

        let gasLimit = try await web3Service.estimateGas(for: request)
        let gasPrice = try await web3Service.getGasPrice()

        return GasEstimate(
            gasLimit: gasLimit,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice / 10,
            estimatedCost: gasLimit * gasPrice
        )
    }

    /// Estimate gas for creating a raw ethscription (no data URI encoding)
    func estimateRawCreateGas(
        rawCalldata: Data,
        recipient: String,
        from: String
    ) async throws -> GasEstimate {
        let request = TransactionRequest(
            from: from,
            to: recipient,
            value: 0,
            data: rawCalldata,
            chainId: web3Service.network.id
        )

        let gasLimit = try await web3Service.estimateGas(for: request)
        let gasPrice = try await web3Service.getGasPrice()

        return GasEstimate(
            gasLimit: gasLimit,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice / 10,
            estimatedCost: gasLimit * gasPrice
        )
    }

    // MARK: - Validation

    /// Validate content for ethscription creation
    func validateContent(_ content: Data, mimeType: String) -> ContentValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Check size
        if content.count > Self.maxContentSize {
            errors.append("Content size (\(content.count) bytes) exceeds maximum (\(Self.maxContentSize) bytes)")
        }

        // Check MIME type
        let supportedTypes = EthscriptionContentType.allCases.map { $0.rawValue }
        if !supportedTypes.contains(mimeType) {
            warnings.append("MIME type '\(mimeType)' may not be widely supported")
        }

        // Estimate calldata size
        let estimatedSize = (content.count * 4 + 2) / 3 + "data:\(mimeType);base64,".count
        if estimatedSize > 120_000 {
            warnings.append("Calldata is large (\(estimatedSize) bytes), gas costs will be high")
        }

        return ContentValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            estimatedCalldataSize: estimatedSize
        )
    }

    // MARK: - Helpers

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "txt":
            return "text/plain"
        case "html", "htm":
            return "text/html"
        case "json":
            return "application/json"
        default:
            return "application/octet-stream"
        }
    }
}

// MARK: - Supporting Types

struct ContentValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let estimatedCalldataSize: Int
}

enum EthscriptionError: Error, LocalizedError {
    case contentTooLarge
    case encodingFailed
    case invalidEthscriptionId
    case notOwned
    case transferFailed(String)

    var errorDescription: String? {
        switch self {
        case .contentTooLarge:
            return "Content exceeds maximum size of 90KB"
        case .encodingFailed:
            return "Failed to encode content"
        case .invalidEthscriptionId:
            return "Invalid ethscription ID format"
        case .notOwned:
            return "You do not own this ethscription"
        case .transferFailed(let reason):
            return "Transfer failed: \(reason)"
        }
    }
}
