import Foundation
import BigInt

/// Represents a paymaster configuration for sponsored/gasless transactions
struct Paymaster: Codable, Identifiable {
    let id: UUID
    let address: String
    let type: PaymasterType
    let name: String
    let sponsorshipPolicy: String?
    let chainId: Int

    init(
        id: UUID = UUID(),
        address: String,
        type: PaymasterType,
        name: String,
        sponsorshipPolicy: String? = nil,
        chainId: Int
    ) {
        self.id = id
        self.address = address
        self.type = type
        self.name = name
        self.sponsorshipPolicy = sponsorshipPolicy
        self.chainId = chainId
    }

    /// Abbreviated address for display
    var shortAddress: String {
        guard address.count >= 10 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }
}

// MARK: - Paymaster Type

enum PaymasterType: String, Codable, CaseIterable {
    case verifying = "verifying"   // Pimlico/Stackup verifying paymaster
    case erc20 = "erc20"           // Pay gas in ERC-20 tokens
    case sponsorship = "sponsorship"  // Fully sponsored by protocol/dApp
    case custom = "custom"

    var displayName: String {
        switch self {
        case .verifying: return "Verifying Paymaster"
        case .erc20: return "ERC-20 Paymaster"
        case .sponsorship: return "Sponsored"
        case .custom: return "Custom Paymaster"
        }
    }

    var description: String {
        switch self {
        case .verifying: return "Pay gas fees through Pimlico"
        case .erc20: return "Pay gas fees in tokens"
        case .sponsorship: return "Gas fees sponsored by dApp"
        case .custom: return "Custom paymaster contract"
        }
    }
}

// MARK: - Sponsorship Policy

struct SponsorshipPolicy: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let chainId: Int
    let limits: SponsorshipLimits?
    let allowedContracts: [String]?  // nil means any contract
    let isActive: Bool

    /// Whether the policy allows a specific contract
    func allowsContract(_ address: String) -> Bool {
        guard let allowed = allowedContracts else { return true }
        return allowed.contains { $0.lowercased() == address.lowercased() }
    }
}

struct SponsorshipLimits: Codable {
    let maxGasPerOperation: BigUInt?
    let maxOperationsPerDay: Int?
    let maxGasPerDay: BigUInt?
    let validUntil: Date?

    enum CodingKeys: String, CodingKey {
        case maxGasPerOperation, maxOperationsPerDay, maxGasPerDay, validUntil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let gasHex = try container.decodeIfPresent(String.self, forKey: .maxGasPerOperation) {
            maxGasPerOperation = BigUInt(hexString: gasHex)
        } else {
            maxGasPerOperation = nil
        }

        maxOperationsPerDay = try container.decodeIfPresent(Int.self, forKey: .maxOperationsPerDay)

        if let dayGasHex = try container.decodeIfPresent(String.self, forKey: .maxGasPerDay) {
            maxGasPerDay = BigUInt(hexString: dayGasHex)
        } else {
            maxGasPerDay = nil
        }

        validUntil = try container.decodeIfPresent(Date.self, forKey: .validUntil)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        if let gas = maxGasPerOperation {
            try container.encode(gas.hexString, forKey: .maxGasPerOperation)
        }
        try container.encodeIfPresent(maxOperationsPerDay, forKey: .maxOperationsPerDay)
        if let dayGas = maxGasPerDay {
            try container.encode(dayGas.hexString, forKey: .maxGasPerDay)
        }
        try container.encodeIfPresent(validUntil, forKey: .validUntil)
    }

    /// Check if limits allow the operation
    var isValid: Bool {
        if let until = validUntil, until < Date() {
            return false
        }
        return true
    }
}

// MARK: - Paymaster Data Response

/// Response from paymaster endpoint with sponsorship data
/// Handles both v0.6 (paymasterAndData) and v0.7 (separate fields) formats
struct PaymasterDataResponse: Codable {
    let paymasterAndData: Data
    let preVerificationGas: BigUInt?
    let verificationGasLimit: BigUInt?
    let callGasLimit: BigUInt?
    let paymasterVerificationGasLimit: BigUInt?
    let paymasterPostOpGasLimit: BigUInt?

