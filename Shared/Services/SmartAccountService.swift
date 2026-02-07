import Foundation
import BigInt
import CryptoSwift
import web3swift
import Web3Core

/// Service for ERC-4337 smart account operations
final class SmartAccountService {
    private let web3Service: Web3Service
    private let bundlerService: BundlerService
    private var chainId: Int

    // Contract addresses
    private let factoryAddress = ERC4337Constants.simpleAccountFactory
    private let entryPointAddress = ERC4337Constants.entryPoint

    // MARK: - Initialization

    init(web3Service: Web3Service, bundlerService: BundlerService, chainId: Int) {
        self.web3Service = web3Service
        self.bundlerService = bundlerService
        self.chainId = chainId
    }

    /// Update chain ID when network changes
    func switchChain(_ chainId: Int) {
        self.chainId = chainId
        bundlerService.switchChain(chainId)
    }

    // MARK: - Account Management

    /// Compute the counterfactual address for a smart account
    /// This address is deterministic and can be computed before deployment
    func computeAddress(owner: String, salt: BigUInt) async throws -> String {
        // We need to call the factory's getAddress function
        // getAddress(address owner, uint256 salt) selector: 0x8cb84e18
        var getAddressCalldata = Data()
        getAddressCalldata.append(Data(hex: "8cb84e18"))  // getAddress selector
        getAddressCalldata.append(padAddress(owner))
        getAddressCalldata.append(padUInt256(salt))

        let result = try await web3Service.call(
            to: factoryAddress,
            data: "0x" + getAddressCalldata.hexStringWithoutPrefix
        )

        guard let address = UserOperationEncoder.decodeUInt256(result) else {
            throw SmartAccountError.addressComputationFailed
        }

        // Convert BigUInt to address (last 20 bytes)
        var addressHex = String(address, radix: 16)
        // Pad to 40 hex characters (20 bytes)
        while addressHex.count < 40 {
            addressHex = "0" + addressHex
        }
        return "0x" + addressHex.suffix(40)
    }

    /// Check if a smart account is deployed at the given address
    func isDeployed(address: String) async throws -> Bool {
        // Check if there's code at the address
        let code = try await getCode(at: address)
        return !code.isEmpty && code != "0x"
    }

    /// Get the init code for deploying a smart account
    func getInitCode(owner: String, salt: BigUInt) -> Data {
        UserOperationEncoder.encodeInitCode(
            factory: factoryAddress,
            owner: owner,
            salt: salt
        )
    }

    /// Create a new smart account (counterfactual - not deployed yet)
    func createSmartAccount(owner: String, salt: BigUInt = 0) async throws -> SmartAccount {
        let smartAccountAddress = try await computeAddress(owner: owner, salt: salt)
        let deployed = try await isDeployed(address: smartAccountAddress)

        return SmartAccount(
            ownerAddress: owner,
            smartAccountAddress: smartAccountAddress,
            salt: salt,
            isDeployed: deployed,
            chainId: chainId
        )
    }

    // MARK: - Nonce Management

    /// Get the current nonce for a smart account from the EntryPoint
    func getNonce(account: String, key: BigUInt = 0) async throws -> BigUInt {
        let calldata = UserOperationEncoder.encodeGetNonce(sender: account, key: key)

        let result = try await web3Service.call(
            to: entryPointAddress,
            data: "0x" + calldata.hexStringWithoutPrefix
        )

        guard let nonce = UserOperationEncoder.decodeUInt256(result) else {
            throw SmartAccountError.nonceRetrievalFailed
        }

        return nonce
    }

    // MARK: - UserOperation Building

    /// Build a UserOperation for a single call
    func buildUserOperation(
        account: SmartAccount,
        call: UserOperationCall,
        skipEstimation: Bool = false
    ) async throws -> UserOperation {
        return try await buildUserOperation(
            account: account,
            calls: [call],
            skipEstimation: skipEstimation
        )
    }

