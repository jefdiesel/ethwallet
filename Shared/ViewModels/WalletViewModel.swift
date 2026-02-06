import Foundation
import Combine
import web3swift
import Web3Core

/// Main view model for wallet state management
@MainActor
final class WalletViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var wallet: Wallet?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: WalletError?
    @Published private(set) var hasWallet: Bool = false

    /// User-friendly error message for display in views
    var loadError: String? {
        error?.errorDescription
    }

    /// Flag to prevent duplicate loadWallet calls
    private var isLoadingWallet: Bool = false

    @Published var selectedAccount: Account? {
        didSet {
            if let account = selectedAccount {
                saveLastSelectedAccount(account)
                Task { await refreshBalance() }
            }
        }
    }

    @Published var selectedNetwork: Network = .ethereum {
        didSet {
            networkManager.selectNetwork(selectedNetwork)
            web3Service.switchNetwork(selectedNetwork)
            Task { await refreshBalance() }
        }
    }

    @Published private(set) var balance: String = "0"
    @Published private(set) var balanceUSD: String = "$0.00"

    // Smart account state
    @Published var smartAccountViewModel = SmartAccountViewModel()

    // MARK: - Services

    private let keychainService: KeychainService
    private let web3Service: Web3Service
    private let networkManager: NetworkManager
    private let priceService: PriceService

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        keychainService: KeychainService = .shared,
        web3Service: Web3Service = Web3Service(),
        networkManager: NetworkManager = .shared,
        priceService: PriceService = .shared
    ) {
        self.keychainService = keychainService
        self.web3Service = web3Service
        self.networkManager = networkManager
        self.priceService = priceService

        setupBindings()
        checkExistingWallet()
    }

    private func setupBindings() {
        // Update balance when network changes
        NotificationCenter.default.publisher(for: .networkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refreshBalance() }
            }
            .store(in: &cancellables)

        // Update USD value when price changes
        priceService.$ethPrice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUSDBalance()
            }
            .store(in: &cancellables)

        // Sync smart account network when wallet network changes
        $selectedNetwork
            .receive(on: DispatchQueue.main)
            .sink { [weak self] network in
                self?.smartAccountViewModel.switchNetwork(network)
            }
            .store(in: &cancellables)
    }

    // MARK: - Wallet Management

    /// Check if a wallet already exists
    func checkExistingWallet() {
        hasWallet = keychainService.seedExists()
        if hasWallet {
            Task { await loadWallet() }
        }
    }

    /// Create a new wallet with generated mnemonic
    func createWallet(wordCount: MnemonicWordCount = .twelve) async throws -> String {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            // Generate mnemonic
            let mnemonic = try web3Service.generateMnemonic(wordCount: wordCount)

            // Derive wallet from mnemonic
            let (seed, accounts) = try web3Service.deriveWallet(from: mnemonic)

            // Store seed securely
            try keychainService.storeSeed(seed, for: "default")

            // Create wallet model
            let wallet = Wallet(
                name: "My Wallet",
                accounts: accounts,
                mnemonicWordCount: wordCount.rawValue
            )

            // Save wallet metadata
            saveWalletMetadata(wallet)

            // Update state
            self.wallet = wallet
            self.selectedAccount = accounts.first
            self.hasWallet = true

            // Refresh balance
            await refreshBalance()

            return mnemonic
        } catch {
            self.error = .creationFailed(error.localizedDescription)
            throw error
        }
    }

    /// Import wallet from mnemonic phrase
    func importWallet(mnemonic: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            // Validate and derive wallet
            let (seed, accounts) = try web3Service.deriveWallet(from: mnemonic)

            // Store seed securely
            try keychainService.storeSeed(seed, for: "default")

            // Determine word count
            let wordCount = mnemonic.split(separator: " ").count

            // Create wallet model
            let wallet = Wallet(
                name: "Imported Wallet",
                accounts: accounts,
                mnemonicWordCount: wordCount
            )

            // Save wallet metadata
            saveWalletMetadata(wallet)

            // Update state
            self.wallet = wallet
            self.selectedAccount = accounts.first
            self.hasWallet = true

            // Refresh balance
            await refreshBalance()
        } catch {
            self.error = .importFailed(error.localizedDescription)
            throw error
        }
    }

    /// Import wallet from private key
    func importFromPrivateKey(_ privateKeyHex: String) async throws {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            // Import account from private key
            let account = try web3Service.importFromPrivateKey(privateKeyHex)

            // Store private key (not seed)
            guard let pkData = HexUtils.decode(privateKeyHex) else {
                throw WalletError.importFailed("Invalid private key format")
            }
            try keychainService.storePrivateKey(pkData, for: account.id.uuidString)

            // Create wallet with single account
            let wallet = Wallet(
                name: "Imported Account",
                accounts: [account],
                mnemonicWordCount: 0  // No mnemonic
            )

            // Save wallet metadata
            saveWalletMetadata(wallet)

            // Update state
            self.wallet = wallet
            self.selectedAccount = account
            self.hasWallet = true

            // Refresh balance
            await refreshBalance()
        } catch {
            self.error = .importFailed(error.localizedDescription)
            throw error
        }
    }

    /// Load existing wallet from keychain
    func loadWallet() async {
        // Prevent duplicate load calls
        guard !isLoadingWallet else { return }
        isLoadingWallet = true

        isLoading = true
        error = nil

        defer {
            isLoading = false
            isLoadingWallet = false
        }

        do {
            // Retrieve seed (requires biometric auth)
            let seed = try await keychainService.retrieveSeed()

            // Load wallet metadata
            let metadata = loadWalletMetadata()

            // Derive accounts
            var accounts: [Account] = []
            let accountCount = max(metadata?.accountLabels.count ?? 1, 1)

            for index in 0..<accountCount {
                let account = try web3Service.deriveAccount(from: seed, at: index)
                accounts.append(account)
            }

            // Create wallet
            let wallet = Wallet(
                id: metadata?.walletId ?? UUID(),
                name: metadata?.name ?? "My Wallet",
                accounts: accounts,
                mnemonicWordCount: 12
            )

            // Update state
            self.wallet = wallet
            self.selectedAccount = accounts.first { $0.index == (metadata?.lastSelectedAccountIndex ?? 0) }
                ?? accounts.first

            // Restore last selected network
            if let networkId = metadata?.lastSelectedNetworkId,
               let network = Network.defaults.first(where: { $0.id == networkId }) {
                self.selectedNetwork = network
            }

            // Refresh balance
            await refreshBalance()
        } catch KeychainError.userCanceled {
            self.error = .authenticationCanceled
        } catch {
            self.error = .loadFailed(error.localizedDescription)
        }
    }

    /// Delete wallet and all associated data
    func deleteWallet() throws {
        try keychainService.deleteSeed(for: "default")
        UserDefaults.standard.removeObject(forKey: "walletMetadata")

        wallet = nil
        selectedAccount = nil
        hasWallet = false
        balance = "0"
        balanceUSD = "$0.00"
    }

    // MARK: - Account Management

    /// Add a new derived account
    func addAccount() async throws {
        guard let wallet = wallet else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let seed = try await keychainService.retrieveSeed()
            let newIndex = wallet.accounts.count
            let account = try web3Service.deriveAccount(from: seed, at: newIndex)

            var updatedWallet = wallet
            updatedWallet.addAccount(account)

            self.wallet = updatedWallet
            saveWalletMetadata(updatedWallet)
        } catch {
            self.error = .accountCreationFailed(error.localizedDescription)
            throw error
        }
    }

    /// Rename an account
    func renameAccount(_ account: Account, newLabel: String) {
        guard var wallet = wallet,
              let index = wallet.accounts.firstIndex(where: { $0.id == account.id }) else {
            return
        }

        wallet.accounts[index].label = newLabel
        self.wallet = wallet
        saveWalletMetadata(wallet)
    }

    // MARK: - Smart Account Management

    /// Upgrade an EOA account to a smart account
    func upgradeToSmartAccount(_ account: Account) async throws -> SmartAccount {
        let smartAccount = try await smartAccountViewModel.getOrCreateSmartAccount(for: account)

        // Update the account with smart account reference
        guard var wallet = wallet,
              let index = wallet.accounts.firstIndex(where: { $0.id == account.id }) else {
            throw WalletError.noWallet
        }

        wallet.accounts[index].smartAccountId = smartAccount.id
        self.wallet = wallet
        saveWalletMetadata(wallet)

        // Update selected account if needed
        if selectedAccount?.id == account.id {
            selectedAccount = wallet.accounts[index]
        }

        return smartAccount
    }

    /// Check if the current account has a smart account
    func hasSmartAccount(_ account: Account) -> Bool {
        smartAccountViewModel.hasSmartAccount(account)
    }

    /// Get the smart account for an EOA
    func getSmartAccount(for account: Account) -> SmartAccount? {
        smartAccountViewModel.getSmartAccount(for: account)
    }

    /// Check if smart accounts are supported on the current network
    var isSmartAccountSupported: Bool {
        BundlerService.isChainSupported(selectedNetwork.id)
    }

    // MARK: - Balance

    /// Refresh balance for current account
    func refreshBalance() async {
        guard let account = selectedAccount else {
            print("[Wallet] refreshBalance: no account selected")
            return
        }

        print("[Wallet] Fetching balance for \(account.address)...")

        do {
            let balanceString = try await web3Service.getFormattedBalance(for: account.address)
            print("[Wallet] Balance fetched: \(balanceString)")
            self.balance = balanceString
            updateUSDBalance()
        } catch {
            print("[Wallet] Balance fetch error: \(error)")
            self.balance = "Error"
        }
    }

    private func updateUSDBalance() {
        guard let ethBalance = Double(balance) else {
            balanceUSD = "$0.00"
            return
        }
        balanceUSD = priceService.formatUSD(priceService.ethToUSD(ethBalance))
    }

    // MARK: - Private Key Access (for signing)

    /// Get private key for signing (requires authentication)
    func getPrivateKey(for account: Account) async throws -> Data {
        let seed = try await keychainService.retrieveSeed()

        // Derive the specific account's private key
        guard let keystore = try? BIP32Keystore(
            seed: seed,
            password: "",
            prefixPath: "m/44'/60'/0'/0"
        ) else {
            throw WalletError.keyDerivationFailed
        }

        guard let address = EthereumAddress(account.address),
              let privateKey = try? keystore.UNSAFE_getPrivateKeyData(
                password: "",
                account: address
              ) else {
            throw WalletError.keyDerivationFailed
        }

        return privateKey
    }

    // MARK: - Persistence

    private func saveWalletMetadata(_ wallet: Wallet) {
        var metadata = WalletMetadata(walletId: wallet.id, name: wallet.name)

        for account in wallet.accounts {
            metadata.accountLabels[account.index] = account.label
        }

        if let account = selectedAccount {
            metadata.lastSelectedAccountIndex = account.index
        }
        metadata.lastSelectedNetworkId = selectedNetwork.id

        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: "walletMetadata")
        }
    }

    private func loadWalletMetadata() -> WalletMetadata? {
        guard let data = UserDefaults.standard.data(forKey: "walletMetadata"),
              let metadata = try? JSONDecoder().decode(WalletMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }

    private func saveLastSelectedAccount(_ account: Account) {
        guard let wallet = wallet else { return }
        saveWalletMetadata(wallet)
    }
}

// MARK: - Errors

enum WalletError: Error, LocalizedError {
    case creationFailed(String)
    case importFailed(String)
    case loadFailed(String)
    case accountCreationFailed(String)
    case keyDerivationFailed
    case authenticationCanceled
    case noWallet

    var errorDescription: String? {
        switch self {
        case .creationFailed(let reason):
            return "Failed to create wallet: \(reason)"
        case .importFailed(let reason):
            return "Failed to import wallet: \(reason)"
        case .loadFailed(let reason):
            return "Failed to load wallet: \(reason)"
        case .accountCreationFailed(let reason):
            return "Failed to create account: \(reason)"
        case .keyDerivationFailed:
            return "Failed to derive private key"
        case .authenticationCanceled:
            return "Authentication was canceled"
        case .noWallet:
            return "No wallet found"
        }
    }
}