    enum CodingKeys: String, CodingKey {
        // v0.6 format
        case paymasterAndData
        // v0.7 format (separate fields)
        case paymaster, paymasterData
        // Gas fields (both formats)
        case preVerificationGas, verificationGasLimit
        case callGasLimit, paymasterVerificationGasLimit, paymasterPostOpGasLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try v0.6 format first (paymasterAndData as single field)
        if let pmDataHex = try container.decodeIfPresent(String.self, forKey: .paymasterAndData) {
            paymasterAndData = Data(hex: pmDataHex)
        }
        // Otherwise try v0.7 format (paymaster + gas limits + paymasterData)
        else if let paymasterHex = try container.decodeIfPresent(String.self, forKey: .paymaster),
                let paymasterDataHex = try container.decodeIfPresent(String.self, forKey: .paymasterData) {
            // For v0.7, we store combined: paymaster (20 bytes) || pmData
            // The gas limits are sent separately in the RPC but we don't need them in the combined field
            let paymasterAddr = Data(hex: paymasterHex)
            let pmData = Data(hex: paymasterDataHex)
            paymasterAndData = paymasterAddr + pmData
        } else {
            paymasterAndData = Data()
        }

        if let preVerHex = try container.decodeIfPresent(String.self, forKey: .preVerificationGas) {
            preVerificationGas = BigUInt(hexString: preVerHex)
        } else {
            preVerificationGas = nil
        }

        if let verGasHex = try container.decodeIfPresent(String.self, forKey: .verificationGasLimit) {
            verificationGasLimit = BigUInt(hexString: verGasHex)
        } else {
            verificationGasLimit = nil
        }

        if let callGasHex = try container.decodeIfPresent(String.self, forKey: .callGasLimit) {
            callGasLimit = BigUInt(hexString: callGasHex)
        } else {
            callGasLimit = nil
        }

        if let pmVerHex = try container.decodeIfPresent(String.self, forKey: .paymasterVerificationGasLimit) {
            paymasterVerificationGasLimit = BigUInt(hexString: pmVerHex)
        } else {
            paymasterVerificationGasLimit = nil
        }

        if let pmPostHex = try container.decodeIfPresent(String.self, forKey: .paymasterPostOpGasLimit) {
            paymasterPostOpGasLimit = BigUInt(hexString: pmPostHex)
        } else {
            paymasterPostOpGasLimit = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(paymasterAndData.hexString, forKey: .paymasterAndData)

        if let preVer = preVerificationGas {
            try container.encode(preVer.hexString, forKey: .preVerificationGas)
        }
        if let verGas = verificationGasLimit {
            try container.encode(verGas.hexString, forKey: .verificationGasLimit)
        }
        if let callGas = callGasLimit {
            try container.encode(callGas.hexString, forKey: .callGasLimit)
        }
        if let pmVer = paymasterVerificationGasLimit {
            try container.encode(pmVer.hexString, forKey: .paymasterVerificationGasLimit)
        }
        if let pmPost = paymasterPostOpGasLimit {
            try container.encode(pmPost.hexString, forKey: .paymasterPostOpGasLimit)
        }
    }
}

// MARK: - ERC-20 Paymaster Token

/// Token accepted by ERC-20 paymaster for gas payment
struct PaymasterToken: Codable, Identifiable {
    let id: UUID
    let address: String
    let symbol: String
    let decimals: Int
    let exchangeRate: Double  // Token units per gas unit
    let chainId: Int

    init(
        id: UUID = UUID(),
        address: String,
        symbol: String,
        decimals: Int,
        exchangeRate: Double,
        chainId: Int
    ) {
        self.id = id
        self.address = address
        self.symbol = symbol
        self.decimals = decimals
        self.exchangeRate = exchangeRate
        self.chainId = chainId
    }

    /// Calculate token amount needed for gas
    func tokenAmountForGas(_ gasInWei: BigUInt) -> BigUInt {
        let gasDouble = Double(gasInWei)
        let tokenAmount = gasDouble * exchangeRate
        return BigUInt(tokenAmount)
    }

    /// Format token amount for display
    func formatAmount(_ amount: BigUInt) -> String {
        let divisor = pow(10.0, Double(decimals))
        let value = Double(amount) / divisor
        return String(format: "%.4f %@", value, symbol)
    }
}

// MARK: - Known Paymasters

extension Paymaster {
    /// Pimlico verifying paymaster on Ethereum mainnet
    static let pimlicoMainnet = Paymaster(
        address: "0x0000000000325602a77416A16136FDafd04b299f",
        type: .verifying,
        name: "Pimlico",
        chainId: 1
    )

    /// Pimlico verifying paymaster on Sepolia
    static let pimlicoSepolia = Paymaster(
        address: "0x0000000000325602a77416A16136FDafd04b299f",
        type: .verifying,
        name: "Pimlico",
        chainId: 11155111
    )

    /// Get Pimlico paymaster for chain
    static func pimlico(chainId: Int) -> Paymaster {
        Paymaster(
            address: "0x0000000000325602a77416A16136FDafd04b299f",
            type: .verifying,
            name: "Pimlico",
            chainId: chainId
        )
    }
}
