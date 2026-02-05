import Foundation

/// Utilities for hex encoding and decoding
enum HexUtils {

    // MARK: - Encoding

    /// Convert Data to hex string with 0x prefix
    static func encode(_ data: Data) -> String {
        "0x" + data.map { String(format: "%02x", $0) }.joined()
    }

    /// Convert Data to hex string without prefix
    static func encodeWithoutPrefix(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Convert string to hex-encoded data (UTF-8)
    static func encodeString(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "0x" }
        return encode(data)
    }

    /// Convert integer to hex string with 0x prefix
    static func encode(_ value: UInt64, padTo bytes: Int = 0) -> String {
        var hex = String(value, radix: 16)
        if bytes > 0 {
            let targetLength = bytes * 2
            if hex.count < targetLength {
                hex = String(repeating: "0", count: targetLength - hex.count) + hex
            }
        }
        return "0x" + hex
    }

    // MARK: - Decoding

    /// Decode hex string to Data
    static func decode(_ hex: String) -> Data? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        guard hex.count % 2 == 0 else { return nil }

        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }

        return data
    }

    /// Decode hex string to UTF-8 string
    static func decodeToString(_ hex: String) -> String? {
        guard let data = decode(hex) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode hex string to UInt64
    static func decodeToUInt64(_ hex: String) -> UInt64? {
        var hex = hex.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        return UInt64(hex, radix: 16)
    }

    // MARK: - Validation

    /// Check if string is valid hex (with or without 0x prefix)
    static func isValidHex(_ string: String) -> Bool {
        var hex = string.lowercased()
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        guard !hex.isEmpty else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    /// Check if string is valid Ethereum address
    static func isValidAddress(_ address: String) -> Bool {
        guard address.hasPrefix("0x") || address.hasPrefix("0X") else { return false }
        let hex = String(address.dropFirst(2))
        return hex.count == 40 && hex.allSatisfy { $0.isHexDigit }
    }

    /// Check if string is valid transaction hash
    static func isValidTxHash(_ hash: String) -> Bool {
        guard hash.hasPrefix("0x") || hash.hasPrefix("0X") else { return false }
        let hex = String(hash.dropFirst(2))
        return hex.count == 64 && hex.allSatisfy { $0.isHexDigit }
    }

    // MARK: - Formatting

    /// Pad hex string to specified byte length (left-pad with zeros)
    static func padLeft(_ hex: String, toBytes bytes: Int) -> String {
        var hex = hex
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }

        let targetLength = bytes * 2
        if hex.count < targetLength {
            hex = String(repeating: "0", count: targetLength - hex.count) + hex
        }
        return "0x" + hex
    }

    /// Convert checksummed address to lowercase
    static func toLowercase(_ address: String) -> String {
        guard address.hasPrefix("0x") else { return address.lowercased() }
        return "0x" + String(address.dropFirst(2)).lowercased()
    }
}

// MARK: - Data Extension

extension Data {
    /// Hex string representation with 0x prefix
    var hexString: String {
        HexUtils.encode(self)
    }

    /// Hex string representation without prefix
    var hexStringWithoutPrefix: String {
        HexUtils.encodeWithoutPrefix(self)
    }
}

// MARK: - String Extension

extension String {
    /// Initialize from hex string
    init?(hexString: String) {
        guard let decoded = HexUtils.decodeToString(hexString) else { return nil }
        self = decoded
    }

    /// Convert string to hex (UTF-8 encoded)
    var hexEncoded: String {
        HexUtils.encodeString(self)
    }

    /// Check if string is valid hex
    var isValidHex: Bool {
        HexUtils.isValidHex(self)
    }

    /// Check if string is valid Ethereum address
    var isValidEthereumAddress: Bool {
        HexUtils.isValidAddress(self)
    }
}
