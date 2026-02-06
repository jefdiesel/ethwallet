import Foundation
import BigInt

/// Result of a transaction simulation
struct SimulationResult: Equatable {
    let success: Bool
    let balanceChanges: [BalanceChange]
    let approvalChanges: [ApprovalChange]
    let nftTransfers: [NFTTransfer]
    let riskWarnings: [SimulationRiskWarning]
    let gasUsed: BigUInt
    let revertReason: String?

    var hasSignificantChanges: Bool {
        !balanceChanges.isEmpty || !approvalChanges.isEmpty || !nftTransfers.isEmpty
    }

    var hasWarnings: Bool {
        !riskWarnings.isEmpty
    }
}

/// A balance change (ETH or ERC-20 tokens)
struct BalanceChange: Identifiable, Equatable {
    let id = UUID()
    let asset: BalanceChangeAsset
    let amount: BigInt  // Positive for incoming, negative for outgoing
    let formattedAmount: String
    let usdValue: Double?

    var isIncoming: Bool {
        amount > 0
    }

    var displayAmount: String {
        if isIncoming {
            return "+\(formattedAmount)"
        } else {
            return formattedAmount  // Already has minus sign
        }
    }
}

enum BalanceChangeAsset: Equatable {
    case eth
    case token(symbol: String, address: String, decimals: Int)

    var symbol: String {
        switch self {
        case .eth:
            return "ETH"
        case .token(let symbol, _, _):
            return symbol
        }
    }
}

/// An ERC-20 approval change
struct ApprovalChange: Identifiable, Equatable {
    let id = UUID()
    let token: String  // Token symbol
    let tokenAddress: String
    let spender: String
    let spenderLabel: String?  // "Uniswap V3 Router" etc
    let allowance: BigUInt
    let isUnlimited: Bool
    let isRevoke: Bool  // allowance == 0

    var displayAllowance: String {
        if isRevoke {
            return "Revoked"
        } else if isUnlimited {
            return "Unlimited"
        } else {
            return formatAllowance(allowance)
        }
    }

    private func formatAllowance(_ amount: BigUInt) -> String {
        let divisor = BigUInt(10).power(18)
        let whole = amount / divisor
        if whole > 1_000_000 {
            return "\(whole / 1_000_000)M+"
        } else if whole > 1_000 {
            return "\(whole / 1_000)K+"
        } else {
            return whole.description
        }
    }
}

/// An NFT transfer
struct NFTTransfer: Identifiable, Equatable {
    let id = UUID()
    let contractAddress: String
    let tokenId: String
    let collectionName: String?
    let isOutgoing: Bool

    var direction: String {
        isOutgoing ? "Send" : "Receive"
    }
}

/// Risk warnings from simulation
enum SimulationRiskWarning: Identifiable, Equatable {
    case contractNotVerified(address: String)
    case newContract(address: String, ageInDays: Int)
    case unlimitedApproval(token: String, spender: String)
    case highValueTransaction(usdValue: Double)
    case knownPhishing(address: String)
    case suspiciousApprovalPattern
    case simulationFailed(reason: String)

    var id: String {
        switch self {
        case .contractNotVerified(let address):
            return "unverified_\(address)"
        case .newContract(let address, _):
            return "new_\(address)"
        case .unlimitedApproval(let token, let spender):
            return "approval_\(token)_\(spender)"
        case .highValueTransaction(let value):
            return "highvalue_\(value)"
        case .knownPhishing(let address):
            return "phishing_\(address)"
        case .suspiciousApprovalPattern:
            return "suspicious_approval"
        case .simulationFailed(let reason):
            return "failed_\(reason)"
        }
    }

    var title: String {
        switch self {
        case .contractNotVerified:
            return "Unverified Contract"
        case .newContract:
            return "New Contract"
        case .unlimitedApproval:
            return "Unlimited Approval"
        case .highValueTransaction:
            return "High Value"
        case .knownPhishing:
            return "Known Scam"
        case .suspiciousApprovalPattern:
            return "Suspicious Pattern"
        case .simulationFailed:
            return "Simulation Failed"
        }
    }

    var message: String {
        switch self {
        case .contractNotVerified(let address):
            return "Contract \(address.prefix(10))... is not verified on the block explorer."
        case .newContract(_, let age):
            return "This contract was created \(age) day\(age == 1 ? "" : "s") ago."
        case .unlimitedApproval(let token, _):
            return "Granting unlimited access to your \(token) tokens."
        case .highValueTransaction(let value):
            return "This transaction involves $\(String(format: "%.2f", value)) in value."
        case .knownPhishing(let address):
            return "Address \(address.prefix(10))... is flagged as malicious."
        case .suspiciousApprovalPattern:
            return "This approval pattern is commonly used in scams."
        case .simulationFailed(let reason):
            return "Could not simulate: \(reason)"
        }
    }

    var severity: SimulationWarningSeverity {
        switch self {
        case .knownPhishing, .suspiciousApprovalPattern:
            return .critical
        case .unlimitedApproval, .contractNotVerified:
            return .high
        case .newContract, .highValueTransaction, .simulationFailed:
            return .medium
        }
    }

    var icon: String {
        switch severity {
        case .critical:
            return "exclamationmark.octagon.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        case .medium:
            return "info.circle.fill"
        }
    }
}

enum SimulationWarningSeverity: Int, Comparable {
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: SimulationWarningSeverity, rhs: SimulationWarningSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
