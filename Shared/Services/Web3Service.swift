import Foundation
import web3swift
import Web3Core
import BigInt

/// Service for interacting with Ethereum and EVM-compatible chains
final class Web3Service {
    private var web3: Web3?
    private var currentNetwork: Network

    init(network: Network = .ethereum) {
        self.currentNetwork = network
        setupWeb3(for: network)
    }

    // MARK: - Network Management

    /// Switch to a different network
    func switchNetwork(_ network: Network) {
        self.currentNetwork = network
        setupWeb3(for: network)
    }

    private func setupWeb3(for network: Network) {
        guard let provider = try? Web3HttpProvider(url: network.rpcURL, network: .Custom(networkID: BigUInt(network.id))) else {
            print("Failed to create provider for \(network.name)")
            return
        }
        self.web3 = Web3(provider: provider)
    }

    // MARK: - Wallet Operations

    /// Generate a new BIP39 mnemonic
    func generateMnemonic(wordCount: MnemonicWordCount = .twelve) throws -> String {
        let entropy: Int
        switch wordCount {
        case .twelve:
            entropy = 128
        case .twentyFour:
            entropy = 256
        }

        guard let mnemonic = try? BIP39.generateMnemonics(bitsOfEntropy: entropy) else {
            throw Web3ServiceError.mnemonicGenerationFailed
        }
        return mnemonic
    }

    /// Derive wallet from mnemonic
    func deriveWallet(from mnemonic: String, password: String = "") throws -> (seed: Data, accounts: [Account]) {
        guard let seed = BIP39.seedFromMmemonics(mnemonic, password: password) else {
            throw Web3ServiceError.invalidMnemonic
        }

        // Derive first account
        let account = try deriveAccount(from: seed, at: 0)

        return (seed: seed, accounts: [account])
    }

    /// Derive an account at a specific index from seed
    func deriveAccount(from seed: Data, at index: Int) throws -> Account {
        let path = "m/44'/60'/0'/0/\(index)"

        guard let keystore = try? BIP32Keystore(seed: seed, password: "", prefixPath: "m/44'/60'/0'/0") else {
            throw Web3ServiceError.keyDerivationFailed
        }

        guard let address = keystore.addresses?.first else {
            throw Web3ServiceError.addressDerivationFailed
        }

        return Account(
            index: index,
            address: address.address,
            label: "Account \(index + 1)"
        )
    }

    /// Import wallet from private key
    func importFromPrivateKey(_ privateKeyHex: String) throws -> Account {
        var hex = privateKeyHex
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard let privateKeyData = Data.fromHex(hex) else {
            throw Web3ServiceError.invalidPrivateKey
        }

        guard let keystore = try? EthereumKeystoreV3(privateKey: privateKeyData, password: "") else {
            throw Web3ServiceError.keystoreCreationFailed
        }

        guard let address = keystore.addresses?.first else {
            throw Web3ServiceError.addressDerivationFailed
        }

        return Account(
            index: 0,
            address: address.address,
            label: "Imported Account"
        )
    }

    // MARK: - Balance Operations

    /// Get ETH balance for an address
    func getBalance(for address: String) async throws -> BigUInt {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        guard let ethAddress = EthereumAddress(address) else {
            throw Web3ServiceError.invalidAddress
        }

        let balance = try await web3.eth.getBalance(for: ethAddress)
        return balance
    }

    /// Get ETH balance formatted as string
    func getFormattedBalance(for address: String) async throws -> String {
        let balance = try await getBalance(for: address)
        return formatWei(balance)
    }

    // MARK: - Transaction Operations

    /// Get current gas price
    func getGasPrice() async throws -> BigUInt {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        return try await web3.eth.gasPrice()
    }

    /// Estimate gas for a transaction
    func estimateGas(for request: TransactionRequest) async throws -> BigUInt {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        guard let toAddress = EthereumAddress(request.to) else {
            throw Web3ServiceError.invalidAddress
        }

        var transaction = CodableTransaction(to: toAddress)
        transaction.value = BigUInt(request.value)
        if let data = request.data {
            transaction.data = data
        }

        return try await web3.eth.estimateGas(for: transaction)
    }

    /// Get the current nonce for an address
    func getNonce(for address: String) async throws -> BigUInt {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        guard let ethAddress = EthereumAddress(address) else {
            throw Web3ServiceError.invalidAddress
        }

        return try await web3.eth.getTransactionCount(for: ethAddress)
    }

