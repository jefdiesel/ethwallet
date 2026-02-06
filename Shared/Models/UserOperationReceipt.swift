import Foundation
import BigInt

/// Receipt returned after a UserOperation is included in a block
struct UserOperationReceipt: Codable {
    let userOpHash: String
    let sender: String
    let nonce: BigUInt
    let paymaster: String?
    let actualGasCost: BigUInt
    let actualGasUsed: BigUInt
    let success: Bool
    let reason: String?
    let logs: [UserOperationLog]
    let receipt: TransactionReceiptInfo

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case userOpHash, sender, nonce, paymaster
        case actualGasCost, actualGasUsed, success, reason, logs, receipt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userOpHash = try container.decode(String.self, forKey: .userOpHash)
        sender = try container.decode(String.self, forKey: .sender)

        let nonceHex = try container.decode(String.self, forKey: .nonce)
        nonce = BigUInt(hexString: nonceHex) ?? 0

        paymaster = try container.decodeIfPresent(String.self, forKey: .paymaster)

        let gasCostHex = try container.decode(String.self, forKey: .actualGasCost)
        actualGasCost = BigUInt(hexString: gasCostHex) ?? 0

        let gasUsedHex = try container.decode(String.self, forKey: .actualGasUsed)
        actualGasUsed = BigUInt(hexString: gasUsedHex) ?? 0

        success = try container.decode(Bool.self, forKey: .success)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        logs = try container.decodeIfPresent([UserOperationLog].self, forKey: .logs) ?? []
        receipt = try container.decode(TransactionReceiptInfo.self, forKey: .receipt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(userOpHash, forKey: .userOpHash)
        try container.encode(sender, forKey: .sender)
        try container.encode(nonce.hexString, forKey: .nonce)
        try container.encodeIfPresent(paymaster, forKey: .paymaster)
        try container.encode(actualGasCost.hexString, forKey: .actualGasCost)
        try container.encode(actualGasUsed.hexString, forKey: .actualGasUsed)
        try container.encode(success, forKey: .success)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encode(logs, forKey: .logs)
        try container.encode(receipt, forKey: .receipt)
    }

    // MARK: - Computed Properties

    /// Formatted gas cost in ETH
    var formattedGasCost: String {
        let divisor: BigUInt = 1_000_000_000_000_000_000  // 10^18
        let eth = Double(actualGasCost) / Double(divisor)
        return String(format: "%.6f ETH", eth)
    }

    /// Transaction hash from the bundled transaction
    var transactionHash: String {
        receipt.transactionHash
    }

    /// Block number where the UserOp was included
    var blockNumber: BigUInt {
        receipt.blockNumber
    }
}

// MARK: - Log Entry

struct UserOperationLog: Codable {
    let address: String
    let topics: [String]
    let data: String
    let blockNumber: String
    let transactionHash: String
    let logIndex: String

    /// Decoded event name if known
    var eventName: String? {
        guard let firstTopic = topics.first else { return nil }

        // Known event signatures
        let knownEvents: [String: String] = [
            "0x49628fd1471006c1482da88028e9ce4dbb080b815c9b0344d39e5a8e6ec1419f": "UserOperationEvent",
            "0x1c4fada7374c0a9ee8841fc38afe82932dc0f8e69012e927f061a8bae611a201": "UserOperationRevertReason",
            "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef": "Transfer",
            "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925": "Approval"
        ]

        return knownEvents[firstTopic.lowercased()]
    }
}

// MARK: - Transaction Receipt Info

struct TransactionReceiptInfo: Codable {
    let transactionHash: String
    let blockHash: String
    let blockNumber: BigUInt
    let from: String
    let to: String
    let cumulativeGasUsed: BigUInt
    let gasUsed: BigUInt
    let effectiveGasPrice: BigUInt
    let status: TransactionStatus

    enum CodingKeys: String, CodingKey {
        case transactionHash, blockHash, blockNumber, from, to
        case cumulativeGasUsed, gasUsed, effectiveGasPrice, status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        transactionHash = try container.decode(String.self, forKey: .transactionHash)
        blockHash = try container.decode(String.self, forKey: .blockHash)

        let blockNumHex = try container.decode(String.self, forKey: .blockNumber)
        blockNumber = BigUInt(hexString: blockNumHex) ?? 0

        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)

        let cumulativeHex = try container.decode(String.self, forKey: .cumulativeGasUsed)
        cumulativeGasUsed = BigUInt(hexString: cumulativeHex) ?? 0

        let gasUsedHex = try container.decode(String.self, forKey: .gasUsed)
        gasUsed = BigUInt(hexString: gasUsedHex) ?? 0

