import Foundation
import BigInt
import CryptoSwift

/// ERC-4337 UserOperation structure for account abstraction
/// https://eips.ethereum.org/EIPS/eip-4337
struct UserOperation: Codable {
    let sender: String                    // Smart account address
    var nonce: BigUInt                    // Anti-replay nonce from EntryPoint
    var initCode: Data                    // Factory + initData, empty if already deployed
    var callData: Data                    // Encoded execute/executeBatch call
    var callGasLimit: BigUInt             // Gas for the main call
    var verificationGasLimit: BigUInt     // Gas for signature verification
    var preVerificationGas: BigUInt       // Gas for bundler overhead
    var maxFeePerGas: BigUInt             // EIP-1559 max fee
    var maxPriorityFeePerGas: BigUInt     // EIP-1559 priority fee
    var paymasterAndData: Data            // Paymaster address + data, empty if self-paying
    var signature: Data                   // ECDSA signature

    // MARK: - Initialization

    init(
        sender: String,
        nonce: BigUInt = 0,
        initCode: Data = Data(),
        callData: Data = Data(),
        callGasLimit: BigUInt = 0,
        verificationGasLimit: BigUInt = 0,
        preVerificationGas: BigUInt = 0,
        maxFeePerGas: BigUInt = 0,
        maxPriorityFeePerGas: BigUInt = 0,
        paymasterAndData: Data = Data(),
        signature: Data = Data()
    ) {
        self.sender = sender
        self.nonce = nonce
        self.initCode = initCode
        self.callData = callData
        self.callGasLimit = callGasLimit
        self.verificationGasLimit = verificationGasLimit
        self.preVerificationGas = preVerificationGas
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.paymasterAndData = paymasterAndData
        self.signature = signature
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case sender, nonce, initCode, callData, callGasLimit
        case verificationGasLimit, preVerificationGas
        case maxFeePerGas, maxPriorityFeePerGas
        case paymasterAndData, signature
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sender = try container.decode(String.self, forKey: .sender)

        // Decode hex strings to BigUInt/Data
        let nonceHex = try container.decode(String.self, forKey: .nonce)
        nonce = BigUInt(hexString: nonceHex) ?? 0

        let initCodeHex = try container.decode(String.self, forKey: .initCode)
        initCode = Data(hex: initCodeHex)

        let callDataHex = try container.decode(String.self, forKey: .callData)
        callData = Data(hex: callDataHex)

        let callGasLimitHex = try container.decode(String.self, forKey: .callGasLimit)
        callGasLimit = BigUInt(hexString: callGasLimitHex) ?? 0

        let verificationGasLimitHex = try container.decode(String.self, forKey: .verificationGasLimit)
        verificationGasLimit = BigUInt(hexString: verificationGasLimitHex) ?? 0

        let preVerificationGasHex = try container.decode(String.self, forKey: .preVerificationGas)
        preVerificationGas = BigUInt(hexString: preVerificationGasHex) ?? 0

        let maxFeePerGasHex = try container.decode(String.self, forKey: .maxFeePerGas)
        maxFeePerGas = BigUInt(hexString: maxFeePerGasHex) ?? 0

        let maxPriorityFeePerGasHex = try container.decode(String.self, forKey: .maxPriorityFeePerGas)
        maxPriorityFeePerGas = BigUInt(hexString: maxPriorityFeePerGasHex) ?? 0

        let paymasterAndDataHex = try container.decode(String.self, forKey: .paymasterAndData)
        paymasterAndData = Data(hex: paymasterAndDataHex)

        let signatureHex = try container.decode(String.self, forKey: .signature)
        signature = Data(hex: signatureHex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sender, forKey: .sender)
        try container.encode(nonce.hexString, forKey: .nonce)
        try container.encode(initCode.hexString, forKey: .initCode)
        try container.encode(callData.hexString, forKey: .callData)
        try container.encode(callGasLimit.hexString, forKey: .callGasLimit)
        try container.encode(verificationGasLimit.hexString, forKey: .verificationGasLimit)
        try container.encode(preVerificationGas.hexString, forKey: .preVerificationGas)
        try container.encode(maxFeePerGas.hexString, forKey: .maxFeePerGas)
        try container.encode(maxPriorityFeePerGas.hexString, forKey: .maxPriorityFeePerGas)
        try container.encode(paymasterAndData.hexString, forKey: .paymasterAndData)
        try container.encode(signature.hexString, forKey: .signature)
    }

    // MARK: - Hash for Signing

    /// Compute the UserOperation hash for signing (ERC-4337 v0.7 format)
    /// This is the hash that gets signed by the owner's private key
    func hash(chainId: Int, entryPoint: String) -> Data {
        // Pack the UserOperation fields (v0.7 format)
        let packed = packForHash()

        // Keccak256 of packed UserOp
        let userOpHash = packed.sha3(.keccak256)

        // Final hash = keccak256(userOpHash || entryPoint || chainId)
        var entryPointAddress = entryPoint.lowercased()
        if entryPointAddress.hasPrefix("0x") {
            entryPointAddress = String(entryPointAddress.dropFirst(2))
        }

        let entryPointPadded = String(repeating: "0", count: 64 - entryPointAddress.count) + entryPointAddress
        let chainIdHex = String(chainId, radix: 16)
        let chainIdPadded = String(repeating: "0", count: 64 - chainIdHex.count) + chainIdHex

        let finalData = userOpHash + Data(hex: entryPointPadded) + Data(hex: chainIdPadded)
        return finalData.sha3(.keccak256)
    }

