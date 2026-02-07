import Foundation
import BigInt

/// Service for interacting with ERC-4337 bundlers (Pimlico)
/// Handles UserOperation submission and status tracking
final class BundlerService {
    private let apiKey: String
    private var chainId: Int

    private let keychainService: KeychainService

    // MARK: - Initialization

    init(chainId: Int, keychainService: KeychainService = .shared) {
        self.chainId = chainId
        self.keychainService = keychainService
        self.apiKey = keychainService.retrieveAPIKey(for: "pimlico") ?? ""
    }

    // MARK: - Configuration

    /// Bundler RPC URL
    var bundlerURL: URL {
        URL(string: "https://api.pimlico.io/v2/\(chainId)/rpc?apikey=\(apiKey)")!
    }

    /// Update the chain ID
    func switchChain(_ chainId: Int) {
        self.chainId = chainId
    }

    /// Store API key
    func setAPIKey(_ key: String) throws {
        try keychainService.storeAPIKey(key, for: "pimlico")
    }

    /// Check if API key is configured
    var hasAPIKey: Bool {
        keychainService.retrieveAPIKey(for: "pimlico") != nil
    }

    // MARK: - UserOperation Methods

    /// Send a UserOperation to the bundler
    /// - Parameter userOp: The signed UserOperation
    /// - Returns: UserOperation hash
    func sendUserOperation(_ userOp: UserOperation) async throws -> String {
        let userOpDict = userOp.toRPCDict()

        #if DEBUG
        if let jsonData = try? JSONSerialization.data(withJSONObject: userOpDict, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("[Bundler] Sending UserOp:\n\(jsonString)")
        }
        #endif

        let params: [Any] = [
            userOpDict,
            ERC4337Constants.entryPoint
        ]

        let result = try await rpcCall(method: "eth_sendUserOperation", params: params)

        guard let hash = result as? String else {
            throw BundlerError.invalidResponse("Expected string hash")
        }

        return hash
    }

    /// Get UserOperation receipt by hash
    /// - Parameter hash: The UserOperation hash
    /// - Returns: Receipt if operation is complete, nil if pending
    func getUserOperationReceipt(_ hash: String) async throws -> UserOperationReceipt? {
        let params: [Any] = [hash]

        let result = try await rpcCall(method: "eth_getUserOperationReceipt", params: params)

        // Null result means still pending
        if result is NSNull {
            return nil
        }

        guard let dict = result as? [String: Any] else {
            throw BundlerError.invalidResponse("Expected receipt object")
        }

        // Convert dictionary to JSON Data and decode
        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(UserOperationReceipt.self, from: jsonData)
    }

    /// Get UserOperation by hash
    /// - Parameter hash: The UserOperation hash
    /// - Returns: UserOperation if found
    func getUserOperationByHash(_ hash: String) async throws -> UserOperation? {
        let params: [Any] = [hash]

        let result = try await rpcCall(method: "eth_getUserOperationByHash", params: params)

        if result is NSNull {
            return nil
        }

        guard let dict = result as? [String: Any],
              let userOpDict = dict["userOperation"] as? [String: Any] else {
            throw BundlerError.invalidResponse("Expected userOperation object")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: userOpDict)
        return try JSONDecoder().decode(UserOperation.self, from: jsonData)
    }

    /// Estimate gas for a UserOperation
    /// - Parameter userOp: The UserOperation (without gas values)
    /// - Returns: Gas estimates
    func estimateUserOperationGas(_ userOp: UserOperation) async throws -> UserOperationGasEstimate {
        let params: [Any] = [
            userOp.toRPCDict(),
            ERC4337Constants.entryPoint
        ]

        let result = try await rpcCall(method: "eth_estimateUserOperationGas", params: params)

        guard let dict = result as? [String: Any] else {
            throw BundlerError.invalidResponse("Expected gas estimate object")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(UserOperationGasEstimate.self, from: jsonData)
    }

    /// Get supported entry points
    /// - Returns: List of supported EntryPoint addresses
    func getSupportedEntryPoints() async throws -> [String] {
        let result = try await rpcCall(method: "eth_supportedEntryPoints", params: [])

        guard let entryPoints = result as? [String] else {
            throw BundlerError.invalidResponse("Expected array of entry points")
        }

        return entryPoints
    }

    /// Get chain ID from bundler
    /// - Returns: Chain ID as hex string
    func getChainId() async throws -> Int {
        let result = try await rpcCall(method: "eth_chainId", params: [])

        guard let hexChainId = result as? String else {
            throw BundlerError.invalidResponse("Expected chain ID string")
        }

        let cleanHex = hexChainId.hasPrefix("0x") ? String(hexChainId.dropFirst(2)) : hexChainId
        guard let chainId = Int(cleanHex, radix: 16) else {
            throw BundlerError.invalidResponse("Invalid chain ID format")
        }

        return chainId
    }

    // MARK: - Pimlico-Specific Methods

    /// Get UserOperation status (Pimlico extension)
    /// - Parameter hash: The UserOperation hash
    /// - Returns: Current status
    func getUserOperationStatus(_ hash: String) async throws -> PimlicoUserOpStatus {
        let params: [Any] = [hash]

        let result = try await rpcCall(method: "pimlico_getUserOperationStatus", params: params)

        guard let dict = result as? [String: Any] else {
            throw BundlerError.invalidResponse("Expected status object")
        }

        return PimlicoUserOpStatus(from: dict)
    }

    /// Get gas prices from Pimlico
    /// - Returns: Current gas prices
    func getGasPrices() async throws -> PimlicoGasPrices {
        let result = try await rpcCall(method: "pimlico_getUserOperationGasPrice", params: [])

        guard let dict = result as? [String: Any] else {
            throw BundlerError.invalidResponse("Expected gas price object")
        }

        return PimlicoGasPrices(from: dict)
    }

    // MARK: - Status Polling

    /// Wait for UserOperation to be confirmed
    /// - Parameters:
    ///   - hash: UserOperation hash
    ///   - timeout: Maximum wait time in seconds
    ///   - pollInterval: Time between status checks in seconds
    /// - Returns: Receipt when confirmed
    func waitForReceipt(
        _ hash: String,
        timeout: TimeInterval = 120,
        pollInterval: TimeInterval = 2
    ) async throws -> UserOperationReceipt {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let receipt = try await getUserOperationReceipt(hash) {
                return receipt
            }

            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }

        throw BundlerError.timeout
    }