    /// Build a transaction
    func buildTransaction(
        from: String,
        to: String,
        value: BigUInt,
        data: Data? = nil
    ) async throws -> CodableTransaction {
        guard let toAddress = EthereumAddress(to) else {
            throw Web3ServiceError.invalidAddress
        }

        var transaction = CodableTransaction(to: toAddress)
        transaction.value = value
        transaction.chainID = BigUInt(currentNetwork.id)

        if let data = data {
            transaction.data = data
        }

        // Get nonce
        let nonce = try await getNonce(for: from)
        transaction.nonce = nonce

        // Get gas price
        let gasPrice = try await getGasPrice()
        transaction.gasPrice = gasPrice

        // Estimate gas
        let gasEstimate = try await estimateGas(for: TransactionRequest(
            from: from,
            to: to,
            value: value,
            data: data,
            chainId: currentNetwork.id
        ))
        transaction.gasLimit = gasEstimate

        return transaction
    }

    /// Sign and send a transaction
    func sendTransaction(
        _ transaction: CodableTransaction,
        privateKey: Data
    ) async throws -> String {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        var tx = transaction

        print("[Web3] Transaction before signing:")
        print("[Web3]   to: \(tx.to.address)")
        print("[Web3]   value: \(tx.value)")
        print("[Web3]   nonce: \(tx.nonce)")
        print("[Web3]   gasLimit: \(tx.gasLimit)")
        print("[Web3]   chainID: \(tx.chainID ?? 0)")
        print("[Web3]   maxFeePerGas: \(tx.maxFeePerGas ?? 0)")
        print("[Web3]   maxPriorityFeePerGas: \(tx.maxPriorityFeePerGas ?? 0)")
        print("[Web3]   gasPrice: \(tx.gasPrice ?? 0)")

        // Sign the transaction
        try tx.sign(privateKey: privateKey)

        guard let encoded = tx.encode() else {
            print("[Web3] Failed to encode transaction")
            throw Web3ServiceError.transactionFailed("Failed to encode transaction")
        }
        print("[Web3] Encoded tx length: \(encoded.count) bytes")
        print("[Web3] Encoded tx: 0x\(encoded.toHexString().prefix(100))...")

        // Send the transaction
        print("[Web3] Sending raw transaction to RPC...")
        let result = try await web3.eth.send(raw: encoded)
        print("[Web3] RPC returned hash: \(result.hash)")

        return result.hash
    }

    /// Send ETH to an address
    func sendETH(
        from: String,
        to: String,
        amount: BigUInt,
        privateKey: Data
    ) async throws -> String {
        let transaction = try await buildTransaction(from: from, to: to, value: amount)
        return try await sendTransaction(transaction, privateKey: privateKey)
    }

    // MARK: - Transaction Status

    /// Get transaction receipt
    func getTransactionReceipt(hash: String) async throws -> TransactionReceipt? {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        guard let hashData = Data.fromHex(hash) else {
            throw Web3ServiceError.invalidTransactionHash
        }

        return try await web3.eth.transactionReceipt(hashData)
    }

    /// Wait for transaction confirmation
    func waitForConfirmation(hash: String, timeout: TimeInterval = 120) async throws -> TransactionReceipt {
        let startTime = Date()

        while Date().timeIntervalSince(startTime) < timeout {
            if let receipt = try await getTransactionReceipt(hash: hash) {
                return receipt
            }
            try await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
        }

        throw Web3ServiceError.transactionTimeout
    }

    // MARK: - Contract Calls

    /// Make a read-only contract call (eth_call)
    func call(
        to: String,
        data: String
    ) async throws -> String {
        guard let web3 = web3 else {
            throw Web3ServiceError.notInitialized
        }

        guard let toAddress = EthereumAddress(to),
              let callData = Data.fromHex(data) else {
            throw Web3ServiceError.invalidAddress
        }

        var transaction = CodableTransaction(to: toAddress)
        transaction.data = callData

        let result = try await web3.eth.callTransaction(transaction)
        return result.toHexString().addHexPrefix()
    }

    // MARK: - Utility

    /// Convert Wei to Ether string representation
    func formatWei(_ wei: BigUInt, decimals: Int = 6) -> String {
        let divisor = BigUInt(10).power(18)
        let wholePart = wei / divisor
        let fractionalPart = wei % divisor

        let fractionalString = String(fractionalPart)
        let paddedFractional = String(repeating: "0", count: 18 - fractionalString.count) + fractionalString
        let trimmedFractional = String(paddedFractional.prefix(decimals))
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)

