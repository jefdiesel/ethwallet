import Foundation
import Combine
import web3swift
import Web3Core
import BigInt

/// View model for managing multiple accounts
@MainActor
final class AccountsViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccount: Account?
    @Published private(set) var balances: [String: String] = [:]  // address -> balance
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    // MARK: - Services

    private let keychainService: KeychainService
    private let web3Service: Web3Service
    private let networkManager: NetworkManager

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        keychainService: KeychainService = .shared,
        web3Service: Web3Service = Web3Service(),
        networkManager: NetworkManager = .shared
    ) {
        self.keychainService = keychainService
        self.web3Service = web3Service
        self.networkManager = networkManager

        setupBindings()
    }

    private func setupBindings() {
        // Refresh balances when network changes
        NotificationCenter.default.publisher(for: .networkDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refreshAllBalances() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Account Loading

    /// Load accounts from wallet
    func loadAccounts(from wallet: Wallet) {
        accounts = wallet.accounts
        if selectedAccount == nil {
            selectedAccount = accounts.first
        }
        Task { await refreshAllBalances() }
    }

    /// Refresh all account balances
    func refreshAllBalances() async {
        isLoading = true
        defer { isLoading = false }

        var newBalances: [String: String] = [:]

        for account in accounts {
            do {
                let balance = try await web3Service.getFormattedBalance(for: account.address)
                newBalances[account.address] = balance
            } catch {
                newBalances[account.address] = "Error"
            }
        }

        self.balances = newBalances
    }

    /// Get balance for a specific account
    func balance(for account: Account) -> String {
        balances[account.address] ?? "0"
    }

    // MARK: - Account Management

    /// Add a new derived account
    func addAccount() async throws -> Account {
        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            let seed = try await keychainService.retrieveSeed()
            let newIndex = accounts.count
            let account = try web3Service.deriveAccount(from: seed, at: newIndex)

            accounts.append(account)

            // Fetch balance for new account
            do {
                let balance = try await web3Service.getFormattedBalance(for: account.address)
                balances[account.address] = balance
            } catch {
                balances[account.address] = "0"
            }

            return account
        } catch {
            self.error = error.localizedDescription
            throw error
        }
    }

    /// Rename an account
    func renameAccount(_ account: Account, to newLabel: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].label = newLabel

        // Update selected account if it was renamed
        if selectedAccount?.id == account.id {
            selectedAccount = accounts[index]
        }
    }

    /// Select an account
    func selectAccount(_ account: Account) {
        selectedAccount = account
    }

    // MARK: - Account Details

    /// Get short address for display
    func shortAddress(for account: Account) -> String {
        account.shortAddress
    }

    /// Get derivation path for account
    func derivationPath(for account: Account) -> String {
        account.derivationPath
    }

    /// Get account at specific index
    func account(at index: Int) -> Account? {
        accounts.first { $0.index == index }
    }

    // MARK: - Total Balance

    /// Get total balance across all accounts
    var totalBalance: String {
        var total: Double = 0

        for balance in balances.values {
            if let value = Double(balance) {
                total += value
            }
        }

        return String(format: "%.6f", total)
    }

    /// Check if any account has balance
    var hasAnyBalance: Bool {
        balances.values.contains { balance in
            if let value = Double(balance) {
                return value > 0
            }
            return false
        }
    }
}

// MARK: - Account List Item

struct AccountListItem: Identifiable {
    let account: Account
    let balance: String
    let isSelected: Bool

    var id: UUID { account.id }
}

extension AccountsViewModel {
    /// Get accounts as list items for display
    var accountListItems: [AccountListItem] {
        accounts.map { account in
            AccountListItem(
                account: account,
                balance: balance(for: account),
                isSelected: account.id == selectedAccount?.id
            )
        }
    }
}