    /// Build a UserOperation for multiple calls (batch)
    /// - Parameters:
    ///   - account: The smart account
    ///   - calls: The calls to execute
    ///   - skipEstimation: If true, skips gas estimation (use when paymaster will provide gas values)
    func buildUserOperation(
        account: SmartAccount,
        calls: [UserOperationCall],
        skipEstimation: Bool = false
    ) async throws -> UserOperation {
        // Get nonce
        let nonce = try await getNonce(account: account.smartAccountAddress)

        // Build calldata
        let callData: Data
        if calls.count == 1 {
            let call = calls[0]
            callData = UserOperationEncoder.encodeExecute(
                to: call.to,
                value: call.value,
                data: call.data
            )
        } else {
            callData = UserOperationEncoder.encodeExecuteBatch(calls: calls)
        }

        // Get init code if not deployed
        let initCode: Data
        if !account.isDeployed {
            initCode = getInitCode(owner: account.ownerAddress, salt: account.salt)
        } else {
            initCode = Data()
        }

        // Get gas prices
        let gasPrices = try await bundlerService.getGasPrices()

        // Build initial UserOp
        var userOp = UserOperation(
            sender: account.smartAccountAddress,
            nonce: nonce,
            initCode: initCode,
            callData: callData,
            callGasLimit: ERC4337Constants.minCallGasLimit,
            verificationGasLimit: ERC4337Constants.minVerificationGasLimit,
            preVerificationGas: ERC4337Constants.defaultPreVerificationGas,
            maxFeePerGas: gasPrices.standard.maxFeePerGas,
            maxPriorityFeePerGas: gasPrices.standard.maxPriorityFeePerGas,
            paymasterAndData: Data(),
            signature: dummySignature()  // Dummy signature for estimation
        )

        // Skip estimation if paymaster will provide gas values
        if !skipEstimation {
            // Estimate gas
            let gasEstimate = try await bundlerService.estimateUserOperationGas(userOp)
            userOp.callGasLimit = gasEstimate.callGasLimit
            userOp.verificationGasLimit = gasEstimate.verificationGasLimit
            userOp.preVerificationGas = gasEstimate.preVerificationGas

            // Update gas prices if returned
            if gasEstimate.maxFeePerGas > 0 {
                userOp.maxFeePerGas = gasEstimate.maxFeePerGas
            }
            if gasEstimate.maxPriorityFeePerGas > 0 {
                userOp.maxPriorityFeePerGas = gasEstimate.maxPriorityFeePerGas
            }
        }

        // Clear dummy signature only if we did estimation
        // Keep dummy signature if skipEstimation=true (paymaster will simulate with it)
        if !skipEstimation {
            userOp.signature = Data()
        }

        return userOp
    }

    // MARK: - Execution

    /// Execute a single call via smart account
    func execute(
        account: SmartAccount,
        to: String,
        value: BigUInt,
        data: Data,
        privateKey: Data
    ) async throws -> String {
        let call = UserOperationCall(to: to, value: value, data: data)
        return try await execute(account: account, calls: [call], privateKey: privateKey)
    }

    /// Execute a batch of calls via smart account
    func execute(
        account: SmartAccount,
        calls: [UserOperationCall],
        privateKey: Data
    ) async throws -> String {
        print("[SmartAccount] === EXECUTE START ===")
        print("[SmartAccount] account: \(account.smartAccountAddress)")
        print("[SmartAccount] owner: \(account.ownerAddress)")
        print("[SmartAccount] isDeployed: \(account.isDeployed)")
        print("[SmartAccount] calls count: \(calls.count)")

        // Build the UserOperation (with estimation since no paymaster in this flow)
        print("[SmartAccount] Building UserOperation...")
        var userOp = try await buildUserOperation(
            account: account,
            calls: calls,
            skipEstimation: false
        )
        print("[SmartAccount] UserOperation built successfully")

        // Sign the UserOperation
        print("[SmartAccount] Signing UserOperation...")
        userOp = try signUserOperation(userOp, privateKey: privateKey)
        print("[SmartAccount] UserOperation signed successfully")

        // Send to bundler
        print("[SmartAccount] Sending to bundler...")
        let userOpHash = try await bundlerService.sendUserOperation(userOp)
        print("[SmartAccount] Sent! Hash: \(userOpHash)")

        return userOpHash
    }

