import Foundation
import BigInt

/// Service for simulating Ethereum transactions before execution
/// Shows users what will happen: balance changes, approvals, warnings
final class TransactionSimulationService {
    static let shared = TransactionSimulationService()

    /// Tenderly API endpoint (free tier: 5000 simulations/month)
    private let tenderlyAPIURL = "https://api.tenderly.co/api/v1/simulate"

    /// Keychain identifier for Tenderly API key
    private let tenderlyKeyIdentifier = "tenderly"

    /// Reference to keychain service for secure storage
    private let keychainService = KeychainService.shared

    /// Known contract labels for common protocols
    private let knownContracts: [String: String] = [
        "0x7a250d5630b4cf539739df2c5dacb4c659f2488d": "Uniswap V2 Router",
        "0xe592427a0aece92de3edee1f18e0157c05861564": "Uniswap V3 Router",
        "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45": "Uniswap Universal Router",
        "0x1111111254eeb25477b68fb85ed929f73a960582": "1inch Router",
        "0xdef1c0ded9bec7f1a1670819833240f027b25eff": "0x Exchange",
        "0x00000000006c3852cbef3e08e8df289169ede581": "OpenSea Seaport",
        "0x7f268357a8c2552623316e2562d90e642bb538e5": "OpenSea Wyvern",
        "0x7be8076f4ea4a4ad08075c2508e481d6c946d12b": "OpenSea V1",
        "0x881d40237659c251811cec9c364ef91dc08d300c": "Metamask Swap Router",
        "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2": "Aave V3 Pool",
        "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "USDC",
        "0xdac17f958d2ee523a2206206994597c13d831ec7": "USDT",
        "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "WETH"
    ]

    /// ERC-20 function selectors
    private let transferSelector = "0xa9059cbb"  // transfer(address,uint256)
    private let approveSelector = "0x095ea7b3"   // approve(address,uint256)
    private let transferFromSelector = "0x23b872dd"  // transferFrom(address,address,uint256)

    /// Max uint256 for unlimited approval detection
    private let maxUint256 = BigUInt(2).power(256) - 1
    private let highApprovalThreshold = BigUInt(10).power(36)  // Very high approval

    private init() {}

    // MARK: - Public API

    /// Simulate a transaction and return predicted outcomes
    func simulate(
        from: String,
        to: String,
        value: BigUInt,
        data: Data?,
        chainId: Int
    ) async throws -> SimulationResult {
        // Try Tenderly simulation if API key is available
        if let apiKey = getTenderlyAPIKey(), !apiKey.isEmpty {
            do {
                return try await simulateWithTenderly(
                    from: from,
                    to: to,
                    value: value,
                    data: data,
                    chainId: chainId,
                    apiKey: apiKey
                )
            } catch {
                #if DEBUG
                print("[Simulation] Tenderly failed: \(error), falling back to local analysis")
                #endif
            }
        }

        // Fallback to local calldata analysis
        return await analyzeLocally(
            from: from,
            to: to,
            value: value,
            data: data,
            chainId: chainId
        )
    }

    /// Set Tenderly API key (stored securely in Keychain)
    func setTenderlyAPIKey(_ key: String) {
        do {
            try keychainService.storeAPIKey(key, for: tenderlyKeyIdentifier)
        } catch {
            #if DEBUG
            print("[Simulation] Failed to store API key: \(error)")
            #endif
        }
    }

    /// Get Tenderly API key (from Keychain)
    func getTenderlyAPIKey() -> String? {
        keychainService.retrieveAPIKey(for: tenderlyKeyIdentifier)
    }

    // MARK: - Tenderly Simulation