    // MARK: - RPC Helper

    private func rpcCall(method: String, params: [Any]) async throws -> Any {
        guard !apiKey.isEmpty else {
            throw BundlerError.noAPIKey
        }

        #if DEBUG
        print("[Bundler] RPC: \(method)")
        #endif

        var request = URLRequest(url: bundlerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": Int.random(in: 1...1000000)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BundlerError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw BundlerError.httpError(httpResponse.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BundlerError.invalidResponse("Invalid JSON response")
        }

        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown error"
            #if DEBUG
            print("[Bundler] Error: \(code) - \(message)")
            #endif
            throw BundlerError.rpcError(code, message)
        }

        guard let result = json["result"] else {
            throw BundlerError.invalidResponse("Missing result field")
        }

        return result
    }
}

// MARK: - Pimlico Status Response

struct PimlicoUserOpStatus {
    let status: UserOperationStatus
    let transactionHash: String?

    init(from dict: [String: Any]) {
        let statusString = dict["status"] as? String ?? "pending"

        switch statusString.lowercased() {
        case "not_found":
            status = .pending
        case "submitted":
            status = .submitted
        case "pending":
            status = .pending
        case "included":
            status = .onChain
        case "succeeded":
            status = .confirmed
        case "reverted":
            status = .reverted
        case "failed":
            status = .failed
        default:
            status = .pending
        }

        transactionHash = dict["transactionHash"] as? String
    }
}

// MARK: - Pimlico Gas Prices

struct PimlicoGasPrices {
    let slow: GasPriceOption
    let standard: GasPriceOption
    let fast: GasPriceOption

    init(from dict: [String: Any]) {
        slow = GasPriceOption(from: dict["slow"] as? [String: Any] ?? [:])
        standard = GasPriceOption(from: dict["standard"] as? [String: Any] ?? [:])
        fast = GasPriceOption(from: dict["fast"] as? [String: Any] ?? [:])
    }

    struct GasPriceOption {
        let maxFeePerGas: BigUInt
        let maxPriorityFeePerGas: BigUInt

        init(from dict: [String: Any]) {
            let maxFeeHex = dict["maxFeePerGas"] as? String ?? "0x0"
            let priorityHex = dict["maxPriorityFeePerGas"] as? String ?? "0x0"

            maxFeePerGas = BigUInt(hexString: maxFeeHex) ?? 0
            maxPriorityFeePerGas = BigUInt(hexString: priorityHex) ?? 0
        }
    }
}

// MARK: - Bundler Errors

enum BundlerError: Error, LocalizedError {
    case noAPIKey
    case networkError(String)
    case httpError(Int, String)
    case invalidResponse(String)
    case rpcError(Int, String)
    case timeout
    case userOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Pimlico API key not configured"
        case .networkError(let message):
            return "Network error: \(message)"
        case .httpError(let code, let body):
            return "HTTP error \(code): \(body)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .rpcError(let code, let message):
            return "Bundler error (\(code)): \(message)"
        case .timeout:
            return "UserOperation confirmation timed out"
        case .userOperationFailed(let reason):
            return "UserOperation failed: \(reason)"
        }
    }

    /// Check if this is a known recoverable error
    var isRecoverable: Bool {
        switch self {
        case .networkError, .timeout:
            return true
        case .rpcError(let code, _):
            // -32602 is invalid params, might be recoverable
            return code == -32602
        default:
            return false
        }
    }
}

// MARK: - Bundler Chain Configuration

extension BundlerService {
    /// Chains supported by Pimlico
    static let supportedChains: Set<Int> = [
        1,        // Ethereum Mainnet
        11155111, // Sepolia
        8453,     // Base
        84531,    // Base Goerli
        137,      // Polygon
        80001,    // Mumbai
        42161,    // Arbitrum One
        421613,   // Arbitrum Goerli
        10,       // Optimism
        420,      // Optimism Goerli
    ]

    /// Check if chain is supported
    static func isChainSupported(_ chainId: Int) -> Bool {
        supportedChains.contains(chainId)
    }
}
