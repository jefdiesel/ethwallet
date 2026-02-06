import Foundation
import BigInt
import web3swift
import Web3Core

/// Service for fetching ERC-20 token balances and info
final class TokenService {
    static let shared = TokenService()

    private var web3Service: Web3Service

    private init(web3Service: Web3Service = Web3Service()) {
        self.web3Service = web3Service
    }

    /// Switch the network for the service
    func switchNetwork(_ network: Network) {
        self.web3Service = Web3Service(network: network)
    }

    // MARK: - Token Balances

    /// Get balance of a specific token for an address
    func getBalance(of token: Token, for address: String) async throws -> TokenBalance {
        // balanceOf(address) selector: 0x70a08231
        let selector = "0x70a08231"
        let paddedAddress = address.lowercased().replacingOccurrences(of: "0x", with: "").leftPadded(to: 64)
        let calldata = selector + paddedAddress

        let result = try await web3Service.call(to: token.address, data: calldata)

        // Parse hex result to BigInt
        let hexBalance = result.replacingOccurrences(of: "0x", with: "")
        let rawBalance = BigUInt(hexBalance, radix: 16) ?? BigUInt(0)

        // Format with decimals
        let formatted = formatTokenAmount(rawBalance, decimals: token.decimals)

        return TokenBalance(
            token: token,
            rawBalance: String(rawBalance),
            formattedBalance: formatted,
            usdValue: nil  // Would need price feed
        )
    }

    /// Get balances for multiple tokens
    func getBalances(of tokens: [Token], for address: String) async -> [TokenBalance] {
        var balances: [TokenBalance] = []

        for token in tokens {
            do {
                let balance = try await getBalance(of: token, for: address)
                balances.append(balance)
            } catch {
                // Skip tokens that fail
                continue
            }
        }

        return balances
    }

    /// Get common token balances
    func getCommonTokenBalances(for address: String, chainId: Int) async -> [TokenBalance] {
        let commonTokens: [Token]

        switch chainId {
        case 1: // Ethereum mainnet
            commonTokens = [.usdc, .usdt, .weth, .dai]
        default:
            commonTokens = []
        }

        return await getBalances(of: commonTokens, for: address)
    }

    // MARK: - Token Info

    /// Get token info from contract
    func getTokenInfo(address: String, chainId: Int) async throws -> Token {
        async let name = getTokenName(address)
        async let symbol = getTokenSymbol(address)
        async let decimals = getTokenDecimals(address)

        return Token(
            address: address,
            symbol: try await symbol,
            name: try await name,
            decimals: try await decimals,
            logoURL: nil,
            chainId: chainId
        )
    }

    private func getTokenName(_ address: String) async throws -> String {
        // name() selector: 0x06fdde03
        let result = try await web3Service.call(to: address, data: "0x06fdde03")
        return decodeString(result) ?? "Unknown"
    }

    private func getTokenSymbol(_ address: String) async throws -> String {
        // symbol() selector: 0x95d89b41
        let result = try await web3Service.call(to: address, data: "0x95d89b41")
        return decodeString(result) ?? "???"
    }

    private func getTokenDecimals(_ address: String) async throws -> Int {
        // decimals() selector: 0x313ce567
        let result = try await web3Service.call(to: address, data: "0x313ce567")
        let hex = result.replacingOccurrences(of: "0x", with: "")
        return Int(hex, radix: 16) ?? 18
    }

    // MARK: - Token Transfers

    /// Build calldata for ERC-20 transfer
    func buildTransferCalldata(to: String, amount: BigUInt) -> Data {
        // transfer(address,uint256) selector: 0xa9059cbb
        let selector = Data([0xa9, 0x05, 0x9c, 0xbb])
        let toAddress = to.lowercased().replacingOccurrences(of: "0x", with: "").leftPadded(to: 64)
        let amountHex = String(amount, radix: 16).leftPadded(to: 64)

        var calldata = selector
        if let toData = Data(hexString: toAddress) {
            calldata.append(toData)
        }
        if let amountData = Data(hexString: amountHex) {
            calldata.append(amountData)
        }

        return calldata
    }

