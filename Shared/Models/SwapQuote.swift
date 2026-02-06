import Foundation
import BigInt

/// Represents a swap quote from 0x API
struct SwapQuote: Equatable {
    let sellToken: SwapToken
    let buyToken: SwapToken
    let sellAmount: BigUInt
    let buyAmount: BigUInt
    let price: Double
    let priceImpact: Double
    let estimatedGas: BigUInt
    let gasPrice: BigUInt
    let to: String  // Contract address to send tx to
    let data: Data  // Calldata for the swap
    let value: BigUInt  // ETH value to send (for selling ETH)
    let allowanceTarget: String?  // Address to approve tokens for
    let sources: [SwapSource]

    var formattedSellAmount: String {
        formatTokenAmount(sellAmount, decimals: sellToken.decimals, symbol: sellToken.symbol)
    }

    var formattedBuyAmount: String {
        formatTokenAmount(buyAmount, decimals: buyToken.decimals, symbol: buyToken.symbol)
    }

    var formattedPrice: String {
        String(format: "1 %@ = %.6f %@", sellToken.symbol, price, buyToken.symbol)
    }

    var formattedPriceImpact: String {
        if priceImpact < 0.01 {
            return "< 0.01%"
        }
        return String(format: "%.2f%%", priceImpact * 100)
    }

    var formattedGasCost: String {
        let gasCostWei = estimatedGas * gasPrice
        let divisor = BigUInt(10).power(18)
        let whole = gasCostWei / divisor
        let frac = gasCostWei % divisor

        if frac == 0 {
            return "\(whole) ETH"
        }

        let fracStr = String(frac).prefix(6)
        return "\(whole).\(fracStr) ETH"
    }

    var routeSummary: String {
        sources.map { $0.name }.joined(separator: " → ")
    }

    private func formatTokenAmount(_ amount: BigUInt, decimals: Int, symbol: String) -> String {
        let divisor = BigUInt(10).power(decimals)
        let whole = amount / divisor
        let frac = amount % divisor

        if frac == 0 {
            return "\(whole) \(symbol)"
        }

        let fracStr = String(frac).prefix(6)
        return "\(whole).\(fracStr) \(symbol)"
    }
}

/// Represents a token in a swap
struct SwapToken: Equatable {
    let address: String
    let symbol: String
    let name: String
    let decimals: Int

    /// Native ETH (represented as zero address)
    static let eth = SwapToken(
        address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
        symbol: "ETH",
        name: "Ethereum",
        decimals: 18
    )

    /// WETH on mainnet
    static let weth = SwapToken(
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        symbol: "WETH",
        name: "Wrapped Ether",
        decimals: 18
    )

    /// USDC on mainnet
    static let usdc = SwapToken(
        address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        symbol: "USDC",
        name: "USD Coin",
        decimals: 6
    )

    /// USDT on mainnet
    static let usdt = SwapToken(
        address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        symbol: "USDT",
        name: "Tether USD",
        decimals: 6
    )

    /// DAI on mainnet
    static let dai = SwapToken(
        address: "0x6B175474E89094C44Da98b954EedeCD5bad813",
        symbol: "DAI",
        name: "Dai Stablecoin",
        decimals: 18
    )

    var isNativeETH: Bool {
        address.lowercased() == "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
    }
}

/// Source of liquidity in a swap route
struct SwapSource: Equatable {
    let name: String
    let proportion: Double  // 0.0 to 1.0
}

/// Slippage tolerance options
enum SlippageTolerance: Double, CaseIterable, Identifiable {
    case low = 0.001      // 0.1%
    case medium = 0.005   // 0.5%
    case high = 0.01      // 1.0%
    case veryHigh = 0.03  // 3.0%

    var id: Double { rawValue }

    var displayName: String {
        String(format: "%.1f%%", rawValue * 100)
    }

    var basisPoints: Int {
        Int(rawValue * 10000)
    }
}
