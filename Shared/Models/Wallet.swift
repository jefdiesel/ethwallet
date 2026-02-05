import Foundation

/// Represents an HD wallet with BIP39 mnemonic and derived accounts
struct Wallet: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var name: String
    var accounts: [Account]

    /// Number of words in the mnemonic (12 or 24)
    let mnemonicWordCount: Int

    init(
        id: UUID = UUID(),
        name: String = "My Wallet",
        accounts: [Account] = [],
        mnemonicWordCount: Int = 12
    ) {
        self.id = id
        self.createdAt = Date()
        self.name = name
        self.accounts = accounts
        self.mnemonicWordCount = mnemonicWordCount
    }

    /// The primary (first) account
    var primaryAccount: Account? {
        accounts.first
    }

    /// Add a new account at the next index
    mutating func addAccount(_ account: Account) {
        accounts.append(account)
    }

    /// Get account by index
    func account(at index: Int) -> Account? {
        accounts.first { $0.index == index }
    }
}

// MARK: - Wallet Creation Options

enum WalletCreationMethod {
    case generateNew(wordCount: MnemonicWordCount)
    case importMnemonic(words: [String])
    case importPrivateKey(hexString: String)
}

enum MnemonicWordCount: Int, CaseIterable {
    case twelve = 12
    case twentyFour = 24

    var entropyBits: Int {
        switch self {
        case .twelve: return 128
        case .twentyFour: return 256
        }
    }
}

// MARK: - Wallet Metadata (stored separately from seed)

struct WalletMetadata: Codable {
    let walletId: UUID
    var name: String
    var accountLabels: [Int: String]  // index -> label
    var lastSelectedAccountIndex: Int
    var lastSelectedNetworkId: Int

    init(walletId: UUID, name: String = "My Wallet") {
        self.walletId = walletId
        self.name = name
        self.accountLabels = [:]
        self.lastSelectedAccountIndex = 0
        self.lastSelectedNetworkId = Network.ethereum.id
    }
}
