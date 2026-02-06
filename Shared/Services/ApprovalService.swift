import Foundation
import BigInt

/// Service for managing ERC-20 token approvals
final class ApprovalService {
    static let shared = ApprovalService()

    private var web3Service: Web3Service

    /// Approval event topic (keccak256 of "Approval(address,address,uint256)")
    private let approvalEventTopic = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

    /// Known spender labels
    private let knownSpenders: [String: String] = [
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": "Uniswap V2 Router",
        "0xe592427a0aece92de3edee1f18e0157c05861564": "Uniswap V3 Router",
        "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": "Uniswap Universal Router",
        "0x1111111254eeb25477b68fb85ed929f73a960582": "1inch Router",
        "0xdef1c0ded9bec7f1a1670819833240f027b25eff": "0x Exchange",
        "0x00000000006c3852cbef3e08e8df289169ede581": "OpenSea Seaport",
        "0x00000000000000adc04c56bf30ac9d3c0aaf14dc": "OpenSea Seaport 1.5",
        "0x881d40237659c251811cec9c364ef91dc08d300c": "Metamask Swap Router",
        "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": "Aave V3 Pool",
        "0xef1c6e67703c7bd7107eed8303fbe6ec2554bf6b": "Uniswap Permit2",
        "0x000000000022d473030f116ddee9f6b43ac78ba3": "Permit2"
    ]

    /// Common tokens to check (mainnet)
    private let commonTokens: [ApprovalToken] = [
        ApprovalToken(address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC", name: "USD Coin", decimals: 6),
        ApprovalToken(address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT", name: "Tether USD", decimals: 6),
        ApprovalToken(address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", symbol: "WETH", name: "Wrapped Ether", decimals: 18),
        ApprovalToken(address: "0x6B175474E89094C44Da98b954EedeCD5bad813", symbol: "DAI", name: "Dai Stablecoin", decimals: 18),
        ApprovalToken(address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", symbol: "WBTC", name: "Wrapped BTC", decimals: 8),
        ApprovalToken(address: "0x514910771AF9Ca656af840dff83E8264EcF986CA", symbol: "LINK", name: "Chainlink", decimals: 18),
        ApprovalToken(address: "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984", symbol: "UNI", name: "Uniswap", decimals: 18),
        ApprovalToken(address: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9", symbol: "AAVE", name: "Aave", decimals: 18)
    ]

    private init() {
        self.web3Service = Web3Service()
    }

    // MARK: - Public API

    /// Fetch all token approvals for an address
    func getApprovals(for address: String, chainId: Int = 1) async throws -> [TokenApproval] {
        // Update web3 service for the chain
        if let network = Network.forChainId(chainId) {
            web3Service = Web3Service(network: network)
        }

        var approvals: [TokenApproval] = []

        // Check common tokens for approvals
        for token in getTokensForChain(chainId) {
            let tokenApprovals = try await getApprovalsForToken(
                token: token,
                owner: address,
                chainId: chainId
            )
            approvals.append(contentsOf: tokenApprovals)
        }

        // Sort by risk (unlimited unknown first)
        approvals.sort { a, b in
            if a.isRisky != b.isRisky {
                return a.isRisky
            }
            if a.isUnlimited != b.isUnlimited {
                return a.isUnlimited
            }
            return a.token.symbol < b.token.symbol
        }

        return approvals
    }

    /// Get approvals for a specific token
    func getApprovalsForToken(
        token: ApprovalToken,
        owner: String,
        chainId: Int
    ) async throws -> [TokenApproval] {
        var approvals: [TokenApproval] = []

        // Check allowance against common spenders
        let spendersToCheck = Array(knownSpenders.keys)

        for spender in spendersToCheck {
            let allowance = try await getAllowance(
                token: token.address,
                owner: owner,
                spender: spender
            )

            if allowance > 0 {
                approvals.append(TokenApproval(
                    token: token,
                    spender: spender,
                    spenderLabel: knownSpenders[spender.lowercased()],
                    allowance: allowance
                ))
            }
        }

        return approvals
    }

    /// Get allowance for a specific token/owner/spender
    func getAllowance(token: String, owner: String, spender: String) async throws -> BigUInt {
        // allowance(address,address) selector: 0xdd62ed3e
        let selector = "0xdd62ed3e"
        let paddedOwner = owner.lowercased().replacingOccurrences(of: "0x", with: "").leftPadded(to: 64)
        let paddedSpender = spender.lowercased().replacingOccurrences(of: "0x", with: "").leftPadded(to: 64)
        let calldata = selector + paddedOwner + paddedSpender

        let result = try await web3Service.call(to: token, data: calldata)
        let hexAllowance = result.replacingOccurrences(of: "0x", with: "")
        return BigUInt(hexAllowance, radix: 16) ?? BigUInt(0)
    }

    /// Revoke an approval (set allowance to 0)
    func revokeApproval(
        token: String,
        spender: String,
        from: String,
        privateKey: Data
    ) async throws -> String {
        // approve(address,uint256) with amount = 0
        let calldata = buildApproveCalldata(spender: spender, amount: BigUInt(0))

        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: token,
            value: 0,
            data: calldata
        )

        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    /// Estimate gas for revoking an approval
    func estimateRevokeGas(
        token: String,
        spender: String,
        from: String
    ) async throws -> GasEstimate {
        let calldata = buildApproveCalldata(spender: spender, amount: BigUInt(0))

        let request = TransactionRequest(
            from: from,
            to: token,
            value: 0,
            data: calldata,
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

    /// Get summary of approvals
    func getApprovalSummary(for address: String, chainId: Int = 1) async -> ApprovalSummary {
        do {
            let approvals = try await getApprovals(for: address, chainId: chainId)

            return ApprovalSummary(
                totalApprovals: approvals.count,
                unlimitedApprovals: approvals.filter { $0.isUnlimited }.count,
                riskyApprovals: approvals.filter { $0.isRisky }.count,
                tokens: Array(Set(approvals.map { $0.token.symbol }))
            )
        } catch {
            return ApprovalSummary(
                totalApprovals: 0,
                unlimitedApprovals: 0,
                riskyApprovals: 0,
                tokens: []
            )
        }
    }

    /// Get spender label
    func getSpenderLabel(_ address: String) -> String? {
        knownSpenders[address.lowercased()]
    }

    // MARK: - Private Helpers

    private func getTokensForChain(_ chainId: Int) -> [ApprovalToken] {
        switch chainId {
        case 1:
            return commonTokens
        default:
            return []
        }
    }

    private func buildApproveCalldata(spender: String, amount: BigUInt) -> Data {
        // approve(address,uint256) selector: 0x095ea7b3
        let selector = Data([0x09, 0x5e, 0xa7, 0xb3])
        let paddedSpender = spender.lowercased().replacingOccurrences(of: "0x", with: "").leftPadded(to: 64)
        let paddedAmount = String(amount, radix: 16).leftPadded(to: 64)

        var calldata = selector
        if let spenderData = Data(hexString: paddedSpender) {
            calldata.append(spenderData)
        }
        if let amountData = Data(hexString: paddedAmount) {
            calldata.append(amountData)
        }

        return calldata
    }
}

// MARK: - String Extension

private extension String {
    func leftPadded(to length: Int, with char: Character = "0") -> String {
        if count >= length { return self }
        return String(repeating: char, count: length - count) + self
    }
}

// MARK: - Data Extension

private extension Data {
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