    /// Pack UserOperation fields for hashing (ERC-4337 v0.7 format)
    private func packForHash() -> Data {
        var data = Data()

        // sender (address, 20 bytes padded to 32)
        data.append(padAddress(sender))

        // nonce (uint256)
        data.append(padUInt256(nonce))

        // hashInitCode = keccak256(initCode)
        data.append(initCode.sha3(.keccak256))

        // hashCallData = keccak256(callData)
        data.append(callData.sha3(.keccak256))

        // accountGasLimits (bytes32) = verificationGasLimit (high 128 bits) || callGasLimit (low 128 bits)
        data.append(packUint128Pair(verificationGasLimit, callGasLimit))

        // preVerificationGas (uint256)
        data.append(padUInt256(preVerificationGas))

        // gasFees (bytes32) = maxPriorityFeePerGas (high 128 bits) || maxFeePerGas (low 128 bits)
        data.append(packUint128Pair(maxPriorityFeePerGas, maxFeePerGas))

        // hashPaymasterAndData = keccak256(paymasterAndData)
        data.append(paymasterAndData.sha3(.keccak256))

        return data
    }

    /// Pack two uint128 values into a bytes32
    private func packUint128Pair(_ high: BigUInt, _ low: BigUInt) -> Data {
        let highHex = String(high, radix: 16)
        let lowHex = String(low, radix: 16)
        let highPadded = String(repeating: "0", count: 32 - highHex.count) + highHex
        let lowPadded = String(repeating: "0", count: 32 - lowHex.count) + lowHex
        return Data(hex: highPadded + lowPadded)
    }

    // MARK: - JSON-RPC Encoding

    /// Convert to dictionary for bundler JSON-RPC calls (EntryPoint v0.7 format)
    func toRPCDict() -> [String: Any] {
        var dict: [String: Any] = [
            "sender": sender,
            "nonce": nonce.hexString,
            "callData": callData.hexString,
            "callGasLimit": callGasLimit.hexString,
            "verificationGasLimit": verificationGasLimit.hexString,
            "preVerificationGas": preVerificationGas.hexString,
            "maxFeePerGas": maxFeePerGas.hexString,
            "maxPriorityFeePerGas": maxPriorityFeePerGas.hexString,
            "signature": signature.hexString
        ]

        // v0.7: Split initCode into factory + factoryData
        if initCode.isEmpty {
            dict["factory"] = NSNull()
            dict["factoryData"] = NSNull()
        } else if initCode.count >= 20 {
            let factoryAddress = "0x" + initCode.prefix(20).map { String(format: "%02x", $0) }.joined()
            let factoryData = "0x" + initCode.dropFirst(20).map { String(format: "%02x", $0) }.joined()
            dict["factory"] = factoryAddress
            dict["factoryData"] = factoryData
        } else {
            dict["factory"] = NSNull()
            dict["factoryData"] = NSNull()
        }

        // v0.7: Split paymasterAndData into separate fields
        if paymasterAndData.isEmpty {
            dict["paymaster"] = NSNull()
            dict["paymasterVerificationGasLimit"] = NSNull()
            dict["paymasterPostOpGasLimit"] = NSNull()
            dict["paymasterData"] = NSNull()
        } else if paymasterAndData.count >= 20 {
            let paymasterAddress = "0x" + paymasterAndData.prefix(20).map { String(format: "%02x", $0) }.joined()
            let paymasterData = "0x" + paymasterAndData.dropFirst(20).map { String(format: "%02x", $0) }.joined()
            dict["paymaster"] = paymasterAddress
            dict["paymasterVerificationGasLimit"] = "0x30d40"  // 200000 default
            dict["paymasterPostOpGasLimit"] = "0x0"
            dict["paymasterData"] = paymasterData
        } else {
            dict["paymaster"] = NSNull()
            dict["paymasterVerificationGasLimit"] = NSNull()
            dict["paymasterPostOpGasLimit"] = NSNull()
            dict["paymasterData"] = NSNull()
        }

        return dict
    }

    // MARK: - Helpers

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

    // MARK: - Computed Properties

    /// Total gas limit for the operation
    var totalGasLimit: BigUInt {
        callGasLimit + verificationGasLimit + preVerificationGas
    }

    /// Maximum cost in wei (before paymaster refund)
    var maxCost: BigUInt {
        totalGasLimit * maxFeePerGas
    }

    /// Whether this is a deployment operation (first tx for account)
    var isDeployment: Bool {
        !initCode.isEmpty
    }

    /// Whether this uses a paymaster
    var usesPaymaster: Bool {
        !paymasterAndData.isEmpty
    }
}

// MARK: - BigUInt Hex Extension

extension BigUInt {
    var hexString: String {
        "0x" + String(self, radix: 16)
    }

    init?(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        self.init(hex, radix: 16)
    }
}

// MARK: - Data Hex Extension (uses HexUtils extension)
// Note: hexString (with 0x prefix) is provided by HexUtils.swift extension on Data

// MARK: - UserOperation Call

/// Represents a single call within a UserOperation
struct UserOperationCall {
    let to: String
    let value: BigUInt
    let data: Data

    init(to: String, value: BigUInt = 0, data: Data = Data()) {
        self.to = to
        self.value = value
        self.data = data
    }

    /// Simple ETH transfer
    static func transfer(to: String, value: BigUInt) -> UserOperationCall {
        UserOperationCall(to: to, value: value)
    }

    /// Contract call
    static func contractCall(to: String, data: Data) -> UserOperationCall {
        UserOperationCall(to: to, value: 0, data: data)
    }

    /// Contract call with value
    static func contractCallWithValue(to: String, value: BigUInt, data: Data) -> UserOperationCall {
        UserOperationCall(to: to, value: value, data: data)
    }
}
