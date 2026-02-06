import Foundation
import BigInt

/// Service for MEV (Maximal Extractable Value) protection using Flashbots RPC
/// Protects transactions from front-running and sandwich attacks on Ethereum mainnet
final class MEVProtectionService {
    static let shared = MEVProtectionService()

    /// Flashbots Protect RPC endpoint
    private let flashbotsRPCURL = URL(string: "https://rpc.flashbots.net")!

    /// UserDefaults key for MEV protection setting
    private let mevEnabledKey = "mevProtectionEnabled"

    private init() {}

    // MARK: - Settings

    /// Whether MEV protection is enabled (default: true)
    var isEnabled: Bool {
        get {
            // Default to true if not set
            if UserDefaults.standard.object(forKey: mevEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: mevEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mevEnabledKey)
        }
    }

    // MARK: - MEV Protection

    /// Check if MEV protection should be used for the given chain
    /// Only Ethereum mainnet (chainId: 1) supports Flashbots
    func shouldUseMEVProtection(chainId: Int) -> Bool {
        return isEnabled && chainId == 1
    }

    /// Send a raw transaction through Flashbots Protect RPC
    /// - Parameters:
    ///   - rawTransaction: The signed transaction data as hex string
    /// - Returns: The transaction hash
    func sendProtectedTransaction(rawTransaction: Data) async throws -> String {
        var request = URLRequest(url: flashbotsRPCURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_sendRawTransaction",
            "params": ["0x" + rawTransaction.toHexString()],
            "id": Int.random(in: 1...1000000)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)

        #if DEBUG
        print("[MEV] Sending transaction through Flashbots Protect...")
        #endif

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MEVProtectionError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw MEVProtectionError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MEVProtectionError.invalidJSON
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown error"
            let code = error["code"] as? Int ?? -1
            throw MEVProtectionError.rpcError(code: code, message: message)
        }

        guard let result = json["result"] as? String else {
            throw MEVProtectionError.noTransactionHash
        }

        #if DEBUG
        print("[MEV] Transaction sent successfully via Flashbots: \(result)")
        #endif
        return result
    }

    /// Get transaction status from Flashbots
    /// Flashbots transactions may take longer to be included as they go through private mempool
    func getTransactionStatus(hash: String) async throws -> FlashbotsTransactionStatus {
        var request = URLRequest(url: flashbotsRPCURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "eth_getTransactionReceipt",
            "params": [hash],
            "id": Int.random(in: 1...1000000)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MEVProtectionError.invalidResponse
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MEVProtectionError.invalidJSON
        }

        if json["result"] == nil || json["result"] is NSNull {
            return .pending
        }

        guard let receipt = json["result"] as? [String: Any] else {
            return .pending
        }

        if let statusHex = receipt["status"] as? String {
            let status = statusHex == "0x1" ? FlashbotsTransactionStatus.confirmed : .failed
            return status
        }

        return .pending
    }
}

// MARK: - Transaction Status

enum FlashbotsTransactionStatus {
    case pending
    case confirmed
    case failed
}

// MARK: - Errors

enum MEVProtectionError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case invalidJSON
    case rpcError(code: Int, message: String)
    case noTransactionHash

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Flashbots RPC"
        case .httpError(let statusCode):
            return "HTTP error \(statusCode) from Flashbots RPC"
        case .invalidJSON:
            return "Invalid JSON response from Flashbots RPC"
        case .rpcError(let code, let message):
            return "Flashbots RPC error (\(code)): \(message)"
        case .noTransactionHash:
            return "No transaction hash returned from Flashbots"
        }
    }
}
