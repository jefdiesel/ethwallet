import Foundation
import Combine
import BigInt

/// View model for ERC-4337 smart account management
@MainActor
final class SmartAccountViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var smartAccounts: [SmartAccount] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: SmartAccountViewError?

    @Published private(set) var isCreating: Bool = false
    @Published private(set) var isDeploying: Bool = false
    @Published private(set) var deploymentProgress: String = ""

    @Published var selectedSmartAccount: SmartAccount?
    @Published private(set) var smartAccountBalance: String = "0"
    @Published private(set) var smartAccountBalanceUSD: String = "$0.00"

    // Paymaster state
    @Published var usePaymaster: Bool = false
    @Published var paymasterMode: PaymasterMode = .none
    @Published private(set) var isPaymasterAvailable: Bool = false

    // Pending operations
    @Published private(set) var pendingOperations: [PendingUserOperation] = []

    // MARK: - Services

    private var smartAccountService: SmartAccountService?
    private var paymasterService: PaymasterService?
    private var web3Service: Web3Service
    private var bundlerService: BundlerService?
    private let keychainService: KeychainService
    private let priceService: PriceService

    private var currentChainId: Int = 1
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        web3Service: Web3Service = Web3Service(),
        keychainService: KeychainService = .shared,
        priceService: PriceService = .shared
    ) {
        self.web3Service = web3Service
        self.keychainService = keychainService
        self.priceService = priceService

        setupServices()
        loadStoredSmartAccounts()
        setupBindings()
    }

    private func setupServices() {
        currentChainId = web3Service.network.id
        bundlerService = BundlerService(chainId: currentChainId)
        paymasterService = PaymasterService(chainId: currentChainId)

        if let bundler = bundlerService {
            smartAccountService = SmartAccountService(
                web3Service: web3Service,
                bundlerService: bundler,
                chainId: currentChainId
            )
        }

        isPaymasterAvailable = paymasterService?.isAvailable ?? false
    }

    private func setupBindings() {
        priceService.$ethPrice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUSDBalance()
            }
            .store(in: &cancellables)
    }

    // MARK: - Network Switching

    func switchNetwork(_ network: Network) {
        currentChainId = network.id
        web3Service.switchNetwork(network)

        bundlerService?.switchChain(network.id)
        paymasterService?.switchChain(network.id)
        smartAccountService?.switchChain(network.id)

        // Filter smart accounts for current chain
        loadStoredSmartAccounts()

        // Check paymaster availability
        isPaymasterAvailable = paymasterService?.isAvailable ?? false

        // Refresh balance for selected account
        if selectedSmartAccount != nil {
            Task { await refreshSmartAccountBalance() }
        }
    }

    // MARK: - Smart Account Creation

    /// Create a new smart account for an EOA
    func createSmartAccount(for account: Account) async throws -> SmartAccount {
        guard let service = smartAccountService else {
            throw SmartAccountViewError.serviceNotInitialized
        }

        isCreating = true
        error = nil

        defer { isCreating = false }

        do {
            // Use account index as salt for determinism
            let salt = BigUInt(account.index)

            let smartAccount = try await service.createSmartAccount(
                owner: account.address,
                salt: salt
            )

            // Save to storage
            var accounts = smartAccounts
            accounts.append(smartAccount)
            smartAccounts = accounts
            saveSmartAccounts()

            // Select the new account
            selectedSmartAccount = smartAccount

            return smartAccount
        } catch {
            self.error = .creationFailed(error.localizedDescription)
            throw error
        }
    }

    /// Get or create smart account for an EOA
    func getOrCreateSmartAccount(for account: Account) async throws -> SmartAccount {
        // Check if smart account already exists for this owner
        if let existing = smartAccounts.first(where: {
            $0.ownerAddress.lowercased() == account.address.lowercased() &&
            $0.chainId == currentChainId
        }) {
            selectedSmartAccount = existing
            return existing
        }

        // Create new one
        return try await createSmartAccount(for: account)
    }

    // MARK: - Deployment

    /// Deploy a smart account (explicit deployment, usually happens automatically on first tx)
    func deploySmartAccount(
        _ smartAccount: SmartAccount,
        privateKey: Data
    ) async throws {
        guard let service = smartAccountService else {
            throw SmartAccountViewError.serviceNotInitialized
        }

        guard !smartAccount.isDeployed else {
            throw SmartAccountViewError.alreadyDeployed
        }

        isDeploying = true
        deploymentProgress = "Preparing deployment..."
        error = nil

        defer {
            isDeploying = false
            deploymentProgress = ""
        }

        do {
            // Build a minimal UserOp that just deploys the account
            // We send 0 ETH to the account itself
            let call = UserOperationCall(to: smartAccount.smartAccountAddress, value: 0)

            deploymentProgress = "Building transaction..."

            var userOp = try await service.buildUserOperation(
                account: smartAccount,
                calls: [call]
            )

            // Apply paymaster if enabled
            if usePaymaster, let paymaster = paymasterService {
                deploymentProgress = "Getting sponsorship..."
                userOp = try await paymaster.buildSponsoredUserOperation(
                    from: userOp,
                    mode: paymasterMode
                )
            }

            deploymentProgress = "Signing..."

            // Sign the UserOp
            userOp = try service.signUserOperation(userOp, privateKey: privateKey)

            deploymentProgress = "Submitting..."

            // Send to bundler
            let userOpHash = try await bundlerService?.sendUserOperation(userOp)
            guard let hash = userOpHash else {
                throw SmartAccountViewError.deploymentFailed("Failed to submit operation")
            }

            // Track pending operation
            let pendingOp = PendingUserOperation(
                hash: hash,
                smartAccount: smartAccount,
                type: .deployment,
                submittedAt: Date()
            )
            pendingOperations.append(pendingOp)

            deploymentProgress = "Waiting for confirmation..."

            // Wait for receipt
            let receipt = try await bundlerService?.waitForReceipt(hash, timeout: 120)

            // Update deployment status
            if receipt?.success == true {
                updateDeploymentStatus(for: smartAccount, isDeployed: true)
            } else {
                throw SmartAccountViewError.deploymentFailed(receipt?.reason ?? "Unknown error")
            }

            // Remove from pending
            pendingOperations.removeAll { $0.hash == hash }
        } catch {
            self.error = .deploymentFailed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Balance

    func refreshSmartAccountBalance() async {
        guard let smartAccount = selectedSmartAccount else { return }

        do {
            let balance = try await web3Service.getFormattedBalance(for: smartAccount.smartAccountAddress)
            smartAccountBalance = balance
            updateUSDBalance()
        } catch {
            smartAccountBalance = "Error"
        }
    }

    private func updateUSDBalance() {
        guard let ethBalance = Double(smartAccountBalance) else {
            smartAccountBalanceUSD = "$0.00"
            return
        }
        smartAccountBalanceUSD = priceService.formatUSD(priceService.ethToUSD(ethBalance))
    }

    // MARK: - Deployment Status

    func refreshDeploymentStatus() async {
        guard let service = smartAccountService else { return }

        isLoading = true
        defer { isLoading = false }

        for (index, smartAccount) in smartAccounts.enumerated() {
            guard smartAccount.chainId == currentChainId else { continue }

            do {
                let isDeployed = try await service.isDeployed(address: smartAccount.smartAccountAddress)
                if isDeployed != smartAccount.isDeployed {
                    smartAccounts[index].isDeployed = isDeployed
                }
            } catch {
                // Ignore errors, keep previous status
            }
        }

        saveSmartAccounts()
    }

    private func updateDeploymentStatus(for smartAccount: SmartAccount, isDeployed: Bool) {
        guard let index = smartAccounts.firstIndex(where: { $0.id == smartAccount.id }) else {
            return
        }

        smartAccounts[index].isDeployed = isDeployed

        if selectedSmartAccount?.id == smartAccount.id {
            selectedSmartAccount = smartAccounts[index]
        }

        saveSmartAccounts()
    }

    // MARK: - Pending Operations

    func refreshPendingOperations() async {
        guard let bundler = bundlerService else { return }

        for (index, operation) in pendingOperations.enumerated() {
            do {
                let status = try await bundler.getUserOperationStatus(operation.hash)
                pendingOperations[index].status = status.status

                if status.status.isFinished {
                    // Update smart account deployment status if needed
                    if operation.type == .deployment && status.status.isSuccess {
                        updateDeploymentStatus(for: operation.smartAccount, isDeployed: true)
                    }
                }
            } catch {
                // Keep current status
            }
        }

        // Remove old completed operations
        pendingOperations.removeAll { $0.status.isFinished && $0.submittedAt.timeIntervalSinceNow < -60 }
    }

    // MARK: - Storage

    private func loadStoredSmartAccounts() {
        if let data = UserDefaults.standard.data(forKey: "smartAccounts"),
           let accounts = try? JSONDecoder().decode([SmartAccount].self, from: data) {
            self.smartAccounts = accounts.filter { $0.chainId == currentChainId }
        }
    }

    private func saveSmartAccounts() {
        // Load all accounts (including other chains)
        var allAccounts: [SmartAccount] = []
        if let data = UserDefaults.standard.data(forKey: "smartAccounts"),
           let stored = try? JSONDecoder().decode([SmartAccount].self, from: data) {
            allAccounts = stored.filter { $0.chainId != currentChainId }
        }

        // Add current chain accounts
        allAccounts.append(contentsOf: smartAccounts)

        // Save
        if let data = try? JSONEncoder().encode(allAccounts) {
            UserDefaults.standard.set(data, forKey: "smartAccounts")
        }
    }

    // MARK: - Helpers

    /// Get smart account for a specific EOA on current chain
    func getSmartAccount(for account: Account) -> SmartAccount? {
        smartAccounts.first {
            $0.ownerAddress.lowercased() == account.address.lowercased() &&
            $0.chainId == currentChainId
        }
    }

    /// Check if an account has a smart account on current chain
    func hasSmartAccount(_ account: Account) -> Bool {
        getSmartAccount(for: account) != nil
    }

    /// Check if bundler is available for current chain
    var isBundlerAvailable: Bool {
        BundlerService.isChainSupported(currentChainId) && (bundlerService?.hasAPIKey ?? false)
    }

    /// Features available for the current smart account
    var availableFeatures: [SmartAccountFeature] {
        SmartAccountFeature.allCases.filter { $0.isAvailable }
    }
}

// MARK: - Pending Operation

struct PendingUserOperation: Identifiable {
    let id = UUID()
    let hash: String
    let smartAccount: SmartAccount
    let type: OperationType
    let submittedAt: Date
    var status: UserOperationStatus = .pending

    enum OperationType {
        case deployment
        case transfer
        case batch
        case contractCall
    }

    var displayType: String {
        switch type {
        case .deployment: return "Deployment"
        case .transfer: return "Transfer"
        case .batch: return "Batch"
        case .contractCall: return "Contract Call"
        }
    }
}

// MARK: - Errors

enum SmartAccountViewError: Error, LocalizedError {
    case serviceNotInitialized
    case creationFailed(String)
    case deploymentFailed(String)
    case alreadyDeployed
    case chainNotSupported
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .serviceNotInitialized:
            return "Smart account service not initialized"
        case .creationFailed(let reason):
            return "Failed to create smart account: \(reason)"
        case .deploymentFailed(let reason):
            return "Deployment failed: \(reason)"
        case .alreadyDeployed:
            return "Smart account is already deployed"
        case .chainNotSupported:
            return "Smart accounts are not supported on this chain"
        case .noAPIKey:
            return "Pimlico API key not configured. Add it in Settings."
        }
    }
}

// MARK: - API Key Management

extension SmartAccountViewModel {
    /// Set the Pimlico API key
    func setPimlicoAPIKey(_ key: String) throws {
        try keychainService.storeAPIKey(key, for: "pimlico")

        // Reinitialize services
        setupServices()
    }

    /// Check if Pimlico API key is set
    var hasPimlicoAPIKey: Bool {
        keychainService.retrieveAPIKey(for: "pimlico") != nil
    }

    /// Get masked API key for display
    var maskedAPIKey: String? {
        guard let key = keychainService.retrieveAPIKey(for: "pimlico") else {
            return nil
        }
        if key.count > 8 {
            return String(key.prefix(4)) + "..." + String(key.suffix(4))
        }
        return "****"
    }
}
