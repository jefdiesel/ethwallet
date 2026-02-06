import Foundation
import BigInt
import CryptoSwift

/// Encoder for ERC-4337 UserOperation data
enum UserOperationEncoder {

    // MARK: - SimpleAccount Execute Encoding

    /// Encode a single execute call for SimpleAccount
    /// execute(address dest, uint256 value, bytes calldata func)
    /// Selector: 0xb61d27f6
    static func encodeExecute(to: String, value: BigUInt, data: Data) -> Data {
        var encoded = Data()

        // Function selector
        encoded.append(Data(hex: String(ERC4337Constants.Selectors.execute.dropFirst(2))))

        // dest (address) - padded to 32 bytes
        encoded.append(padAddress(to))

        // value (uint256)
        encoded.append(padUInt256(value))

        // func offset (points to dynamic data)
        encoded.append(padUInt256(BigUInt(96)))  // 3 * 32 bytes

        // func length
        encoded.append(padUInt256(BigUInt(data.count)))

        // func data (padded to 32-byte boundary)
        encoded.append(data)
        let padding = (32 - (data.count % 32)) % 32
        if padding > 0 {
            encoded.append(Data(repeating: 0, count: padding))
        }

        return encoded
    }

    /// Encode a batch execute call for SimpleAccount
    /// executeBatch(address[] dest, uint256[] values, bytes[] func)
    /// Selector: 0x47e1da2a
    static func encodeExecuteBatch(calls: [UserOperationCall]) -> Data {
        guard !calls.isEmpty else {
            return Data()
        }

        var encoded = Data()

        // Function selector
        encoded.append(Data(hex: String(ERC4337Constants.Selectors.executeBatch.dropFirst(2))))

        // Calculate offsets for dynamic arrays
        // Header: 3 offsets (3 * 32 = 96 bytes)
        let destArrayOffset: BigUInt = 96
        let valuesArrayOffset = destArrayOffset + BigUInt(32 + calls.count * 32)  // length + addresses
        let funcArrayOffset = valuesArrayOffset + BigUInt(32 + calls.count * 32)  // length + values

        // Encode offsets
        encoded.append(padUInt256(destArrayOffset))
        encoded.append(padUInt256(valuesArrayOffset))
        encoded.append(padUInt256(funcArrayOffset))

        // Encode dest array
        encoded.append(padUInt256(BigUInt(calls.count)))  // array length
        for call in calls {
            encoded.append(padAddress(call.to))
        }

        // Encode values array
        encoded.append(padUInt256(BigUInt(calls.count)))  // array length
        for call in calls {
            encoded.append(padUInt256(call.value))
        }

        // Encode func array (array of bytes)
        encoded.append(padUInt256(BigUInt(calls.count)))  // array length

        // Calculate offsets for each bytes element
        var currentOffset = BigUInt(calls.count * 32)  // After all offset slots
        var offsets: [BigUInt] = []
        var encodedFuncs: [Data] = []

        for call in calls {
            offsets.append(currentOffset)

            // Encode the bytes: length + data + padding
            var funcEncoded = Data()
            funcEncoded.append(padUInt256(BigUInt(call.data.count)))
            funcEncoded.append(call.data)
            let padding = (32 - (call.data.count % 32)) % 32
            if padding > 0 && !call.data.isEmpty {
                funcEncoded.append(Data(repeating: 0, count: padding))
            }
            if call.data.isEmpty {
                // Empty bytes still needs the length word
                funcEncoded = padUInt256(0)
            }

            encodedFuncs.append(funcEncoded)
            currentOffset += BigUInt(funcEncoded.count)
        }

        // Write offsets
        for offset in offsets {
            encoded.append(padUInt256(offset))
        }

        // Write encoded func data
        for funcData in encodedFuncs {
            encoded.append(funcData)
        }

        return encoded
    }

    // MARK: - Factory Init Code

    /// Encode initCode for SimpleAccountFactory.createAccount
    /// createAccount(address owner, uint256 salt)
    /// Selector: 0x5fbfb9cf
    static func encodeInitCode(factory: String, owner: String, salt: BigUInt) -> Data {
        var initCode = Data()

        // Factory address (20 bytes, no padding)
        var factoryHex = factory.lowercased()
        if factoryHex.hasPrefix("0x") {
            factoryHex = String(factoryHex.dropFirst(2))
        }
        initCode.append(Data(hex: factoryHex))

        // createAccount selector
        initCode.append(Data(hex: String(ERC4337Constants.Selectors.createAccount.dropFirst(2))))

        // owner (address)
        initCode.append(padAddress(owner))

        // salt (uint256)
        initCode.append(padUInt256(salt))

        return initCode
    }