    /// Sign a UserOperation with the owner's private key
    func signUserOperation(_ userOp: UserOperation, privateKey: Data) throws -> UserOperation {
        // Debug: print key info
        print("[SmartAccount] === SIGNING DEBUG ===")

        // Derive address from private key to verify it matches expected owner
        if let publicKey = SECP256K1.privateToPublic(privateKey: privateKey, compressed: false) {
            // Skip first byte (0x04 prefix) and take keccak256 of remaining 64 bytes
            let publicKeyData = publicKey.dropFirst()
            let addressHash = publicKeyData.sha3(.keccak256)
            let signerAddress = "0x" + addressHash.suffix(20).map { String(format: "%02x", $0) }.joined()
            print("[SmartAccount] signer address (from privateKey): \(signerAddress)")
        }

        print("[SmartAccount] chainId: \(chainId)")
        print("[SmartAccount] entryPoint: \(entryPointAddress)")
        print("[SmartAccount] sender: \(userOp.sender)")
        print("[SmartAccount] nonce: \(userOp.nonce)")
        print("[SmartAccount] initCode length: \(userOp.initCode.count)")
        print("[SmartAccount] callData length: \(userOp.callData.count)")
        print("[SmartAccount] callGasLimit: \(userOp.callGasLimit)")
        print("[SmartAccount] verificationGasLimit: \(userOp.verificationGasLimit)")
        print("[SmartAccount] preVerificationGas: \(userOp.preVerificationGas)")
        print("[SmartAccount] maxFeePerGas: \(userOp.maxFeePerGas)")
        print("[SmartAccount] maxPriorityFeePerGas: \(userOp.maxPriorityFeePerGas)")
        print("[SmartAccount] paymasterAndData length: \(userOp.paymasterAndData.count)")

        // Compute the UserOperation hash (this is what EntryPoint.getUserOpHash returns)
        let userOpHash = userOp.hash(chainId: chainId, entryPoint: entryPointAddress)

        // SimpleAccount v0.7 uses EIP-191 personal sign: toEthSignedMessageHash(userOpHash)
        let prefix = "\u{19}Ethereum Signed Message:\n32"
        guard let prefixData = prefix.data(using: .utf8) else {
            throw SmartAccountError.signatureFailed
        }
        let messageHash = (prefixData + userOpHash).sha3(.keccak256)

        // Debug: print hashes for troubleshooting
        print("[SmartAccount] userOpHash: 0x\(userOpHash.map { String(format: "%02x", $0) }.joined())")
        print("[SmartAccount] messageHash (personal sign): 0x\(messageHash.map { String(format: "%02x", $0) }.joined())")

        let (serializedSignature, _) = SECP256K1.signForRecovery(hash: messageHash, privateKey: privateKey)

        guard let signature = serializedSignature else {
            throw SmartAccountError.signatureFailed
        }

        // Print signature components
        print("[SmartAccount] signature (65 bytes): 0x\(signature.map { String(format: "%02x", $0) }.joined())")
        print("[SmartAccount] signature v: \(signature[64])")
        print("[SmartAccount] === END DEBUG ===")

        var signedOp = userOp
        signedOp.signature = signature
        return signedOp
    }

    // MARK: - Transaction Helpers

    /// Send ETH via smart account
    func sendETH(
        from account: SmartAccount,
        to: String,
        amount: BigUInt,
        privateKey: Data
    ) async throws -> String {
        let call = UserOperationCall.transfer(to: to, value: amount)
        return try await execute(account: account, calls: [call], privateKey: privateKey)
    }

