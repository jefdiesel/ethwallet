import Foundation
import BigInt

/// Represents an ERC-20 token approval granted to a spender
struct TokenApproval: Identifiable, Equatable {
    let id: String
    let token: ApprovalToken
    let spender: String
    let spenderLabel: String?  // "Uniswap V3 Router", etc.
    let allowance: BigUInt
    let isUnlimited: Bool
    let grantedAt: Date?
    let transactionHash: String?

    /// Formatted allowance for display
    var formattedAllowance: String {
        if isUnlimited {
            return "Unlimited"
        }

        let divisor = BigUInt(10).power(token.decimals)
        let whole = allowance / divisor
        let frac = allowance % divisor

        if whole > 1_000_000_000 {
            return "\(whole / 1_000_000_000)B+ \(token.symbol)"
        } else if whole > 1_000_000 {
            return "\(whole / 1_000_000)M+ \(token.symbol)"
        } else if whole > 1_000 {
            return "\(whole / 1_000)K+ \(token.symbol)"
        } else if frac == 0 {
            return "\(whole) \(token.symbol)"
        } else {
            let fracStr = String(frac).prefix(4)
            return "\(whole).\(fracStr) \(token.symbol)"
        }
    }

    /// Short spender address for display
    var shortSpender: String {
        guard spender.count > 12 else { return spender }
        return "\(spender.prefix(6))...\(spender.suffix(4))"
    }

    /// Display name: either label or short address
    var spenderDisplayName: String {
        spenderLabel ?? shortSpender
    }

    /// Whether this approval is potentially risky
    var isRisky: Bool {
        isUnlimited && spenderLabel == nil
    }

    init(
        token: ApprovalToken,
        spender: String,
        spenderLabel: String?,
        allowance: BigUInt,
        grantedAt: Date? = nil,
        transactionHash: String? = nil
    ) {
        self.id = "\(token.address.lowercased())_\(spender.lowercased())"
        self.token = token
        self.spender = spender
        self.spenderLabel = spenderLabel
        self.allowance = allowance
        self.isUnlimited = allowance >= BigUInt(10).power(36)  // Very high threshold
        self.grantedAt = grantedAt
        self.transactionHash = transactionHash
    }
}

/// Simplified token info for approvals
struct ApprovalToken: Equatable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int
    let logoURL: URL?

    init(address: String, symbol: String, name: String, decimals: Int, logoURL: URL? = nil) {
        self.address = address
        self.symbol = symbol
        self.name = name
        self.decimals = decimals
        self.logoURL = logoURL
    }

    init(from token: Token) {
        self.address = token.address
        self.symbol = token.symbol
        self.name = token.name
        self.decimals = token.decimals
        self.logoURL = token.logoURL
    }
}

/// Summary of approvals for an account
struct ApprovalSummary {
    let totalApprovals: Int
    let unlimitedApprovals: Int
    let riskyApprovals: Int  // Unlimited + unknown spender
    let tokens: [String]  // Unique token symbols

    var hasRiskyApprovals: Bool {
        riskyApprovals > 0
    }
}
