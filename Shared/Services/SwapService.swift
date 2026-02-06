import Foundation
import BigInt

/// Service for token swaps via 0x API
final class SwapService {
    static let shared = SwapService()

    /// 0x API base URL
    private let apiBaseURL = "https://api.0x.org"

    /// Supported chain IDs
    private let supportedChains: Set<Int> = [1, 8453] // Ethereum mainnet, Base

    /// Common tokens by chain
    private let tokensByChain: [Int: [SwapToken]] = [
        1: [.eth, .weth, .usdc, .usdt, .dai],
        8453: [
            SwapToken(address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", symbol: "ETH", name: "Ethereum", decimals: 18),
            SwapToken(address: "0x4200000000000000000000000000000000000006", symbol: "WETH", name: "Wrapped Ether", decimals: 18),
            SwapToken(address: "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", symbol: "USDC", name: "USD Coin", decimals: 6)
        ]
    ]

    private var web3Service: Web3Service

    private init() {
        self.web3Service = Web3Service()
    }

    // MARK: - Public API

    /// Get available tokens for swapping on a chain
    func getAvailableTokens(chainId: Int) -> [SwapToken] {
        tokensByChain[chainId] ?? []
    }

    /// Check if swapping is supported on a chain
    func isSupported(chainId: Int) -> Bool {
        supportedChains.contains(chainId)
    }

    /// Get a swap quote
    func getQuote(
        sellToken: SwapToken,
        buyToken: SwapToken,
        sellAmount: BigUInt,
        takerAddress: String,
        slippage: SlippageTolerance,
        chainId: Int
    ) async throws -> SwapQuote {
        guard isSupported(chainId: chainId) else {
            throw SwapError.unsupportedChain(chainId)
        }

        let chainPath = chainId == 1 ? "" : "/\(getChainName(chainId))"
        let baseURL = "\(apiBaseURL)\(chainPath)/swap/v1/quote"

        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "sellToken", value: sellToken.address),
            URLQueryItem(name: "buyToken", value: buyToken.address),
            URLQueryItem(name: "sellAmount", value: sellAmount.description),
            URLQueryItem(name: "takerAddress", value: takerAddress),
            URLQueryItem(name: "slippagePercentage", value: String(slippage.rawValue))
        ]

        guard let url = urlComponents.url else {
            throw SwapError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwapError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 400 {
            if let errorResponse = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let reason = errorResponse["reason"] as? String {
                throw SwapError.quoteError(reason)
            }
            throw SwapError.quoteError("Invalid request")
        }

        guard httpResponse.statusCode == 200 else {
            throw SwapError.networkError("HTTP \(httpResponse.statusCode)")
        }

        return try parseQuoteResponse(data, sellToken: sellToken, buyToken: buyToken)
    }

    /// Get a price estimate (no calldata, just for display)
    func getPrice(
        sellToken: SwapToken,
        buyToken: SwapToken,
        sellAmount: BigUInt,
        chainId: Int
    ) async throws -> SwapQuote {
        guard isSupported(chainId: chainId) else {
            throw SwapError.unsupportedChain(chainId)
        }

        let chainPath = chainId == 1 ? "" : "/\(getChainName(chainId))"
        let baseURL = "\(apiBaseURL)\(chainPath)/swap/v1/price"

        var urlComponents = URLComponents(string: baseURL)!
        urlComponents.queryItems = [
            URLQueryItem(name: "sellToken", value: sellToken.address),
            URLQueryItem(name: "buyToken", value: buyToken.address),
            URLQueryItem(name: "sellAmount", value: sellAmount.description)
        ]

        guard let url = urlComponents.url else {
            throw SwapError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SwapError.networkError("Failed to get price")
        }

        return try parseQuoteResponse(data, sellToken: sellToken, buyToken: buyToken)
    }