    /// Send ERC-20 token via smart account
    func sendToken(
        from account: SmartAccount,
        token: String,
        to: String,
        amount: BigUInt,
        privateKey: Data
    ) async throws -> String {
        // Encode ERC-20 transfer calldata
        let transferData = encodeERC20Transfer(to: to, amount: amount)
        let call = UserOperationCall.contractCall(to: token, data: transferData)
        return try await execute(account: account, calls: [call], privateKey: privateKey)
    }

    // MARK: - Status Checking

    /// Wait for UserOperation receipt
    func waitForReceipt(_ userOpHash: String, timeout: TimeInterval = 120) async throws -> UserOperationReceipt {
        try await bundlerService.waitForReceipt(userOpHash, timeout: timeout)
    }

    /// Get UserOperation status
    func getStatus(_ userOpHash: String) async throws -> PimlicoUserOpStatus {
        try await bundlerService.getUserOperationStatus(userOpHash)
    }

    // MARK: - Private Helpers

    private func getCode(at address: String) async throws -> String {
        do {
            let result = try await web3Service.rawRPCCall(
                method: "eth_getCode",
                params: [address, "latest"]
            )
            return result as? String ?? "0x"
        } catch {
            return "0x"
        }
    }

    private func padAddress(_ address: String) -> Data {
        var hex = address.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        let padded = String(repeating: "0", count: 64 - hex.count) + hex
        return Data(hex: padded)
    }

    private func padUInt256(_ value: BigUInt) -> Data {
        let hex = String(value, radix: 16)
        let padded = String(repeating: "0", count: 64 - hex.count) + hex
        return Data(hex: padded)
    }

    private func dummySignature() -> Data {
        // 65-byte dummy signature for gas estimation
        // Must be valid ECDSA format or OpenZeppelin's ECDSA.recover will revert
        // r = 1 (32 bytes), s = 1 (32 bytes), v = 27 (1 byte)
        var sig = Data(repeating: 0x00, count: 65)
        sig[31] = 0x01  // r = 1 (last byte of first 32)
        sig[63] = 0x01  // s = 1 (last byte of second 32)
        sig[64] = 0x1b  // v = 27
        return sig
    }

    private func encodeERC20Transfer(to: String, amount: BigUInt) -> Data {
        // transfer(address,uint256) selector: 0xa9059cbb
        var data = Data()
        data.append(Data(hex: "a9059cbb"))
        data.append(padAddress(to))
        data.append(padUInt256(amount))
        return data
    }
}

// MARK: - Smart Account Errors

enum SmartAccountError: Error, LocalizedError {
    case addressComputationFailed
    case nonceRetrievalFailed
    case signatureFailed
    case userOperationFailed(String)
    case accountNotDeployed
    case insufficientBalance
    case invalidCalldata

    var errorDescription: String? {
        switch self {
        case .addressComputationFailed:
            return "Failed to compute smart account address"
        case .nonceRetrievalFailed:
            return "Failed to retrieve account nonce"
        case .signatureFailed:
            return "Failed to sign UserOperation"
        case .userOperationFailed(let reason):
            return "UserOperation failed: \(reason)"
        case .accountNotDeployed:
            return "Smart account is not deployed"
        case .insufficientBalance:
            return "Insufficient balance for operation"
        case .invalidCalldata:
            return "Invalid calldata encoding"
        }
    }
}

// MARK: - Gas Estimation Helpers

extension SmartAccountService {
    /// Estimate the cost of a UserOperation in ETH
    func estimateCost(
        account: SmartAccount,
        calls: [UserOperationCall]
    ) async throws -> BigUInt {
        let userOp = try await buildUserOperation(account: account, calls: calls)
        return userOp.maxCost
    }

    /// Format gas cost for display
    func formatCost(_ wei: BigUInt) -> String {
        let divisor: BigUInt = 1_000_000_000_000_000_000  // 10^18
        let eth = Double(wei) / Double(divisor)
        return String(format: "%.6f ETH", eth)
    }
}