    // MARK: - Address Computation

    /// Compute the counterfactual smart account address using CREATE2
    /// Address = keccak256(0xff ++ factory ++ salt ++ keccak256(initCode))[12:]
    static func computeAddress(
        factory: String,
        owner: String,
        salt: BigUInt,
        initCodeHash: Data
    ) -> String {
        var data = Data()

        // 0xff prefix
        data.append(0xff)

        // Factory address (20 bytes)
        var factoryHex = factory.lowercased()
        if factoryHex.hasPrefix("0x") {
            factoryHex = String(factoryHex.dropFirst(2))
        }
        data.append(Data(hex: factoryHex))

        // Combined salt: keccak256(owner ++ salt)
        let ownerPadded = padAddress(owner)
        let saltPadded = padUInt256(salt)
        let combinedSalt = (ownerPadded + saltPadded).sha3(.keccak256)
        data.append(combinedSalt)

        // Init code hash
        data.append(initCodeHash)

        // Hash and take last 20 bytes
        let hash = data.sha3(.keccak256)
        let addressBytes = hash.suffix(20)

        return "0x" + addressBytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - EntryPoint Nonce Encoding

    /// Encode getNonce call for EntryPoint
    /// getNonce(address sender, uint192 key)
    static func encodeGetNonce(sender: String, key: BigUInt = 0) -> Data {
        var encoded = Data()

        // Function selector
        encoded.append(Data(hex: String(ERC4337Constants.Selectors.entryPointGetNonce.dropFirst(2))))

        // sender (address)
        encoded.append(padAddress(sender))

        // key (uint192, padded to 32 bytes)
        encoded.append(padUInt256(key))

        return encoded
    }

    // MARK: - Signature Encoding

    /// Pack a signature for UserOperation
    /// For SimpleAccount, this is just the raw ECDSA signature
    static func encodeSignature(_ signature: Data) -> Data {
        // SimpleAccount expects raw 65-byte signature (r, s, v)
        return signature
    }

    // MARK: - EIP-712 Helpers

    /// Compute EIP-712 domain separator
    static func domainSeparator(chainId: Int, entryPoint: String) -> Data {
        // EIP-712 domain type hash
        let domainTypeHash = "EIP712Domain(uint256 chainId,address verifyingContract)".data(using: .utf8)!.sha3(.keccak256)

        var encoded = Data()
        encoded.append(domainTypeHash)
        encoded.append(padUInt256(BigUInt(chainId)))
        encoded.append(padAddress(entryPoint))

        return encoded.sha3(.keccak256)
    }

    // MARK: - Decoding

    /// Decode a revert reason from call result
    static func decodeRevertReason(_ data: Data) -> String? {
        // Error(string) selector: 0x08c379a0
        guard data.count >= 68,
              data.prefix(4) == Data(hex: "08c379a0") else {
            return nil
        }

        // Skip selector (4) + offset (32) + length location (32)
        // Read length
        let lengthOffset = 36
        guard data.count > lengthOffset + 32 else { return nil }

        let lengthData = data.subdata(in: lengthOffset..<(lengthOffset + 32))
        guard let length = BigUInt(lengthData.hexStringWithoutPrefix, radix: 16) else {
            return nil
        }

        // Read string
        let stringOffset = 68
        let stringLength = Int(length)
        guard data.count >= stringOffset + stringLength else { return nil }

        let stringData = data.subdata(in: stringOffset..<(stringOffset + stringLength))
        return String(data: stringData, encoding: .utf8)
    }

    /// Decode a uint256 from eth_call result
    static func decodeUInt256(_ hex: String) -> BigUInt? {
        var cleanHex = hex.lowercased()
        if cleanHex.hasPrefix("0x") {
            cleanHex = String(cleanHex.dropFirst(2))
        }
        return BigUInt(cleanHex, radix: 16)
    }

    // MARK: - Helpers

    private static func padAddress(_ address: String) -> Data {
        var hex = address.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        let padded = String(repeating: "0", count: 64 - hex.count) + hex
        return Data(hex: padded)
    }

    private static func padUInt256(_ value: BigUInt) -> Data {
        let hex = String(value, radix: 16)
        let padded = String(repeating: "0", count: 64 - hex.count) + hex
        return Data(hex: padded)
    }
}