    /// Check if approval is needed for a swap
    func needsApproval(
        token: SwapToken,
        owner: String,
        spender: String,
        amount: BigUInt
    ) async throws -> Bool {
        // Native ETH doesn't need approval
        if token.isNativeETH {
            return false
        }

        let allowance = try await getAllowance(token: token.address, owner: owner, spender: spender)
        return allowance < amount
    }

    /// Get current allowance
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

    /// Build approval transaction
    func buildApprovalTransaction(
        token: String,
        spender: String,
        amount: BigUInt,
        from: String
    ) async throws -> (to: String, data: Data, value: BigUInt) {
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

        return (to: token, data: calldata, value: BigUInt(0))
    }

    /// Execute a swap
    func executeSwap(
        quote: SwapQuote,
        from: String,
        privateKey: Data
    ) async throws -> String {
        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: quote.to,
            value: quote.value,
            data: quote.data
        )

        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    /// Switch the network
    func switchNetwork(_ network: Network) {
        self.web3Service = Web3Service(network: network)
    }

    // MARK: - Private Helpers

    private func parseQuoteResponse(_ data: Data, sellToken: SwapToken, buyToken: SwapToken) throws -> SwapQuote {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SwapError.parseError
        }

        guard let sellAmountStr = json["sellAmount"] as? String,
              let buyAmountStr = json["buyAmount"] as? String,
              let sellAmount = BigUInt(sellAmountStr),
              let buyAmount = BigUInt(buyAmountStr) else {
            throw SwapError.parseError
        }

        let priceStr = json["price"] as? String ?? "0"
        let price = Double(priceStr) ?? 0

        let estimatedPriceImpact = json["estimatedPriceImpact"] as? String ?? "0"
        let priceImpact = Double(estimatedPriceImpact) ?? 0

        let gasStr = json["estimatedGas"] as? String ?? json["gas"] as? String ?? "0"
        let estimatedGas = BigUInt(gasStr) ?? BigUInt(0)

        let gasPriceStr = json["gasPrice"] as? String ?? "0"
        let gasPrice = BigUInt(gasPriceStr) ?? BigUInt(0)

        let to = json["to"] as? String ?? ""
        let dataHex = json["data"] as? String ?? "0x"
        let txData = Data(hexString: dataHex) ?? Data()

        let valueStr = json["value"] as? String ?? "0"
        let value = BigUInt(valueStr) ?? BigUInt(0)

        let allowanceTarget = json["allowanceTarget"] as? String

        // Parse sources
        var sources: [SwapSource] = []
        if let sourcesArray = json["sources"] as? [[String: Any]] {
            for source in sourcesArray {
                if let name = source["name"] as? String,
                   let proportionStr = source["proportion"] as? String,
                   let proportion = Double(proportionStr),
                   proportion > 0 {
                    sources.append(SwapSource(name: name, proportion: proportion))
                }
            }
        }

        return SwapQuote(
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            price: price,
            priceImpact: priceImpact,
            estimatedGas: estimatedGas,
            gasPrice: gasPrice,
            to: to,
            data: txData,
            value: value,
            allowanceTarget: allowanceTarget,
            sources: sources
        )
    }

    private func getChainName(_ chainId: Int) -> String {
        switch chainId {
        case 8453:
            return "base"
        default:
            return "ethereum"
        }
    }
}

// MARK: - Errors

enum SwapError: Error, LocalizedError {
    case unsupportedChain(Int)
    case invalidRequest
    case networkError(String)
    case quoteError(String)
    case parseError
    case insufficientBalance
    case approvalFailed(String)
    case swapFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let chainId):
            return "Swaps not supported on chain ID \(chainId)"
        case .invalidRequest:
            return "Invalid swap request"
        case .networkError(let message):
            return "Network error: \(message)"
        case .quoteError(let reason):
            return "Quote error: \(reason)"
        case .parseError:
            return "Failed to parse swap response"
        case .insufficientBalance:
            return "Insufficient balance for swap"
        case .approvalFailed(let reason):
            return "Approval failed: \(reason)"
        case .swapFailed(let reason):
            return "Swap failed: \(reason)"
        }
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
