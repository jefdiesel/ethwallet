import Foundation
import BigInt

/// Service for fetching transaction history
final class TransactionHistoryService {
    static let shared = TransactionHistoryService()

    /// Etherscan-compatible API URLs by chain ID
    private let apiURLs: [Int: String] = [
        1: "https://api.etherscan.io/api",
        8453: "https://api.basescan.org/api",
        11155111: "https://api-sepolia.etherscan.io/api"
    ]

    /// Known contract signatures for transaction type detection
    private let knownSignatures: [String: TxActivityType] = [
        "0xa9059cbb": .tokenTransfer,    // transfer(address,uint256)
        "0x23b872dd": .tokenTransfer,    // transferFrom(address,address,uint256)
        "0x095ea7b3": .approval,         // approve(address,uint256)
        "0x7ff36ab5": .swap,             // swapExactETHForTokens
        "0x38ed1739": .swap,             // swapExactTokensForTokens
        "0x18cbafe5": .swap,             // swapExactTokensForETH
        "0x8803dbee": .swap,             // swapTokensForExactTokens
        "0xfb3bdb41": .swap,             // swapETHForExactTokens
        "0x5c11d795": .swap,             // swapExactTokensForTokensSupportingFeeOnTransferTokens
        "0x0d0e30db": .wrap,             // deposit (WETH)
        "0x2e1a7d4d": .unwrap,           // withdraw (WETH)
        "0xab834bab": .nftTransfer,      // atomicMatch_ (OpenSea)
        "0xfb0f3ee1": .nftTransfer,      // fulfillBasicOrder (Seaport)
    ]

    private init() {}

    // MARK: - Public API

    /// Fetch transaction history for an address
    func getTransactionHistory(
        for address: String,
        chainId: Int = 1,
        page: Int = 1,
        pageSize: Int = 50
    ) async throws -> [TxHistoryEntry] {
        guard let apiURL = apiURLs[chainId] else {
            throw TransactionHistoryError.unsupportedChain(chainId)
        }

        let offset = (page - 1) * pageSize

        // Fetch normal transactions
        async let normalTxs = fetchNormalTransactions(
            apiURL: apiURL,
            address: address,
            page: page,
            pageSize: pageSize
        )

        // Fetch internal transactions
        async let internalTxs = fetchInternalTransactions(
            apiURL: apiURL,
            address: address,
            page: page,
            pageSize: pageSize
        )

        // Fetch ERC-20 token transfers
        async let tokenTxs = fetchTokenTransfers(
            apiURL: apiURL,
            address: address,
            page: page,
            pageSize: pageSize
        )

        // Combine and sort by timestamp
        var allTransactions: [TxHistoryEntry] = []
        allTransactions.append(contentsOf: try await normalTxs)
        allTransactions.append(contentsOf: try await internalTxs)
        allTransactions.append(contentsOf: try await tokenTxs)

        // Remove duplicates (by hash) and sort by timestamp descending
        var seenHashes = Set<String>()
        let uniqueTransactions = allTransactions.filter { tx in
            if seenHashes.contains(tx.hash) {
                return false
            }
            seenHashes.insert(tx.hash)
            return true
        }

        return uniqueTransactions.sorted { $0.timestamp > $1.timestamp }
    }