        if trimmedFractional.isEmpty {
            return "\(wholePart)"
        }
        return "\(wholePart).\(trimmedFractional)"
    }

    /// Parse Ether string to Wei
    func parseEther(_ ether: String) throws -> BigUInt {
        let components = ether.split(separator: ".")

        guard components.count <= 2 else {
            throw Web3ServiceError.invalidAmount
        }

        let wholePart = BigUInt(String(components[0])) ?? 0

        let fractionalPart: BigUInt
        if components.count == 2 {
            var fractionalString = String(components[1])
            if fractionalString.count > 18 {
                fractionalString = String(fractionalString.prefix(18))
            } else {
                fractionalString += String(repeating: "0", count: 18 - fractionalString.count)
            }
            fractionalPart = BigUInt(fractionalString) ?? 0
        } else {
            fractionalPart = 0
        }

        let multiplier = BigUInt(10).power(18)
        return wholePart * multiplier + fractionalPart
    }

    // MARK: - Current State

    var network: Network {
        currentNetwork
    }

    // MARK: - Message Signing (for WalletConnect)

    /// Sign a personal message (EIP-191)
    func signPersonalMessage(message: String, privateKey: Data) async throws -> String {
        // Remove 0x prefix if present and convert hex to data
        let messageData: Data
        if message.hasPrefix("0x") {
            let hex = String(message.dropFirst(2))
            guard let data = Data(fromHexString: hex) else {
                throw Web3ServiceError.invalidAmount
            }
            messageData = data
        } else {
            guard let data = message.data(using: .utf8) else {
                throw Web3ServiceError.invalidAmount
            }
            messageData = data
        }

        // Create the personal sign prefix
        let prefix = "\u{19}Ethereum Signed Message:\n\(messageData.count)"
        guard let prefixData = prefix.data(using: .utf8) else {
            throw Web3ServiceError.invalidAmount
        }

        // Hash prefix + message
        let dataToSign = prefixData + messageData
        let hash = dataToSign.sha3(.keccak256)

        // Sign the hash
        let signature = try signHash(hash, privateKey: privateKey)
        return signature
    }

    /// Sign a raw message hash
    func signMessage(message: String, privateKey: Data) async throws -> String {
        // Remove 0x prefix if present
        let hex = message.hasPrefix("0x") ? String(message.dropFirst(2)) : message
        guard let messageData = Data(fromHexString: hex) else {
            throw Web3ServiceError.invalidAmount
        }

        // If it's already 32 bytes, treat it as a hash
        let hash: Data
        if messageData.count == 32 {
            hash = messageData
        } else {
            hash = messageData.sha3(.keccak256)
        }

        let signature = try signHash(hash, privateKey: privateKey)
        return signature
    }

    /// Sign a hash with private key
    private func signHash(_ hash: Data, privateKey: Data) throws -> String {
        let (serializedSignature, _) = SECP256K1.signForRecovery(hash: hash, privateKey: privateKey)

        guard let sigData = serializedSignature else {
            throw Web3ServiceError.transactionFailed("Failed to sign")
        }

        // The serializedSignature is already 65 bytes: r (32) + s (32) + v (1)
        return "0x" + sigData.toHexString()
    }

    /// Send a transaction from a dictionary (for WalletConnect)
    func sendTransactionFromDict(
        _ txDict: [String: Any],
        from: String,
        privateKey: Data
    ) async throws -> String {
        print("[Web3] sendTransactionFromDict starting...")
        print("[Web3] txDict keys: \(txDict.keys.sorted())")
        guard let to = txDict["to"] as? String,
              let toAddress = EthereumAddress(to) else {
            throw Web3ServiceError.invalidAddress
        }

        // Parse value (default 0)
        var value = BigUInt(0)
        if let valueHex = txDict["value"] as? String {
            value = parseBigUInt(valueHex)
        }

        // Parse data
        var txData = Data()
        if let dataHex = txDict["data"] as? String, dataHex != "0x" {
            txData = Data.fromHex(dataHex) ?? Data()
        }

        // Parse nonce
        var nonce = BigUInt(0)
        if let nonceHex = txDict["nonce"] as? String {
            nonce = parseBigUInt(nonceHex)
            print("[Web3] Using dApp nonce: \(nonce)")
        } else {
            nonce = try await getNonce(for: from)
            print("[Web3] Fetched nonce: \(nonce)")
        }

        // Parse gas limit (add 30% buffer to estimates for safety)
        var gasLimit = BigUInt(0)
        if let gasHex = txDict["gas"] as? String {
            gasLimit = parseBigUInt(gasHex)
            print("[Web3] Using dApp gas limit: \(gasLimit)")
        } else {
            do {
                let estimated = try await estimateGas(for: TransactionRequest(
                    from: from, to: to, value: value, data: txData, chainId: currentNetwork.id
                ))
                gasLimit = estimated * 130 / 100
                print("[Web3] Estimated gas: \(estimated), with 30%% buffer: \(gasLimit)")
            } catch {
                print("[Web3] Gas estimation failed: \(error), using fallback 200000")
                gasLimit = BigUInt(200000)
            }
        }

        // Build transaction - default to EIP-1559 on post-London chains
        let txType = txDict["type"] as? String
        let dAppWantsLegacy = txType == "0x0" || txDict["gasPrice"] != nil
        let transaction: CodableTransaction

        if dAppWantsLegacy {
            // Legacy transaction (only if dApp explicitly requests it)
            print("[Web3] Building legacy transaction (dApp requested)")
            var gasPrice = BigUInt(0)
            if let gasPriceHex = txDict["gasPrice"] as? String {
                gasPrice = parseBigUInt(gasPriceHex)
            } else {
                gasPrice = try await getGasPrice()
            }
            print("[Web3] gasPrice: \(gasPrice)")

            transaction = CodableTransaction(
                type: .legacy,
                to: toAddress,
                nonce: nonce,
                chainID: BigUInt(currentNetwork.id),
                value: value,
                data: txData,
                gasLimit: gasLimit,
                gasPrice: gasPrice
            )
        } else {
            // EIP-1559 transaction (default)
            print("[Web3] Building EIP-1559 transaction")
            var maxFeePerGas: BigUInt
            var maxPriorityFeePerGas: BigUInt

            if let mfpg = txDict["maxFeePerGas"] as? String {
                maxFeePerGas = parseBigUInt(mfpg)
                maxPriorityFeePerGas = parseBigUInt(txDict["maxPriorityFeePerGas"] as? String ?? "0")
            } else {
                // Fetch current base fee and compute reasonable fees
                let baseFee = try await getGasPrice()
                maxPriorityFeePerGas = BigUInt(1_500_000_000) // 1.5 Gwei tip
                maxFeePerGas = baseFee * 2 + maxPriorityFeePerGas
            }
            print("[Web3] maxFeePerGas: \(maxFeePerGas), maxPriorityFee: \(maxPriorityFeePerGas)")

            transaction = CodableTransaction(
                type: .eip1559,
                to: toAddress,
                nonce: nonce,
                chainID: BigUInt(currentNetwork.id),
                value: value,
                data: txData,
                gasLimit: gasLimit,
                maxFeePerGas: maxFeePerGas,
                maxPriorityFeePerGas: maxPriorityFeePerGas
            )
        }

        print("[Web3] Calling sendTransaction...")
        return try await sendTransaction(transaction, privateKey: privateKey)
    }

    /// Parse hex string to BigUInt
    private func parseBigUInt(_ hex: String) -> BigUInt {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        return BigUInt(cleanHex, radix: 16) ?? 0
    }

    // MARK: - Raw RPC Calls

    /// Forward raw RPC call to the node (for browser dApp support)
    func rawRPCCall(method: String, params: [Any]) async throws -> Any {
        guard let url = URL(string: currentNetwork.rpcURL.absoluteString) else {
            throw Web3ServiceError.notInitialized
        }

        // Build JSON-RPC request
        var request = URLRequest(url: url)
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

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw Web3ServiceError.rpcError("HTTP error")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Web3ServiceError.rpcError("Invalid JSON response")
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw Web3ServiceError.rpcError(message)
        }

        // result can be null (NSNull) for some RPC methods - that's valid
        let result = json["result"]
        if result == nil || result is NSNull {
            return NSNull()
        }

        return result!
    }
}

