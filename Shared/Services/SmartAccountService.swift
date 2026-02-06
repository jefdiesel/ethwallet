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
    private let entryPointAddress = ERC4337Constants.entryPointV07

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
        // Call factory.getAddress(owner, salt) to get the counterfactual address
        let calldata = UserOperationEncoder.encodeInitCode(
            factory: factoryAddress,
            owner: owner,
            salt: salt
        )

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
        paymaster: Paymaster? = nil
    ) async throws -> UserOperation {
        return try await buildUserOperation(
            account: account,
            calls: [call],
            paymaster: paymaster
        )
    }

    /// Build a UserOperation for multiple calls (batch)
    func buildUserOperation(
        account: SmartAccount,
        calls: [UserOperationCall],
        paymaster: Paymaster? = nil
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

        // Build initial UserOp for gas estimation
        var userOp = UserOperation(
            sender: account.smartAccountAddress,
            nonce: nonce,
            initCode: initCode,
            callData: callData,
            callGasLimit: ERC4337Constants.minCallGasLimit,
            verificationGasLimit: ERC4337Constants.minVerificationGasLimit,
            preVerificationGas: ERC4337Constants.defaultPreVerificationGas,
            maxFeePerGas: 0,
            maxPriorityFeePerGas: 0,
            paymasterAndData: Data(),
            signature: dummySignature()  // Dummy signature for estimation
        )

        // Get gas prices
        let gasPrices = try await bundlerService.getGasPrices()
        userOp.maxFeePerGas = gasPrices.standard.maxFeePerGas
        userOp.maxPriorityFeePerGas = gasPrices.standard.maxPriorityFeePerGas

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

        // Clear dummy signature
        userOp.signature = Data()

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
        privateKey: Data,
        paymaster: Paymaster? = nil
    ) async throws -> String {
        // Build the UserOperation
        var userOp = try await buildUserOperation(
            account: account,
            calls: calls,
            paymaster: paymaster
        )

        // Sign the UserOperation
        userOp = try signUserOperation(userOp, privateKey: privateKey)

        // Send to bundler
        let userOpHash = try await bundlerService.sendUserOperation(userOp)

        return userOpHash
    }

    /// Sign a UserOperation with the owner's private key
    func signUserOperation(_ userOp: UserOperation, privateKey: Data) throws -> UserOperation {
        // Compute the hash to sign
        let hash = userOp.hash(chainId: chainId, entryPoint: entryPointAddress)

        // Sign with Ethereum personal sign prefix
        let prefix = "\u{19}Ethereum Signed Message:\n32"
        guard let prefixData = prefix.data(using: .utf8) else {
            throw SmartAccountError.signatureFailed
        }

        let dataToSign = (prefixData + hash).sha3(.keccak256)

        // Sign using secp256k1
        let (serializedSignature, _) = SECP256K1.signForRecovery(hash: dataToSign, privateKey: privateKey)

        guard let signature = serializedSignature else {
            throw SmartAccountError.signatureFailed
        }

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
        Data(repeating: 0xff, count: 65)
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