    /// Fetch a single transaction by hash
    func getTransaction(hash: String, chainId: Int = 1) async throws -> TxHistoryEntry? {
        guard let apiURL = apiURLs[chainId] else {
            throw TransactionHistoryError.unsupportedChain(chainId)
        }

        let urlString = "\(apiURL)?module=proxy&action=eth_getTransactionByHash&txhash=\(hash)"
        guard let url = URL(string: urlString) else {
            throw TransactionHistoryError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else {
            return nil
        }

        return parseTransactionResult(result, userAddress: "")
    }

    // MARK: - Fetch Methods

    private func fetchNormalTransactions(
        apiURL: String,
        address: String,
        page: Int,
        pageSize: Int
    ) async throws -> [TxHistoryEntry] {
        let urlString = "\(apiURL)?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&page=\(page)&offset=\(pageSize)&sort=desc"

        guard let url = URL(string: urlString) else {
            throw TransactionHistoryError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []
        }

        return result.compactMap { parseNormalTransaction($0, userAddress: address) }
    }

    private func fetchInternalTransactions(
        apiURL: String,
        address: String,
        page: Int,
        pageSize: Int
    ) async throws -> [TxHistoryEntry] {
        let urlString = "\(apiURL)?module=account&action=txlistinternal&address=\(address)&startblock=0&endblock=99999999&page=\(page)&offset=\(pageSize)&sort=desc"

        guard let url = URL(string: urlString) else {
            throw TransactionHistoryError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []
        }

        return result.compactMap { parseInternalTransaction($0, userAddress: address) }
    }

    private func fetchTokenTransfers(
        apiURL: String,
        address: String,
        page: Int,
        pageSize: Int
    ) async throws -> [TxHistoryEntry] {
        let urlString = "\(apiURL)?module=account&action=tokentx&address=\(address)&startblock=0&endblock=99999999&page=\(page)&offset=\(pageSize)&sort=desc"

        guard let url = URL(string: urlString) else {
            throw TransactionHistoryError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [[String: Any]] else {
            return []
        }

        return result.compactMap { parseTokenTransfer($0, userAddress: address) }
    }

    // MARK: - Parsing

    private func parseNormalTransaction(_ tx: [String: Any], userAddress: String) -> TxHistoryEntry? {
        guard let hash = tx["hash"] as? String,
              let from = tx["from"] as? String,
              let to = tx["to"] as? String,
              let valueStr = tx["value"] as? String,
              let timestampStr = tx["timeStamp"] as? String,
              let timestamp = TimeInterval(timestampStr) else {
            return nil
        }

        let value = BigUInt(valueStr) ?? BigUInt(0)
        let isError = tx["isError"] as? String == "1"
        let input = tx["input"] as? String ?? "0x"
        let gasUsed = BigUInt(tx["gasUsed"] as? String ?? "0") ?? BigUInt(0)
        let gasPrice = BigUInt(tx["gasPrice"] as? String ?? "0") ?? BigUInt(0)

        let type = detectTxActivityType(input: input, from: from, to: to, value: value, userAddress: userAddress)
        let isOutgoing = from.lowercased() == userAddress.lowercased()

        return TxHistoryEntry(
            hash: hash,
            from: from,
            to: to,
            value: value,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: isError ? .failed : .confirmed,
            type: type,
            tokenSymbol: nil,
            tokenDecimals: nil,
            gasUsed: gasUsed,
            gasPrice: gasPrice,
            isOutgoing: isOutgoing
        )
    }

    private func parseInternalTransaction(_ tx: [String: Any], userAddress: String) -> TxHistoryEntry? {
        guard let hash = tx["hash"] as? String,
              let from = tx["from"] as? String,
              let to = tx["to"] as? String,
              let valueStr = tx["value"] as? String,
              let timestampStr = tx["timeStamp"] as? String,
              let timestamp = TimeInterval(timestampStr) else {
            return nil
        }

        let value = BigUInt(valueStr) ?? BigUInt(0)
        let isError = tx["isError"] as? String == "1"
        let isOutgoing = from.lowercased() == userAddress.lowercased()

        return TxHistoryEntry(
            hash: hash,
            from: from,
            to: to,
            value: value,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: isError ? .failed : .confirmed,
            type: isOutgoing ? .send : .receive,
            tokenSymbol: nil,
            tokenDecimals: nil,
            gasUsed: BigUInt(0),
            gasPrice: BigUInt(0),
            isOutgoing: isOutgoing
        )
    }

    private func parseTokenTransfer(_ tx: [String: Any], userAddress: String) -> TxHistoryEntry? {
        guard let hash = tx["hash"] as? String,
              let from = tx["from"] as? String,
              let to = tx["to"] as? String,
              let valueStr = tx["value"] as? String,
              let timestampStr = tx["timeStamp"] as? String,
              let timestamp = TimeInterval(timestampStr),
              let tokenSymbol = tx["tokenSymbol"] as? String else {
            return nil
        }

        let value = BigUInt(valueStr) ?? BigUInt(0)
        let decimals = Int(tx["tokenDecimal"] as? String ?? "18") ?? 18
        let isOutgoing = from.lowercased() == userAddress.lowercased()

        return TxHistoryEntry(
            hash: hash,
            from: from,
            to: to,
            value: value,
            timestamp: Date(timeIntervalSince1970: timestamp),
            status: .confirmed,
            type: .tokenTransfer,
            tokenSymbol: tokenSymbol,
            tokenDecimals: decimals,
            gasUsed: BigUInt(0),
            gasPrice: BigUInt(0),
            isOutgoing: isOutgoing
        )
    }

    private func parseTransactionResult(_ tx: [String: Any], userAddress: String) -> TxHistoryEntry? {
        guard let hash = tx["hash"] as? String,
              let from = tx["from"] as? String,
              let to = tx["to"] as? String else {
            return nil
        }

        let valueHex = tx["value"] as? String ?? "0x0"
        let value = BigUInt(valueHex.dropFirst(2), radix: 16) ?? BigUInt(0)
        let input = tx["input"] as? String ?? "0x"

        let type = detectTxActivityType(input: input, from: from, to: to, value: value, userAddress: userAddress)
        let isOutgoing = from.lowercased() == userAddress.lowercased()

        return TxHistoryEntry(
            hash: hash,
            from: from,
            to: to,
            value: value,
            timestamp: Date(),
            status: .pending,
            type: type,
            tokenSymbol: nil,
            tokenDecimals: nil,
            gasUsed: BigUInt(0),
            gasPrice: BigUInt(0),
            isOutgoing: isOutgoing
        )
    }

    private func detectTxActivityType(
        input: String,
        from: String,
        to: String,
        value: BigUInt,
        userAddress: String
    ) -> TxActivityType {
        // Check function signature
        if input.count >= 10 {
            let selector = String(input.prefix(10)).lowercased()
            if let type = knownSignatures[selector] {
                return type
            }
        }

        // Simple ETH transfer
        if input == "0x" || input.isEmpty {
            if from.lowercased() == userAddress.lowercased() {
                return .send
            } else {
                return .receive
            }
        }

        // Contract interaction
        return .contract
    }
}

// MARK: - Models

struct TxHistoryEntry: Identifiable {
    let hash: String
    let from: String
    let to: String
    let value: BigUInt
    let timestamp: Date
    let status: TransactionStatus
    let type: TxActivityType
    let tokenSymbol: String?
    let tokenDecimals: Int?
    let gasUsed: BigUInt
    let gasPrice: BigUInt
    let isOutgoing: Bool

    var id: String { hash }

    var formattedValue: String {
        if let symbol = tokenSymbol, let decimals = tokenDecimals {
            return formatTokenValue(value, decimals: decimals, symbol: symbol)
        }
        return formatETHValue(value)
    }

    var gasCost: BigUInt {
        gasUsed * gasPrice
    }

    var shortHash: String {
        guard hash.count > 12 else { return hash }
        return "\(hash.prefix(6))...\(hash.suffix(4))"
    }

    var shortFrom: String {
        guard from.count > 12 else { return from }
        return "\(from.prefix(6))...\(from.suffix(4))"
    }

    var shortTo: String {
        guard to.count > 12 else { return to }
        return "\(to.prefix(6))...\(to.suffix(4))"
    }

    private func formatETHValue(_ wei: BigUInt) -> String {
        let divisor = BigUInt(10).power(18)
        let whole = wei / divisor
        let frac = wei % divisor

        if frac == 0 {
            return "\(whole) ETH"
        }

        let fracStr = String(frac).prefix(4)
        return "\(whole).\(fracStr) ETH"
    }

    private func formatTokenValue(_ amount: BigUInt, decimals: Int, symbol: String) -> String {
        let divisor = BigUInt(10).power(decimals)
        let whole = amount / divisor
        let frac = amount % divisor

        if frac == 0 {
            return "\(whole) \(symbol)"
        }

        let fracStr = String(frac).prefix(4)
        return "\(whole).\(fracStr) \(symbol)"
    }
}

enum TxActivityType: String {
    case send
    case receive
    case swap
    case approval
    case tokenTransfer
    case nftTransfer
    case wrap
    case unwrap
    case contract

    var displayName: String {
        switch self {
        case .send: return "Send"
        case .receive: return "Receive"
        case .swap: return "Swap"
        case .approval: return "Approval"
        case .tokenTransfer: return "Token Transfer"
        case .nftTransfer: return "NFT Transfer"
        case .wrap: return "Wrap"
        case .unwrap: return "Unwrap"
        case .contract: return "Contract"
        }
    }

    var icon: String {
        switch self {
        case .send: return "arrow.up.circle"
        case .receive: return "arrow.down.circle"
        case .swap: return "arrow.triangle.2.circlepath"
        case .approval: return "checkmark.seal"
        case .tokenTransfer: return "arrow.left.arrow.right"
        case .nftTransfer: return "photo"
        case .wrap: return "gift"
        case .unwrap: return "gift.fill"
        case .contract: return "doc.text"
        }
    }
}

// MARK: - Errors

enum TransactionHistoryError: Error, LocalizedError {
    case unsupportedChain(Int)
    case invalidURL
    case networkError(String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .unsupportedChain(let chainId):
            return "Transaction history not supported for chain ID \(chainId)"
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let message):
            return "Network error: \(message)"
        case .parseError:
            return "Failed to parse transaction data"
        }
    }
}
