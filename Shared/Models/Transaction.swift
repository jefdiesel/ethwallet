import Foundation
import BigInt

/// Represents an Ethereum transaction
struct Transaction: Identifiable, Codable {
    let id: String  // Transaction hash
    let from: String
    let to: String
    let value: String  // Wei as hex string
    let data: String?  // Calldata
    let nonce: Int
    let gasLimit: String
    let gasPrice: String?  // Legacy
    let maxFeePerGas: String?  // EIP-1559
    let maxPriorityFeePerGas: String?  // EIP-1559
    let chainId: Int

    // Post-transaction fields
    var blockNumber: Int?
    var blockHash: String?
    var transactionIndex: Int?
    var status: TransactionStatus?
    var gasUsed: String?
    var effectiveGasPrice: String?
    var timestamp: Date?

    // MARK: - Computed Properties

    var isEIP1559: Bool {
        maxFeePerGas != nil && maxPriorityFeePerGas != nil
    }

    var shortHash: String {
        guard id.count >= 10 else { return id }
        let start = id.prefix(6)
        let end = id.suffix(4)
        return "\(start)...\(end)"
    }

    var isContractCall: Bool {
        guard let data = data else { return false }
        return data.count > 2  // More than just "0x"
    }

    var isEthscriptionTransfer: Bool {
        // Ethscription transfer: calldata is exactly 32 bytes (64 hex chars + 0x prefix)
        guard let data = data else { return false }
        return data.count == 66 && value == "0x0"
    }

    var isEthscriptionCreation: Bool {
        // Ethscription creation: calldata starts with data URI encoded as hex
        guard let data = data else { return false }
        // Check if calldata represents "data:" prefix
        let dataPrefix = "646174613a"  // "data:" in hex
        return data.lowercased().hasPrefix("0x" + dataPrefix)
    }
}

// MARK: - Transaction Status

enum TransactionStatus: String, Codable {
    case pending
    case confirmed
    case failed

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .confirmed: return "Confirmed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Transaction Request (for building transactions)

struct TransactionRequest {
    var from: String
    var to: String
    var value: BigUInt  // Wei
    var data: Data?
    var nonce: Int?  // Auto-fill if nil
    var gasLimit: BigUInt?  // Estimate if nil
    var maxFeePerGas: BigUInt?
    var maxPriorityFeePerGas: BigUInt?
    var chainId: Int

    init(
        from: String,
        to: String,
        value: BigUInt = 0,
        data: Data? = nil,
        chainId: Int
    ) {
        self.from = from
        self.to = to
        self.value = value
        self.data = data
        self.chainId = chainId
    }

    /// Create a simple ETH transfer request
    static func ethTransfer(
        from: String,
        to: String,
        value: BigUInt,
        chainId: Int
    ) -> TransactionRequest {
        TransactionRequest(from: from, to: to, value: value, chainId: chainId)
    }

    /// Create an ethscription creation request
    static func createEthscription(
        from: String,
        to: String,
        calldata: Data,
        chainId: Int
    ) -> TransactionRequest {
        TransactionRequest(from: from, to: to, value: 0, data: calldata, chainId: chainId)
    }

    /// Create an ethscription transfer request
    static func transferEthscription(
        from: String,
        to: String,
        ethscriptionId: String,
        chainId: Int
    ) -> TransactionRequest {
        let data = Data(hex: ethscriptionId)
        return TransactionRequest(from: from, to: to, value: 0, data: data, chainId: chainId)
    }
}

// MARK: - Transaction History Item

struct TransactionHistoryItem: Identifiable {
    let id: String
    let transaction: Transaction
    let network: Network
    let type: TransactionType

    enum TransactionType {
        case ethSent
        case ethReceived
        case ethscriptionCreated
        case ethscriptionSent
        case ethscriptionReceived
        case contractInteraction
        case unknown
    }

    var displayTitle: String {
        switch type {
        case .ethSent: return "Sent ETH"
        case .ethReceived: return "Received ETH"
        case .ethscriptionCreated: return "Created Ethscription"
        case .ethscriptionSent: return "Sent Ethscription"
        case .ethscriptionReceived: return "Received Ethscription"
        case .contractInteraction: return "Contract Interaction"
        case .unknown: return "Transaction"
        }
    }
}

// MARK: - Gas Estimation

struct GasEstimate {
    let gasLimit: BigUInt
    let maxFeePerGas: BigUInt
    let maxPriorityFeePerGas: BigUInt
    let estimatedCost: BigUInt  // gasLimit * maxFeePerGas

    var formattedCost: String {
        let divisor: BigUInt = 1_000_000_000_000_000_000  // 10^18
        let eth = Double(estimatedCost) / Double(divisor)
        return String(format: "%.6f ETH", eth)
    }
}

// MARK: - Data Extension for Hex

extension Data {
    init(hex: String) {
        var hex = hex
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }

        self = data
    }
}