// MARK: - Errors

enum Web3ServiceError: Error, LocalizedError {
    case notInitialized
    case invalidAddress
    case invalidPrivateKey
    case invalidMnemonic
    case invalidAmount
    case invalidTransactionHash
    case mnemonicGenerationFailed
    case keyDerivationFailed
    case addressDerivationFailed
    case keystoreCreationFailed
    case transactionFailed(String)
    case transactionTimeout
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Web3 service not initialized"
        case .invalidAddress:
            return "Invalid Ethereum address"
        case .invalidPrivateKey:
            return "Invalid private key"
        case .invalidMnemonic:
            return "Invalid mnemonic phrase"
        case .invalidAmount:
            return "Invalid amount format"
        case .invalidTransactionHash:
            return "Invalid transaction hash"
        case .mnemonicGenerationFailed:
            return "Failed to generate mnemonic"
        case .keyDerivationFailed:
            return "Failed to derive key"
        case .addressDerivationFailed:
            return "Failed to derive address"
        case .keystoreCreationFailed:
            return "Failed to create keystore"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        case .transactionTimeout:
            return "Transaction confirmation timed out"
        case .rpcError(let message):
            return "RPC error: \(message)"
        }
    }
}

// MARK: - Data Extension

extension Data {
    func toHexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(fromHexString hex: String) {
        let cleanHex = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleanHex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = cleanHex.startIndex

        while index < cleanHex.endIndex {
            let nextIndex = cleanHex.index(index, offsetBy: 2)
            guard let byte = UInt8(cleanHex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

extension String {
    func addHexPrefix() -> String {
        if hasPrefix("0x") {
            return self
        }
        return "0x" + self
    }
}