    private func simulateWithTenderly(
        from: String,
        to: String,
        value: BigUInt,
        data: Data?,
        chainId: Int,
        apiKey: String
    ) async throws -> SimulationResult {
        guard let url = URL(string: tenderlyAPIURL) else {
            throw SimulationError.invalidConfiguration
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let requestBody: [String: Any] = [
            "network_id": String(chainId),
            "from": from,
            "to": to,
            "value": "0x\(String(value, radix: 16))",
            "input": data != nil ? "0x\(data!.toHexString())" : "0x",
            "save": false,
            "save_if_fails": false,
            "simulation_type": "quick"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SimulationError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SimulationError.apiError(statusCode: httpResponse.statusCode)
        }

        return try parseTenderlyResponse(responseData, from: from)
    }

    private func parseTenderlyResponse(_ data: Data, from: String) throws -> SimulationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transaction = json["transaction"] as? [String: Any] else {
            throw SimulationError.parseError
        }

        let success = transaction["status"] as? Bool ?? false
        let gasUsed = BigUInt(transaction["gas_used"] as? Int ?? 0)
        let revertReason = transaction["error_message"] as? String

        var balanceChanges: [BalanceChange] = []
        var approvalChanges: [ApprovalChange] = []
        var warnings: [SimulationRiskWarning] = []

        // Parse asset changes
        if let txInfo = transaction["transaction_info"] as? [String: Any],
           let assetChanges = txInfo["asset_changes"] as? [[String: Any]] {
            for change in assetChanges {
                if let balanceChange = parseAssetChange(change, from: from) {
                    balanceChanges.append(balanceChange)
                }
            }
        }

        // Parse logs for approvals
        if let txInfo = transaction["transaction_info"] as? [String: Any],
           let logs = txInfo["logs"] as? [[String: Any]] {
            for log in logs {
                if let approval = parseApprovalLog(log) {
                    approvalChanges.append(approval)

                    // Add warning for unlimited approvals
                    if approval.isUnlimited {
                        warnings.append(.unlimitedApproval(token: approval.token, spender: approval.spender))
                    }
                }
            }
        }

        return SimulationResult(
            success: success,
            balanceChanges: balanceChanges,
            approvalChanges: approvalChanges,
            nftTransfers: [],
            riskWarnings: warnings,
            gasUsed: gasUsed,
            revertReason: revertReason
        )
    }

    private func parseAssetChange(_ change: [String: Any], from: String) -> BalanceChange? {
        guard let rawAmount = change["amount"] as? String,
              let type = change["type"] as? String else {
            return nil
        }

        let amount = BigInt(rawAmount) ?? BigInt(0)
        let toAddress = (change["to"] as? String)?.lowercased()
        let isIncoming = toAddress == from.lowercased()
        let signedAmount = isIncoming ? amount : -amount

        let asset: BalanceChangeAsset
        if type == "ETH" || type == "native" {
            asset = .eth
        } else {
            let symbol = change["symbol"] as? String ?? "???"
            let address = change["token_address"] as? String ?? ""
            let decimals = change["decimals"] as? Int ?? 18
            asset = .token(symbol: symbol, address: address, decimals: decimals)
        }

        return BalanceChange(
            asset: asset,
            amount: signedAmount,
            formattedAmount: formatAmount(signedAmount, asset: asset),
            usdValue: change["dollar_value"] as? Double
        )
    }

    private func parseApprovalLog(_ log: [String: Any]) -> ApprovalChange? {
        // Check if this is an Approval event (topic0 = keccak256("Approval(address,address,uint256)"))
        guard let topics = log["topics"] as? [String],
              topics.count >= 3,
              topics[0] == "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925" else {
            return nil
        }

        let tokenAddress = log["address"] as? String ?? ""
        let spender = "0x" + topics[2].suffix(40)
        let data = log["data"] as? String ?? "0x0"
        let allowanceHex = data.hasPrefix("0x") ? String(data.dropFirst(2)) : data
        let allowance = BigUInt(allowanceHex, radix: 16) ?? BigUInt(0)

        let isUnlimited = allowance >= highApprovalThreshold
        let isRevoke = allowance == 0

        return ApprovalChange(
            token: knownContracts[tokenAddress.lowercased()] ?? "Token",
            tokenAddress: tokenAddress,
            spender: spender,
            spenderLabel: knownContracts[spender.lowercased()],
            allowance: allowance,
            isUnlimited: isUnlimited,
            isRevoke: isRevoke
        )
    }

    // MARK: - Local Analysis (Fallback)