        let gasPriceHex = try container.decode(String.self, forKey: .effectiveGasPrice)
        effectiveGasPrice = BigUInt(hexString: gasPriceHex) ?? 0

        let statusHex = try container.decode(String.self, forKey: .status)
        status = statusHex == "0x1" ? .confirmed : .failed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(transactionHash, forKey: .transactionHash)
        try container.encode(blockHash, forKey: .blockHash)
        try container.encode(blockNumber.hexString, forKey: .blockNumber)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(cumulativeGasUsed.hexString, forKey: .cumulativeGasUsed)
        try container.encode(gasUsed.hexString, forKey: .gasUsed)
        try container.encode(effectiveGasPrice.hexString, forKey: .effectiveGasPrice)
        try container.encode(status == .confirmed ? "0x1" : "0x0", forKey: .status)
    }
}

// MARK: - UserOperation Status

enum UserOperationStatus: String, Codable {
    case pending
    case submitted       // Submitted to bundler
    case bundled         // Included in bundle transaction
    case onChain         // Transaction mined
    case confirmed       // UserOp executed successfully
    case reverted        // UserOp reverted
    case failed          // Bundle transaction failed

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .submitted: return "Submitted"
        case .bundled: return "Bundled"
        case .onChain: return "On Chain"
        case .confirmed: return "Confirmed"
        case .reverted: return "Reverted"
        case .failed: return "Failed"
        }
    }

    var isFinished: Bool {
        switch self {
        case .pending, .submitted, .bundled, .onChain:
            return false
        case .confirmed, .reverted, .failed:
            return true
        }
    }

    var isSuccess: Bool {
        self == .confirmed
    }
}

// MARK: - Gas Estimation Response

struct UserOperationGasEstimate: Codable {
    var callGasLimit: BigUInt
    var verificationGasLimit: BigUInt
    var preVerificationGas: BigUInt
    var maxFeePerGas: BigUInt
    var maxPriorityFeePerGas: BigUInt

    // Optional paymaster gas values
    var paymasterVerificationGasLimit: BigUInt?
    var paymasterPostOpGasLimit: BigUInt?

    enum CodingKeys: String, CodingKey {
        case callGasLimit, verificationGasLimit, preVerificationGas
        case maxFeePerGas, maxPriorityFeePerGas
        case paymasterVerificationGasLimit, paymasterPostOpGasLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let callGasHex = try container.decode(String.self, forKey: .callGasLimit)
        callGasLimit = BigUInt(hexString: callGasHex) ?? 0

        let verGasHex = try container.decode(String.self, forKey: .verificationGasLimit)
        verificationGasLimit = BigUInt(hexString: verGasHex) ?? 0

        let preVerHex = try container.decode(String.self, forKey: .preVerificationGas)
        preVerificationGas = BigUInt(hexString: preVerHex) ?? 0

        if let maxFeeHex = try container.decodeIfPresent(String.self, forKey: .maxFeePerGas) {
            maxFeePerGas = BigUInt(hexString: maxFeeHex) ?? 0
        } else {
            maxFeePerGas = 0
        }

        if let priorityHex = try container.decodeIfPresent(String.self, forKey: .maxPriorityFeePerGas) {
            maxPriorityFeePerGas = BigUInt(hexString: priorityHex) ?? 0
        } else {
            maxPriorityFeePerGas = 0
        }

        if let pmVerHex = try container.decodeIfPresent(String.self, forKey: .paymasterVerificationGasLimit) {
            paymasterVerificationGasLimit = BigUInt(hexString: pmVerHex)
        }

        if let pmPostHex = try container.decodeIfPresent(String.self, forKey: .paymasterPostOpGasLimit) {
            paymasterPostOpGasLimit = BigUInt(hexString: pmPostHex)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(callGasLimit.hexString, forKey: .callGasLimit)
        try container.encode(verificationGasLimit.hexString, forKey: .verificationGasLimit)
        try container.encode(preVerificationGas.hexString, forKey: .preVerificationGas)
        try container.encode(maxFeePerGas.hexString, forKey: .maxFeePerGas)
        try container.encode(maxPriorityFeePerGas.hexString, forKey: .maxPriorityFeePerGas)

        if let pmVer = paymasterVerificationGasLimit {
            try container.encode(pmVer.hexString, forKey: .paymasterVerificationGasLimit)
        }
        if let pmPost = paymasterPostOpGasLimit {
            try container.encode(pmPost.hexString, forKey: .paymasterPostOpGasLimit)
        }
    }

    /// Total gas for the operation
    var totalGas: BigUInt {
        callGasLimit + verificationGasLimit + preVerificationGas
    }

    /// Estimated max cost in wei
    var estimatedMaxCost: BigUInt {
        totalGas * maxFeePerGas
    }
}
