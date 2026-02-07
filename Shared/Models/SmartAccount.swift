import Foundation
import BigInt

/// Represents an ERC-4337 smart contract account (SimpleAccount)
struct SmartAccount: Identifiable, Codable, Hashable {
    let id: UUID
    let ownerAddress: String          // EOA that owns this smart account
    let smartAccountAddress: String   // The computed/deployed smart account address
    let salt: BigUInt                 // Salt used for CREATE2 address computation
    var isDeployed: Bool              // Whether the account contract is deployed
    let chainId: Int                  // Chain where this account exists
    let createdAt: Date

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        ownerAddress: String,
        smartAccountAddress: String,
        salt: BigUInt = 0,
        isDeployed: Bool = false,
        chainId: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.ownerAddress = ownerAddress
        self.smartAccountAddress = smartAccountAddress
        self.salt = salt
        self.isDeployed = isDeployed
        self.chainId = chainId
        self.createdAt = createdAt
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, ownerAddress, smartAccountAddress, salt, isDeployed, chainId, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerAddress = try container.decode(String.self, forKey: .ownerAddress)
        smartAccountAddress = try container.decode(String.self, forKey: .smartAccountAddress)
        let saltString = try container.decode(String.self, forKey: .salt)
        salt = BigUInt(saltString) ?? 0
        isDeployed = try container.decode(Bool.self, forKey: .isDeployed)
        chainId = try container.decode(Int.self, forKey: .chainId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(ownerAddress, forKey: .ownerAddress)
        try container.encode(smartAccountAddress, forKey: .smartAccountAddress)
        try container.encode(String(salt), forKey: .salt)
        try container.encode(isDeployed, forKey: .isDeployed)
        try container.encode(chainId, forKey: .chainId)
        try container.encode(createdAt, forKey: .createdAt)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SmartAccount, rhs: SmartAccount) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    /// Abbreviated smart account address for display
    var shortAddress: String {
        guard smartAccountAddress.count >= 10 else { return smartAccountAddress }
        let start = smartAccountAddress.prefix(6)
        let end = smartAccountAddress.suffix(4)
        return "\(start)...\(end)"
    }

    /// Abbreviated owner address for display
    var shortOwnerAddress: String {
        guard ownerAddress.count >= 10 else { return ownerAddress }
        let start = ownerAddress.prefix(6)
        let end = ownerAddress.suffix(4)
        return "\(start)...\(end)"
    }

    /// Status text for display
    var statusText: String {
        isDeployed ? "Active" : "Not Deployed"
    }

    /// Whether this is on a testnet
    var isTestnet: Bool {
        // Known testnets
        [11155111, 5, 80001, 421613, 84531].contains(chainId)
    }

    /// Chain name for display
    var chainName: String {
        switch chainId {
        case 1: return "Ethereum"
        case 11155111: return "Sepolia"
        case 8453: return "Base"
        case 84531: return "Base Goerli"
        case 137: return "Polygon"
        case 80001: return "Mumbai"
        case 42161: return "Arbitrum One"
        case 421613: return "Arbitrum Goerli"
        case 10: return "Optimism"
        default: return "Chain \(chainId)"
        }
    }
}

// MARK: - Smart Account Features

/// Features available with smart accounts
enum SmartAccountFeature: String, CaseIterable {
    case batchTransactions = "batch"
    case gaslessTransactions = "gasless"
    case socialRecovery = "recovery"
    case sessionKeys = "sessions"
    case spendingLimits = "limits"

    var displayName: String {
        switch self {
        case .batchTransactions: return "Batch Transactions"
        case .gaslessTransactions: return "Gasless Transactions"
        case .socialRecovery: return "Social Recovery"
        case .sessionKeys: return "Session Keys"
        case .spendingLimits: return "Spending Limits"
        }
    }

    var description: String {
        switch self {
        case .batchTransactions: return "Send multiple transactions in one"
        case .gaslessTransactions: return "Pay gas fees in tokens or get sponsored"
        case .socialRecovery: return "Recover your account using trusted contacts"
        case .sessionKeys: return "Grant limited permissions to dApps"
        case .spendingLimits: return "Set daily spending limits"
        }
    }

    var isAvailable: Bool {
        switch self {
        case .batchTransactions, .gaslessTransactions:
            return true
        case .socialRecovery, .sessionKeys, .spendingLimits:
            return false  // Coming soon
        }
    }

    var iconName: String {
        switch self {
        case .batchTransactions: return "square.stack.3d.up"
        case .gaslessTransactions: return "gift"
        case .socialRecovery: return "person.3"
        case .sessionKeys: return "key"
        case .spendingLimits: return "gauge.with.dots.needle.bottom.50percent"
        }
    }
}

// MARK: - ERC-4337 Constants

struct ERC4337Constants {
    /// EntryPoint v0.6 address (same on all chains)
    static let entryPointV06 = "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"

    /// EntryPoint v0.7 address (same on all chains)
    static let entryPointV07 = "0x0000000071727De22E5E9d8BAf0edAc6f37da032"

    /// SimpleAccountFactory v0.7 address
    static let simpleAccountFactory = "0x91E60e0613810449d098b0b5Ec8b51A0FE8c8985"

    /// Active EntryPoint to use (v0.7 to match the factory)
    static let entryPoint = entryPointV07

    /// Default salt for first smart account
    static let defaultSalt: BigUInt = 0

    /// Minimum verification gas limit
    static let minVerificationGasLimit: BigUInt = 100_000

    /// Minimum call gas limit
    static let minCallGasLimit: BigUInt = 50_000

    /// Default pre-verification gas
    static let defaultPreVerificationGas: BigUInt = 50_000

    /// Function selectors
    struct Selectors {
        /// createAccount(address owner, uint256 salt)
        static let createAccount = "0x5fbfb9cf"

        /// execute(address dest, uint256 value, bytes calldata func)
        static let execute = "0xb61d27f6"

        /// executeBatch(address[] calldata dest, uint256[] calldata values, bytes[] calldata func)
        static let executeBatch = "0x47e1da2a"

        /// getNonce()
        static let getNonce = "0xd087d288"

        /// getDeposit()
        static let getDeposit = "0xc399ec88"

        /// EntryPoint getNonce(address sender, uint192 key)
        static let entryPointGetNonce = "0x35567e1a"
    }
}
