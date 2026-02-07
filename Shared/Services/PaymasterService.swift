import Foundation
import BigInt

/// Service for paymaster operations (gasless/sponsored transactions)
final class PaymasterService {
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

    /// Pimlico paymaster RPC URL
    var paymasterURL: URL {
        URL(string: "https://api.pimlico.io/v2/\(chainId)/rpc?apikey=\(apiKey)")!
    }

    /// Update the chain ID
    func switchChain(_ chainId: Int) {
        self.chainId = chainId
    }

    /// Check if paymaster is available (API key configured)
    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    // MARK: - Sponsorship

    /// Check if a UserOperation can be sponsored
    /// - Parameter userOp: The UserOperation to check
    /// - Returns: Whether sponsorship is available
    func canSponsor(_ userOp: UserOperation) async throws -> Bool {
        do {
            let _ = try await getPaymasterAndData(userOp: userOp)
            return true
        } catch PaymasterError.sponsorshipDenied {
            return false
        } catch {
            throw error
        }
    }

    /// Get paymaster data for a UserOperation
    /// - Parameters:
    ///   - userOp: The UserOperation to sponsor
    ///   - sponsorshipPolicy: Optional policy ID for specific sponsorship rules
    /// - Returns: Paymaster data to include in the UserOperation
    func getPaymasterAndData(
        userOp: UserOperation,
        sponsorshipPolicy: String? = nil
    ) async throws -> PaymasterDataResponse {
        var params: [Any] = [
            userOp.toRPCDict(),
            ERC4337Constants.entryPoint
        ]

        // Add sponsorship context if provided
        if let policy = sponsorshipPolicy {
            params.append([
                "sponsorshipPolicyId": policy
            ])
        }

        let result = try await rpcCall(
            method: "pm_sponsorUserOperation",
            params: params
        )

        guard let dict = result as? [String: Any] else {
            throw PaymasterError.invalidResponse("Expected paymaster data object")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(PaymasterDataResponse.self, from: jsonData)
    }

    /// Sponsor a UserOperation (modifies the UserOp with paymaster data)
    /// - Parameter userOp: The UserOperation to sponsor
    /// - Returns: Modified UserOperation with paymaster data
    func sponsorUserOperation(_ userOp: UserOperation) async throws -> UserOperation {
        let paymasterData = try await getPaymasterAndData(userOp: userOp)

        var sponsoredOp = userOp
        sponsoredOp.paymasterAndData = paymasterData.paymasterAndData

        // Update gas limits if provided
        if let preVer = paymasterData.preVerificationGas {
            sponsoredOp.preVerificationGas = preVer
        }
        if let verGas = paymasterData.verificationGasLimit {
            sponsoredOp.verificationGasLimit = verGas
        }
        if let callGas = paymasterData.callGasLimit {
            sponsoredOp.callGasLimit = callGas
        }

        return sponsoredOp
    }

    // MARK: - ERC-20 Paymaster

    /// Get accepted tokens for ERC-20 paymaster
    func getAcceptedTokens() async throws -> [PaymasterToken] {
        // For Pimlico, query the supported tokens
        // This is chain-specific
        let knownTokens: [Int: [PaymasterToken]] = [
            1: [  // Ethereum Mainnet
                PaymasterToken(
                    address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
                    symbol: "USDC",
                    decimals: 6,
                    exchangeRate: 0.000001,  // Approximate
                    chainId: 1
                ),
                PaymasterToken(
                    address: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
                    symbol: "USDT",
                    decimals: 6,
                    exchangeRate: 0.000001,
                    chainId: 1
                ),
            ],
            11155111: [  // Sepolia
                PaymasterToken(
                    address: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238",
                    symbol: "USDC",
                    decimals: 6,
                    exchangeRate: 0.000001,
                    chainId: 11155111
                ),
            ],
        ]

        return knownTokens[chainId] ?? []
    }

    /// Get paymaster data for paying gas in ERC-20 tokens
    /// - Parameters:
    ///   - userOp: The UserOperation
    ///   - token: The token to pay gas with
    /// - Returns: Paymaster data for ERC-20 payment
    func getERC20PaymasterData(
        userOp: UserOperation,
        token: PaymasterToken
    ) async throws -> PaymasterDataResponse {
        // For Pimlico's ERC-20 paymaster, we need to include the token address
        let params: [Any] = [
            userOp.toRPCDict(),
            ERC4337Constants.entryPoint,
            [
                "token": token.address
            ]
        ]

        let result = try await rpcCall(
            method: "pm_sponsorUserOperation",
            params: params
        )

        guard let dict = result as? [String: Any] else {
            throw PaymasterError.invalidResponse("Expected paymaster data object")
        }

        let jsonData = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(PaymasterDataResponse.self, from: jsonData)
    }

    // MARK: - Validation

    /// Validate that a paymaster stub signature is valid
    func validateStubData(_ paymasterAndData: Data) async throws -> Bool {
        // Check minimum length (20 bytes address + any data)
        guard paymasterAndData.count >= 20 else {
            return false
        }

        // Extract paymaster address
        let paymasterAddress = "0x" + paymasterAndData.prefix(20).hexStringWithoutPrefix

        // Verify it's a valid address format
        return paymasterAddress.count == 42
    }

    // MARK: - Sponsorship Policies

    /// Get available sponsorship policies for the current chain
    func getSponsorshipPolicies() async throws -> [SponsorshipPolicy] {
        // This would typically be fetched from Pimlico's API
        // For now, return a default policy
        return [
            SponsorshipPolicy(
                id: "default",
                name: "Default Sponsorship",
                description: "Standard gas sponsorship",
                chainId: chainId,
                limits: nil,
                allowedContracts: nil,
                isActive: true
            )
        ]
    }

    // MARK: - Private Helpers

    private func rpcCall(method: String, params: [Any]) async throws -> Any {
        guard !apiKey.isEmpty else {
            throw PaymasterError.noAPIKey
        }

        print("[Paymaster] RPC call: \(method)")

        var request = URLRequest(url: paymasterURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let rpcRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": Int.random(in: 1...1000000)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: rpcRequest)

        // Log request
        if let requestBody = String(data: request.httpBody!, encoding: .utf8) {
            print("[Paymaster] Request:\n\(requestBody)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // Log response
        let responseStr = String(data: data, encoding: .utf8) ?? "Unable to decode"
        print("[Paymaster] Response: \(responseStr)")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PaymasterError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PaymasterError.httpError(httpResponse.statusCode, body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PaymasterError.invalidResponse("Invalid JSON response")
        }

        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? -1
            let message = error["message"] as? String ?? "Unknown error"

            // Check for specific error codes
            if code == -32602 || message.lowercased().contains("not sponsored") {
                throw PaymasterError.sponsorshipDenied(message)
            }

            throw PaymasterError.rpcError(code, message)
        }

        guard let result = json["result"] else {
            throw PaymasterError.invalidResponse("Missing result field")
        }

        return result
    }
}

// MARK: - Paymaster Errors

enum PaymasterError: Error, LocalizedError {
    case noAPIKey
    case networkError(String)
    case httpError(Int, String)
    case invalidResponse(String)
    case rpcError(Int, String)
    case sponsorshipDenied(String)
    case insufficientTokenBalance
    case tokenNotAccepted

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
            return "Paymaster error (\(code)): \(message)"
        case .sponsorshipDenied(let reason):
            return "Sponsorship denied: \(reason)"
        case .insufficientTokenBalance:
            return "Insufficient token balance for gas payment"
        case .tokenNotAccepted:
            return "Token not accepted by paymaster"
        }
    }
}

// MARK: - Paymaster Mode

enum PaymasterMode: String, CaseIterable {
    case none = "none"              // Pay gas from smart account
    case sponsored = "sponsored"    // Fully sponsored by Pimlico/dApp
    case erc20 = "erc20"            // Pay gas in ERC-20 tokens

    var displayName: String {
        switch self {
        case .none: return "Self Pay"
        case .sponsored: return "Sponsored"
        case .erc20: return "Pay in Tokens"
        }
    }

    var description: String {
        switch self {
        case .none: return "Pay gas from your account balance"
        case .sponsored: return "Gas fees are sponsored"
        case .erc20: return "Pay gas fees using tokens"
        }
    }
}

// MARK: - Convenience Extensions

extension PaymasterService {
    /// Build a sponsored UserOperation
    func buildSponsoredUserOperation(
        from userOp: UserOperation,
        mode: PaymasterMode,
        token: PaymasterToken? = nil
    ) async throws -> UserOperation {
        switch mode {
        case .none:
            return userOp

        case .sponsored:
            return try await sponsorUserOperation(userOp)

        case .erc20:
            guard let token = token else {
                throw PaymasterError.tokenNotAccepted
            }
            let paymasterData = try await getERC20PaymasterData(userOp: userOp, token: token)
            var sponsoredOp = userOp
            sponsoredOp.paymasterAndData = paymasterData.paymasterAndData
            return sponsoredOp
        }
    }
}