    /// Transfer ERC-20 tokens
    func transfer(
        token: Token,
        to: String,
        amount: BigUInt,
        from: String,
        privateKey: Data
    ) async throws -> String {
        let calldata = buildTransferCalldata(to: to, amount: amount)

        let transaction = try await web3Service.buildTransaction(
            from: from,
            to: token.address,
            value: 0,
            data: calldata
        )

        return try await web3Service.sendTransaction(transaction, privateKey: privateKey)
    }

    /// Estimate gas for token transfer
    func estimateTransferGas(
        token: Token,
        to: String,
        amount: BigUInt,
        from: String
    ) async throws -> GasEstimate {
        let calldata = buildTransferCalldata(to: to, amount: amount)

        let request = TransactionRequest(
            from: from,
            to: token.address,
            value: 0,
            data: calldata,
            chainId: token.chainId
        )

        let gasLimit = try await web3Service.estimateGas(for: request)
        let gasPrice = try await web3Service.getGasPrice()

        return GasEstimate(
            gasLimit: gasLimit,
            maxFeePerGas: gasPrice,
            maxPriorityFeePerGas: gasPrice / 10,
            estimatedCost: gasLimit * gasPrice
        )
    }

    /// Parse a token amount string to raw value (accounting for decimals)
    func parseTokenAmount(_ amount: String, decimals: Int) -> BigUInt? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return BigUInt(0) }

        let components = trimmed.split(separator: ".")
        guard components.count <= 2 else { return nil }

        let wholePart = BigUInt(String(components[0])) ?? BigUInt(0)

        let fractionalPart: BigUInt
        if components.count == 2 {
            var fractionalString = String(components[1])
            if fractionalString.count > decimals {
                fractionalString = String(fractionalString.prefix(decimals))
            } else {
                fractionalString += String(repeating: "0", count: decimals - fractionalString.count)
            }
            fractionalPart = BigUInt(fractionalString) ?? BigUInt(0)
        } else {
            fractionalPart = BigUInt(0)
        }

        let multiplier = BigUInt(10).power(decimals)
        return wholePart * multiplier + fractionalPart
    }

    // MARK: - Helpers

    private func formatTokenAmount(_ amount: BigUInt, decimals: Int) -> String {
        let divisor = BigUInt(10).power(decimals)
        let wholePart = amount / divisor
        let fractionalPart = amount % divisor

        if fractionalPart == 0 {
            return String(wholePart)
        }

        let fractionalString = String(fractionalPart)
            .leftPadded(to: decimals, with: "0")
            .trimmingTrailingZeros()

        if fractionalString.isEmpty {
            return String(wholePart)
        }

        return "\(wholePart).\(fractionalString)"
    }

    private func decodeString(_ hex: String) -> String? {
        // ABI-encoded string: offset (32 bytes) + length (32 bytes) + data
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        guard clean.count >= 128 else { return nil }

        // Get length from second 32-byte word
        let lengthHex = String(clean.dropFirst(64).prefix(64))
        guard let length = Int(lengthHex, radix: 16), length > 0 else { return nil }

        // Get string data
        let dataHex = String(clean.dropFirst(128).prefix(length * 2))
        guard let data = Data(hexString: dataHex) else { return nil }

        return String(data: data, encoding: .utf8)
    }
}

// MARK: - String Extensions

private extension String {
    func leftPadded(to length: Int, with char: Character = "0") -> String {
        if count >= length { return self }
        return String(repeating: char, count: length - count) + self
    }

    func trimmingTrailingZeros() -> String {
        var result = self
        while result.hasSuffix("0") && result.count > 1 {
            result.removeLast()
        }
        return result
    }
}

private extension Data {
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: "0x", with: "")
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
