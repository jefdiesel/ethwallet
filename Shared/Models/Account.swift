import Foundation
import BigInt

/// Represents a single derived Ethereum account from an HD wallet
struct Account: Identifiable, Codable, Hashable {
    let id: UUID
    let index: Int                 // Derivation index (0, 1, 2, ...)
    let address: String            // 0x... checksummed
    var label: String              // User-defined name
    var smartAccountId: UUID?      // Optional linked smart account ID

    /// BIP44 derivation path for this account
    var derivationPath: String {
        "m/44'/60'/0'/0/\(index)"
    }

    init(id: UUID = UUID(), index: Int, address: String, label: String? = nil, smartAccountId: UUID? = nil) {
        self.id = id
        self.index = index
        self.address = address
        self.label = label ?? "Account \(index + 1)"
        self.smartAccountId = smartAccountId
    }

    /// Abbreviated address for display (0x1234...5678)
    var shortAddress: String {
        guard address.count >= 10 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    /// Whether this account has an associated smart account
    var hasSmartAccount: Bool {
        smartAccountId != nil
    }

    /// The type of this account (EOA or Smart)
    var accountType: AccountType {
        hasSmartAccount ? .smart : .eoa
    }
}

// MARK: - Account Type

enum AccountType: String, Codable {
    case eoa = "eoa"
    case smart = "smart"

    var displayName: String {
        switch self {
        case .eoa: return "Standard"
        case .smart: return "Smart Account"
        }
    }

    var description: String {
        switch self {
        case .eoa: return "Externally Owned Account"
        case .smart: return "ERC-4337 Smart Account"
        }
    }
}

// MARK: - Account Balance

struct AccountBalance: Identifiable {
    var id: String { "\(account.id)-\(network.id)" }
    let account: Account
    let network: Network
    var balance: BigUInt
    var formattedBalance: String {
        formatEther(balance)
    }

    private func formatEther(_ wei: BigUInt) -> String {
        let divisor = BigUInt(10).power(18)
        let wholePart = wei / divisor
        let fractionalPart = wei % divisor

        // Format with up to 6 decimal places
        let fractionalString = String(fractionalPart)
        let paddedFractional = String(repeating: "0", count: 18 - fractionalString.count) + fractionalString
        let trimmedFractional = String(paddedFractional.prefix(6)).trimmingCharacters(in: CharacterSet(charactersIn: "0"))

        if trimmedFractional.isEmpty {
            return "\(wholePart)"
        }
        return "\(wholePart).\(trimmedFractional)"
    }
}

