import Foundation

// MARK: - EthscriptionNameTransaction

/// Builds transaction data for Ethscription name operations
///
/// Use this to construct the raw transaction parameters needed to:
/// - Claim a new name (inscription)
/// - Transfer a name to another address
///
/// ## Claiming a Name
///
/// To claim a name, send a transaction **to yourself** with the name's
/// calldata. The ethscription is created when the transaction is mined.
///
/// ```swift
/// let tx = EthscriptionNameTransaction.claim("alice", from: myAddress)
///
/// // Use with your preferred web3 library:
/// let rawTx = Transaction(
///     to: tx.to,
///     value: tx.value,      // 0
///     data: tx.calldata
/// )
/// ```
///
/// ## Transferring a Name
///
/// To transfer a name, you need the ethscription's transaction hash (ID).
/// Send a transaction to the recipient with the hash as calldata.
///
/// ```swift
/// let tx = EthscriptionNameTransaction.transfer(
///     ethscriptionId: "0x123...",
///     to: recipientAddress
/// )
/// ```
public struct EthscriptionNameTransaction: Sendable {

    /// The recipient address for this transaction
    public let to: String

    /// The transaction value in wei (always 0 for ethscriptions)
    public let value: String

    /// The hex-encoded calldata
    public let calldata: String

    /// The type of transaction
    public let type: TransactionType

    /// Transaction types
    public enum TransactionType: Sendable {
        /// Claiming a new name
        case claim(EthscriptionName)
        /// Transferring an existing name
        case transfer(ethscriptionId: String)
    }

    // MARK: - Factory Methods

    /// Create a transaction to claim a new name
    ///
    /// The transaction must be sent **from and to the same address** (self-inscription).
    /// The sender will become the owner of the name once the transaction is mined.
    ///
    /// - Parameters:
    ///   - name: The name to claim (e.g., "alice")
    ///   - from: Your Ethereum address (sender and recipient)
    /// - Returns: Transaction parameters ready to sign and send
    /// - Throws: `EthscriptionNameError.invalidFormat` if the name is invalid
    public static func claim(_ name: String, from address: String) throws -> EthscriptionNameTransaction {
        let ethName = try EthscriptionName(name)
        return claim(ethName, from: address)
    }

    /// Create a transaction to claim a new name
    ///
    /// - Parameters:
    ///   - name: The EthscriptionName to claim
    ///   - from: Your Ethereum address (sender and recipient)
    /// - Returns: Transaction parameters ready to sign and send
    public static func claim(_ name: EthscriptionName, from address: String) -> EthscriptionNameTransaction {
        return EthscriptionNameTransaction(
            to: address.lowercased(),
            value: "0x0",
            calldata: name.calldata,
            type: .claim(name)
        )
    }

    /// Create a transaction to transfer a name
    ///
    /// To transfer an ethscription, send a transaction to the recipient
    /// with the ethscription's transaction hash as the calldata.
    ///
    /// - Parameters:
    ///   - ethscriptionId: The transaction hash of the ethscription (0x...)
    ///   - to: The recipient's Ethereum address
    /// - Returns: Transaction parameters ready to sign and send
    public static func transfer(ethscriptionId: String, to recipient: String) -> EthscriptionNameTransaction {
        // Ensure the ID has 0x prefix
        let normalizedId = ethscriptionId.hasPrefix("0x") ? ethscriptionId : "0x" + ethscriptionId

        return EthscriptionNameTransaction(
            to: recipient.lowercased(),
            value: "0x0",
            calldata: normalizedId.lowercased(),
            type: .transfer(ethscriptionId: normalizedId)
        )
    }

    /// Create a transaction for bulk transfer (ESIP-5)
    ///
    /// Transfer multiple ethscriptions to the same recipient in one transaction.
    /// The calldata is the concatenation of all transaction hashes.
    ///
    /// - Parameters:
    ///   - ethscriptionIds: Array of transaction hashes to transfer
    ///   - to: The recipient's Ethereum address
    /// - Returns: Transaction parameters ready to sign and send
    public static func bulkTransfer(ethscriptionIds: [String], to recipient: String) -> EthscriptionNameTransaction {
        // ESIP-5: Concatenate hashes without 0x prefix, then add single 0x prefix
        let concatenated = ethscriptionIds
            .map { $0.hasPrefix("0x") ? String($0.dropFirst(2)) : $0 }
            .joined()

        return EthscriptionNameTransaction(
            to: recipient.lowercased(),
            value: "0x0",
            calldata: "0x" + concatenated.lowercased(),
            type: .transfer(ethscriptionId: "bulk:\(ethscriptionIds.count)")
        )
    }

    // MARK: - Validation

    /// Validate that an address is properly formatted
    public static func isValidAddress(_ address: String) -> Bool {
        let clean = address.lowercased()
        guard clean.hasPrefix("0x") && clean.count == 42 else {
            return false
        }
        let hex = String(clean.dropFirst(2))
        return hex.allSatisfy { $0.isHexDigit }
    }

    /// Validate that a transaction hash is properly formatted
    public static func isValidTransactionHash(_ hash: String) -> Bool {
        let clean = hash.lowercased()
        guard clean.hasPrefix("0x") && clean.count == 66 else {
            return false
        }
        let hex = String(clean.dropFirst(2))
        return hex.allSatisfy { $0.isHexDigit }
    }
}

// MARK: - Gas Estimation

extension EthscriptionNameTransaction {

    /// Estimated gas limit for this transaction
    ///
    /// Ethscription transactions are simple transfers with calldata.
    /// Gas cost is primarily determined by calldata size.
    public var estimatedGasLimit: UInt64 {
        // Base cost: 21,000 for transfer
        // Calldata: 16 gas per non-zero byte, 4 gas per zero byte
        // Most calldata bytes are non-zero for text content
        let baseGas: UInt64 = 21_000
        let calldataBytes = (calldata.count - 2) / 2  // Remove 0x, divide by 2 for hex
        let calldataGas = UInt64(calldataBytes) * 16
        return baseGas + calldataGas + 5000  // Add buffer
    }

    /// Estimate the total cost in wei
    ///
    /// - Parameter gasPriceWei: The gas price in wei
    /// - Returns: Total cost in wei (gas limit * gas price)
    public func estimateCost(gasPriceWei: UInt64) -> UInt64 {
        return estimatedGasLimit * gasPriceWei
    }
}

// MARK: - Description

extension EthscriptionNameTransaction: CustomStringConvertible {
    public var description: String {
        switch type {
        case .claim(let name):
            return "Claim '\(name.displayName)' -> \(truncate(to))"
        case .transfer(let id):
            if id.hasPrefix("bulk:") {
                return "Bulk transfer \(id) -> \(truncate(to))"
            }
            return "Transfer \(truncate(id)) -> \(truncate(to))"
        }
    }

    private func truncate(_ s: String) -> String {
        guard s.count > 12 else { return s }
        return "\(s.prefix(6))...\(s.suffix(4))"
    }
}
