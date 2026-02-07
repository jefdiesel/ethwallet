import Foundation

/// Represents an EVM-compatible blockchain network
struct Network: Identifiable, Codable, Hashable {
    let id: Int                    // chainId
    let name: String
    let rpcURL: URL
    let currencySymbol: String
    let explorerURL: URL?
    let isTestnet: Bool

    /// Flashbots RPC URL for MEV protection (only available on Ethereum mainnet)
    var flashbotsRPCURL: URL? {
        guard id == 1 else { return nil }
        return URL(string: "https://rpc.flashbots.net")
    }

    /// Whether this network supports MEV protection via Flashbots
    var supportsMEVProtection: Bool {
        return id == 1 // Only Ethereum mainnet
    }

    // MARK: - RPC URL Helpers

    /// Get RPC URL with API key from Keychain if available
    static func rpcURL(for chainId: Int) -> URL {
        let alchemyKey = KeychainService.shared.retrieveAPIKey(for: "alchemy")

        switch chainId {
        case 1: // Ethereum
            if let key = alchemyKey {
                return URL(string: "https://eth-mainnet.g.alchemy.com/v2/\(key)")!
            }
            return URL(string: "https://eth.llamarpc.com")! // Public fallback
        case 11155111: // Sepolia
            if let key = alchemyKey {
                return URL(string: "https://eth-sepolia.g.alchemy.com/v2/\(key)")!
            }
            return URL(string: "https://ethereum-sepolia-rpc.publicnode.com")!
        case 8453: // Base
            return URL(string: "https://mainnet.base.org")!
        default:
            return URL(string: "https://eth.llamarpc.com")!
        }
    }

    // MARK: - Default Networks

    static var ethereum: Network {
        Network(
            id: 1,
            name: "Ethereum",
            rpcURL: rpcURL(for: 1),
            currencySymbol: "ETH",
            explorerURL: URL(string: "https://etherscan.io"),
            isTestnet: false
        )
    }

    static var sepolia: Network {
        Network(
            id: 11155111,
            name: "Sepolia",
            rpcURL: rpcURL(for: 11155111),
            currencySymbol: "ETH",
            explorerURL: URL(string: "https://sepolia.etherscan.io"),
            isTestnet: true
        )
    }

    static var base: Network {
        Network(
            id: 8453,
            name: "Base",
            rpcURL: rpcURL(for: 8453),
            currencySymbol: "ETH",
            explorerURL: URL(string: "https://basescan.org"),
            isTestnet: false
        )
    }

    static var defaults: [Network] { [.ethereum, .sepolia, .base] }

    /// Get network for a specific chain ID
    static func forChainId(_ chainId: Int) -> Network? {
        switch chainId {
        case 1: return .ethereum
        case 11155111: return .sepolia
        case 8453: return .base
        default: return nil
        }
    }

    // MARK: - Ethscriptions AppChain (L2 for queries)

    static let appChain = Network(
        id: 0, // Custom identifier for AppChain
        name: "Ethscriptions AppChain",
        rpcURL: URL(string: "https://mainnet.ethscriptions.com")!,
        currencySymbol: "ETH",
        explorerURL: URL(string: "https://explorer.ethscriptions.com"),
        isTestnet: false
    )

    // MARK: - Helpers

    func explorerTransactionURL(_ txHash: String) -> URL? {
        explorerURL?.appendingPathComponent("tx/\(txHash)")
    }

    func explorerAddressURL(_ address: String) -> URL? {
        explorerURL?.appendingPathComponent("address/\(address)")
    }
}

// MARK: - Custom Network Support

extension Network {
    init(
        chainId: Int,
        name: String,
        rpcURLString: String,
        currencySymbol: String = "ETH",
        explorerURLString: String? = nil,
        isTestnet: Bool = false
    ) {
        self.id = chainId
        self.name = name
        self.rpcURL = URL(string: rpcURLString)!
        self.currencySymbol = currencySymbol
        self.explorerURL = explorerURLString.flatMap { URL(string: $0) }
        self.isTestnet = isTestnet
    }
}