    private func analyzeLocally(
        from: String,
        to: String,
        value: BigUInt,
        data: Data?,
        chainId: Int
    ) async -> SimulationResult {
        var balanceChanges: [BalanceChange] = []
        var approvalChanges: [ApprovalChange] = []
        var warnings: [SimulationRiskWarning] = []

        // ETH value transfer
        if value > 0 {
            let formattedValue = formatWei(value)
            balanceChanges.append(BalanceChange(
                asset: .eth,
                amount: -BigInt(value),
                formattedAmount: "-\(formattedValue) ETH",
                usdValue: nil
            ))
        }

        // Analyze calldata
        if let data = data, data.count >= 4 {
            let selector = "0x" + data.prefix(4).toHexString()

            switch selector.lowercased() {
            case transferSelector:
                // ERC-20 transfer
                if data.count >= 68 {
                    let recipientHex = data[16..<36].toHexString()
                    let amountHex = data[36..<68].toHexString()
                    let amount = BigUInt(amountHex, radix: 16) ?? BigUInt(0)

                    balanceChanges.append(BalanceChange(
                        asset: .token(symbol: "Token", address: to, decimals: 18),
                        amount: -BigInt(amount),
                        formattedAmount: "Token transfer",
                        usdValue: nil
                    ))
                }

            case approveSelector:
                // ERC-20 approval
                if data.count >= 68 {
                    let spenderHex = "0x" + data[16..<36].toHexString()
                    let amountHex = data[36..<68].toHexString()
                    let allowance = BigUInt(amountHex, radix: 16) ?? BigUInt(0)

                    let isUnlimited = allowance >= highApprovalThreshold

                    approvalChanges.append(ApprovalChange(
                        token: knownContracts[to.lowercased()] ?? "Token",
                        tokenAddress: to,
                        spender: spenderHex,
                        spenderLabel: knownContracts[spenderHex.lowercased()],
                        allowance: allowance,
                        isUnlimited: isUnlimited,
                        isRevoke: allowance == 0
                    ))

                    if isUnlimited {
                        warnings.append(.unlimitedApproval(
                            token: knownContracts[to.lowercased()] ?? "Token",
                            spender: spenderHex
                        ))
                    }
                }

            default:
                break
            }
        }

        // Check for high value transactions
        if value > BigUInt(10).power(18) * 10 {  // > 10 ETH
            let ethValue = Double(value) / Double(BigUInt(10).power(18))
            let usdValue = ethValue * 2500  // Rough estimate
            if usdValue > 10000 {
                warnings.append(.highValueTransaction(usdValue: usdValue))
            }
        }

        // Add simulation limitation warning
        if warnings.isEmpty && balanceChanges.isEmpty && approvalChanges.isEmpty && data != nil && data!.count > 0 {
            warnings.append(.simulationFailed(reason: "Full simulation requires Tenderly API key"))
        }

        return SimulationResult(
            success: true,
            balanceChanges: balanceChanges,
            approvalChanges: approvalChanges,
            nftTransfers: [],
            riskWarnings: warnings,
            gasUsed: BigUInt(21000),  // Default gas
            revertReason: nil
        )
    }

    // MARK: - Helpers

    private func formatAmount(_ amount: BigInt, asset: BalanceChangeAsset) -> String {
        let decimals: Int
        switch asset {
        case .eth:
            decimals = 18
        case .token(_, _, let d):
            decimals = d
        }

        let divisor = BigInt(10).power(decimals)
        let whole = amount / divisor
        let frac = abs(amount) % divisor

        if frac == 0 {
            return "\(whole) \(asset.symbol)"
        }

        let fracStr = String(frac).prefix(4)
        return "\(whole).\(fracStr) \(asset.symbol)"
    }

    private func formatWei(_ wei: BigUInt) -> String {
        let divisor = BigUInt(10).power(18)
        let whole = wei / divisor
        let frac = wei % divisor

        if frac == 0 {
            return whole.description
        }

        let fracStr = String(frac).prefix(4)
        return "\(whole).\(fracStr)"
    }

    /// Get label for a known contract address
    func getContractLabel(_ address: String) -> String? {
        knownContracts[address.lowercased()]
    }
}

// MARK: - Errors

enum SimulationError: Error, LocalizedError {
    case invalidConfiguration
    case invalidResponse
    case apiError(statusCode: Int)
    case parseError
    case notSupported

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid simulation configuration"
        case .invalidResponse:
            return "Invalid response from simulation service"
        case .apiError(let statusCode):
            return "Simulation API error (status: \(statusCode))"
        case .parseError:
            return "Failed to parse simulation response"
        case .notSupported:
            return "Simulation not supported for this transaction type"
        }
    }
}

// MARK: - BigInt Extension

private extension BigInt {
    init?(_ string: String) {
        if string.hasPrefix("0x") {
            self.init(String(string.dropFirst(2)), radix: 16)
        } else {
            self.init(string, radix: 10)
        }
    }

    func power(_ n: Int) -> BigInt {
        var result = BigInt(1)
        for _ in 0..<n {
            result *= 10
        }
        return result
    }
}
