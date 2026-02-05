import Foundation

/// Represents an ERC-20 token
struct Token: Identifiable, Codable, Hashable {
    /// Contract address
    let address: String

    /// Token symbol (e.g., "USDC")
    let symbol: String

    /// Token name (e.g., "USD Coin")
    let name: String

    /// Number of decimals
    let decimals: Int

    /// Optional logo URL
    let logoURL: URL?

    /// Chain ID this token is on
    let chainId: Int

    var id: String { "\(chainId):\(address)" }

    // MARK: - Common Tokens

    static let usdc = Token(
        address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        symbol: "USDC",
        name: "USD Coin",
        decimals: 6,
        logoURL: nil,
        chainId: 1
    )

    static let usdt = Token(
        address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
        symbol: "USDT",
        name: "Tether USD",
        decimals: 6,
        logoURL: nil,
        chainId: 1
    )

    static let weth = Token(
        address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        symbol: "WETH",
        name: "Wrapped Ether",
        decimals: 18,
        logoURL: nil,
        chainId: 1
    )

    static let dai = Token(
        address: "0x6B175474E89094C44Da98b954EescdeCB5bad813",
        symbol: "DAI",
        name: "Dai Stablecoin",
        decimals: 18,
        logoURL: nil,
        chainId: 1
    )
}

/// Token balance for display
struct TokenBalance: Identifiable {
    let token: Token
    let rawBalance: String  // Raw balance as hex or decimal string
    let formattedBalance: String  // Human readable with decimals
    let usdValue: Double?

    var id: String { token.id }

    var hasBalance: Bool {
        formattedBalance != "0" && formattedBalance != "0.0"
    }
}
