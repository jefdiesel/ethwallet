import Foundation

/// ABI encoder for Ethereum contract calls
enum ABIEncoder {

    // MARK: - Function Calls

    /// Encode a function call with parameters
    /// - Parameters:
    ///   - selector: 4-byte function selector (hex string with 0x prefix)
    ///   - parameters: Array of parameters to encode
    /// - Returns: Encoded calldata as hex string
    static func encodeFunctionCall(
        selector: String,
        parameters: [ABIValue]
    ) -> String {
        var result = selector.hasPrefix("0x") ? String(selector.dropFirst(2)) : selector

        for param in parameters {
            result += encodeParameter(param)
        }

        return "0x" + result
    }

    /// Encode a single parameter to 32-byte hex
    static func encodeParameter(_ value: ABIValue) -> String {
        switch value {
        case .uint256(let number):
            return padLeft(String(number, radix: 16), to: 64)

        case .int256(let number):
            if number >= 0 {
                return padLeft(String(number, radix: 16), to: 64)
            } else {
                // Two's complement for negative numbers
                let twosComplement = UInt64(bitPattern: number)
                return padLeft(String(twosComplement, radix: 16), to: 64)
            }

        case .address(let addr):
            var hex = addr.lowercased()
            if hex.hasPrefix("0x") {
                hex = String(hex.dropFirst(2))
            }
            return padLeft(hex, to: 64)

        case .bytes32(let data):
            var hex: String
            if let stringData = data as? String {
                hex = stringData.hasPrefix("0x") ? String(stringData.dropFirst(2)) : stringData
            } else if let dataData = data as? Data {
                hex = dataData.hexStringWithoutPrefix
            } else {
                hex = ""
            }
            return padRight(hex, to: 64)

        case .bool(let flag):
            return padLeft(flag ? "1" : "0", to: 64)

        case .string(let str):
            // Dynamic type - encode offset, then length, then data
            guard let data = str.data(using: .utf8) else { return "" }
            return encodeDynamicBytes(data)

        case .bytes(let data):
            return encodeDynamicBytes(data)
        }
    }

    // MARK: - Decoding

    /// Decode an ABI-encoded response
    static func decodeResponse(_ hex: String, types: [ABIType]) -> [ABIValue]? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count >= types.count * 64 else { return nil }

        var results: [ABIValue] = []
        var offset = 0

        for type in types {
            let chunk = String(hex.dropFirst(offset).prefix(64))
            offset += 64

            switch type {
            case .uint256:
                if let value = UInt64(chunk, radix: 16) {
                    results.append(.uint256(value))
                }

            case .int256:
                if let value = UInt64(chunk, radix: 16) {
                    results.append(.int256(Int64(bitPattern: value)))
                }

            case .address:
                // Address is in the last 20 bytes (40 hex chars)
                let addressHex = String(chunk.suffix(40))
                results.append(.address("0x" + addressHex))

            case .bytes32:
                results.append(.bytes32("0x" + chunk))

            case .bool:
                let value = chunk.last == "1"
                results.append(.bool(value))

            case .string, .bytes:
                // Dynamic types need special handling
                if let dataOffset = UInt64(chunk, radix: 16) {
                    let actualOffset = Int(dataOffset) * 2  // Convert to hex char offset
                    if let decoded = decodeDynamicBytes(from: hex, at: actualOffset) {
                        if type == .string {
                            if let str = String(data: decoded, encoding: .utf8) {
                                results.append(.string(str))
                            }
                        } else {
                            results.append(.bytes(decoded))
                        }
                    }
                }
            }
        }

        return results.count == types.count ? results : nil
    }

    /// Decode a single address from ABI response
    static func decodeAddress(_ hex: String) -> String? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard hex.count >= 64 else { return nil }
        let addressHex = String(hex.prefix(64).suffix(40))
        return "0x" + addressHex
    }

    /// Decode a single uint256 from ABI response
    static func decodeUInt256(_ hex: String) -> UInt64? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard hex.count >= 64 else { return nil }
        return UInt64(hex.prefix(64), radix: 16)
    }

    /// Decode an ABI-encoded string
    static func decodeString(_ hex: String) -> String? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        // First 32 bytes is offset to string data
        guard hex.count >= 64 else { return nil }
        guard let offset = UInt64(hex.prefix(64), radix: 16) else { return nil }

        let dataStart = Int(offset) * 2  // Convert byte offset to hex char offset
        guard hex.count >= dataStart + 64 else { return nil }

        // Next 32 bytes at offset is string length
        let lengthHex = String(hex.dropFirst(dataStart).prefix(64))
        guard let length = UInt64(lengthHex, radix: 16) else { return nil }

        // Read the string data
        let stringDataStart = dataStart + 64
        let stringDataLength = Int(length) * 2  // Convert to hex chars
        guard hex.count >= stringDataStart + stringDataLength else { return nil }

        let stringHex = String(hex.dropFirst(stringDataStart).prefix(stringDataLength))
        guard let data = HexUtils.decode("0x" + stringHex) else { return nil }

        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helper Functions

    private static func padLeft(_ hex: String, to length: Int) -> String {
        if hex.count >= length { return String(hex.suffix(length)) }
        return String(repeating: "0", count: length - hex.count) + hex
    }

    private static func padRight(_ hex: String, to length: Int) -> String {
        if hex.count >= length { return String(hex.prefix(length)) }
        return hex + String(repeating: "0", count: length - hex.count)
    }

    private static func encodeDynamicBytes(_ data: Data) -> String {
        // Length (32 bytes)
        let length = padLeft(String(data.count, radix: 16), to: 64)

        // Data (padded to 32 byte boundary)
        var dataHex = data.hexStringWithoutPrefix
        let padding = (32 - (data.count % 32)) % 32
        dataHex += String(repeating: "0", count: padding * 2)

        return length + dataHex
    }

    private static func decodeDynamicBytes(from hex: String, at offset: Int) -> Data? {
        guard hex.count >= offset + 64 else { return nil }

        // Read length
        let lengthHex = String(hex.dropFirst(offset).prefix(64))
        guard let length = UInt64(lengthHex, radix: 16) else { return nil }

        // Read data
        let dataStart = offset + 64
        let dataLength = Int(length) * 2
        guard hex.count >= dataStart + dataLength else { return nil }

        let dataHex = String(hex.dropFirst(dataStart).prefix(dataLength))
        return HexUtils.decode("0x" + dataHex)
    }
}

// MARK: - ABI Types

enum ABIType {
    case uint256
    case int256
    case address
    case bytes32
    case bool
    case string
    case bytes
}

enum ABIValue {
    case uint256(UInt64)
    case int256(Int64)
    case address(String)
    case bytes32(Any)  // String or Data
    case bool(Bool)
    case string(String)
    case bytes(Data)
}

// MARK: - Common Function Selectors

enum FunctionSelector {
    // ERC-20
    static let balanceOf = "0x70a08231"        // balanceOf(address)
    static let transfer = "0xa9059cbb"         // transfer(address,uint256)
    static let approve = "0x095ea7b3"          // approve(address,uint256)
    static let allowance = "0xdd62ed3e"        // allowance(address,address)

    // ERC-721
    static let ownerOf = "0x6352211e"          // ownerOf(uint256)
    static let tokenURI = "0xc87b56dd"         // tokenURI(uint256)
    static let safeTransferFrom = "0x42842e0e" // safeTransferFrom(address,address,uint256)

    // Ethscriptions AppChain Manager
    static let getMembershipOfEthscription = "0x73a3a428"  // getMembershipOfEthscription(bytes32)
}
