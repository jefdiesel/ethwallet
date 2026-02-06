import Foundation
import Combine
import web3swift
import Web3Core
import BigInt

/// View model for sending ETH and ethscriptions
@MainActor
final class SendViewModel: ObservableObject {
    // MARK: - Published State

    @Published var recipientAddress: String = "" {
        didSet { validateRecipient() }
    }

    @Published var amount: String = "" {
        didSet { validateAmount() }
    }

    @Published var selectedAsset: SendAsset = .eth
    @Published var selectedToken: Token?
    @Published var selectedTokenBalance: TokenBalance?
    @Published var selectedEthscription: Ethscription?

    @Published private(set) var isValidRecipient: Bool = false
    @Published private(set) var isValidAmount: Bool = false
    @Published private(set) var recipientError: String?
    @Published private(set) var amountError: String?

    // Name resolution
    @Published private(set) var resolvedAddress: String?
    @Published private(set) var isResolvingName: Bool = false
    @Published private(set) var resolvedName: String?  // Display name for resolved address

    @Published private(set) var gasEstimate: GasEstimate?
    @Published private(set) var isEstimatingGas: Bool = false

    // Security warnings
    @Published private(set) var securityWarnings: [SecurityWarning] = []
    @Published private(set) var isCheckingSecurity: Bool = false

    @Published private(set) var isSending: Bool = false
    @Published private(set) var sendError: String?
    @Published private(set) var lastTransactionHash: String?

    // MARK: - Dependencies

    private let web3Service: Web3Service
    private let ethscriptionService: EthscriptionService
    private let keychainService: KeychainService
    private let priceService: PriceService
    private let nameService: NameService
    private let tokenService: TokenService

    private var account: Account?
    private var availableBalance: BigUInt = 0
    private var cancellables = Set<AnyCancellable>()
    private var nameResolutionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        web3Service: Web3Service = Web3Service(),
        keychainService: KeychainService = .shared,
        priceService: PriceService = .shared,
        nameService: NameService = .shared,
        tokenService: TokenService = .shared
    ) {
        self.web3Service = web3Service
        self.ethscriptionService = EthscriptionService(web3Service: web3Service)
        self.keychainService = keychainService
        self.priceService = priceService
        self.nameService = nameService
        self.tokenService = tokenService

        setupBindings()
    }

    private func setupBindings() {
        // Re-estimate gas when inputs change
        $recipientAddress
            .combineLatest($amount, $selectedAsset)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                Task { await self?.estimateGas() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    /// Configure the view model with an account
    func configure(account: Account, balance: BigUInt) {
        self.account = account
        self.availableBalance = balance
    }

    // MARK: - Validation

    private func validateRecipient() {
        // Cancel any pending name resolution
        nameResolutionTask?.cancel()

        recipientError = nil
        resolvedAddress = nil
        resolvedName = nil

        if recipientAddress.isEmpty {
            isValidRecipient = false
            isResolvingName = false
            return
        }

        // Check if it's a valid Ethereum address
        if HexUtils.isValidAddress(recipientAddress) {
            // Validate checksum if address has mixed case
            if !HexUtils.isValidChecksumAddress(recipientAddress) {
                recipientError = "Invalid address checksum - please verify the address"
                isValidRecipient = false
                isResolvingName = false
                return
            }

            resolvedAddress = recipientAddress

            // Check if sending to self (warning only)
            if recipientAddress.lowercased() == account?.address.lowercased() {
                recipientError = "Warning: Sending to yourself"
            }

            isValidRecipient = true
            isResolvingName = false

            // Check for security warnings asynchronously
            Task {
                await checkRecipientSecurity(recipientAddress)
            }
            return
        }

        // Check if it looks like a name to resolve
        if nameService.isEthscriptionName(recipientAddress) {
            resolvedName = recipientAddress
            isResolvingName = true
            isValidRecipient = false

            // Resolve the name asynchronously
            nameResolutionTask = Task {
                do {
                    if let address = try await nameService.resolveAddress(for: recipientAddress) {
                        await MainActor.run {
                            self.resolvedAddress = address
                            self.isValidRecipient = true
                            self.isResolvingName = false
                            self.recipientError = nil

                            // Check if sending to self
                            if address.lowercased() == self.account?.address.lowercased() {
                                self.recipientError = "Warning: Sending to yourself"
                            }
                        }

                        // Check for security warnings
                        await self.checkRecipientSecurity(address)
                    } else {
                        await MainActor.run {
                            self.recipientError = "Name not found"
                            self.isValidRecipient = false
                            self.isResolvingName = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.recipientError = "Failed to resolve name"
                        self.isValidRecipient = false
                        self.isResolvingName = false
                    }
                }
            }
            return
        }

        // Not a valid address or name
        recipientError = "Invalid address or name"
        isValidRecipient = false
        isResolvingName = false
    }

    private func validateAmount() {
        amountError = nil

        if amount.isEmpty {
            isValidAmount = selectedAsset == .ethscription  // No amount needed for ethscription transfer
            return
        }

        switch selectedAsset {
        case .eth:
            // Parse amount
            guard let parsedAmount = try? web3Service.parseEther(amount) else {
                amountError = "Invalid amount format"
                isValidAmount = false
                return
            }

            // Check if amount is positive
            if parsedAmount == 0 {
                amountError = "Amount must be greater than 0"
                isValidAmount = false
                return
            }

            // Check if sufficient balance (with gas buffer)
            let estimatedGas = gasEstimate?.estimatedCost ?? 0
            if parsedAmount + BigUInt(estimatedGas) > availableBalance {
                amountError = "Insufficient balance"
                isValidAmount = false
                return
            }

            isValidAmount = true

        case .token:
            guard let token = selectedToken,
                  let balance = selectedTokenBalance else {
                amountError = "Select a token"
                isValidAmount = false
                return
            }

            guard let parsedAmount = tokenService.parseTokenAmount(amount, decimals: token.decimals) else {
                amountError = "Invalid amount format"
                isValidAmount = false
                return
            }

            if parsedAmount == 0 {
                amountError = "Amount must be greater than 0"
                isValidAmount = false
                return
            }

            // Check token balance
            if let rawBalance = BigUInt(balance.rawBalance), parsedAmount > rawBalance {
                amountError = "Insufficient \(token.symbol) balance"
                isValidAmount = false
                return
            }

            isValidAmount = true

        case .ethscription:
            isValidAmount = true
        }
    }

    // MARK: - Security Check

    private func checkRecipientSecurity(_ address: String) async {
        await MainActor.run {
            self.isCheckingSecurity = true
            self.securityWarnings = []
        }

        let chainId = web3Service.network.id
        let warnings = await PhishingProtectionService.shared.checkRecipient(address, chainId: chainId)

        await MainActor.run {
            self.securityWarnings = warnings
            self.isCheckingSecurity = false
        }
    }

    // MARK: - Gas Estimation

    func estimateGas() async {
        guard isValidRecipient, let account = account else {
            gasEstimate = nil
            return
        }

        isEstimatingGas = true
        defer { isEstimatingGas = false }

        do {
            switch selectedAsset {
            case .eth:
                guard let parsedAmount = try? web3Service.parseEther(amount) else { return }

                let request = TransactionRequest(
                    from: account.address,
                    to: recipientAddress,
                    value: parsedAmount,
                    chainId: web3Service.network.id
                )

                let gasLimit = try await web3Service.estimateGas(for: request)
                let gasPrice = try await web3Service.getGasPrice()

                gasEstimate = GasEstimate(
                    gasLimit: gasLimit,
                    maxFeePerGas: gasPrice,
                    maxPriorityFeePerGas: gasPrice / 10,
                    estimatedCost: gasLimit * gasPrice
                )

            case .token:
                guard let token = selectedToken,
                      let parsedAmount = tokenService.parseTokenAmount(amount, decimals: token.decimals),
                      let targetAddress = resolvedAddress else { return }

                gasEstimate = try await tokenService.estimateTransferGas(
                    token: token,
                    to: targetAddress,
                    amount: parsedAmount,
                    from: account.address
                )

            case .ethscription:
                guard let ethscription = selectedEthscription else { return }

                gasEstimate = try await ethscriptionService.estimateTransferGas(
                    ethscriptionId: ethscription.id,
                    to: recipientAddress,
                    from: account.address
                )
            }

            // Re-validate amount with new gas estimate
            validateAmount()
        } catch {
            gasEstimate = nil
        }
    }

    // MARK: - Send Operations

    /// Check if send is ready
    var canSend: Bool {
        switch selectedAsset {
        case .eth:
            return isValidRecipient && isValidAmount && !isSending
        case .token:
            return isValidRecipient && isValidAmount && selectedToken != nil && !isSending
        case .ethscription:
            return isValidRecipient && selectedEthscription != nil && !isSending
        }
    }

    /// Send ETH or ethscription
    func send() async throws -> String {
        guard canSend, let account = account else {
            throw SendError.notReady
        }

        isSending = true
        sendError = nil
        lastTransactionHash = nil

        defer { isSending = false }

        do {
            // Get private key (requires biometric auth)
            let seed = try await keychainService.retrieveSeed()

            guard let keystore = try? BIP32Keystore(
                seed: seed,
                password: "",
                prefixPath: "m/44'/60'/0'/0"
            ) else {
                throw SendError.keyDerivationFailed
            }

            guard let address = EthereumAddress(account.address),
                  let privateKey = try? keystore.UNSAFE_getPrivateKeyData(
                    password: "",
                    account: address
                  ) else {
                throw SendError.keyDerivationFailed
            }

            // Use resolved address (from name resolution) or the direct address
            guard let targetAddress = resolvedAddress else {
                throw SendError.notReady
            }

            let txHash: String

            switch selectedAsset {
            case .eth:
                guard let parsedAmount = try? web3Service.parseEther(amount) else {
                    throw SendError.invalidAmount
                }

                txHash = try await web3Service.sendETH(
                    from: account.address,
                    to: targetAddress,
                    amount: BigUInt(parsedAmount),
                    privateKey: privateKey
                )

            case .token:
                guard let token = selectedToken,
                      let parsedAmount = tokenService.parseTokenAmount(amount, decimals: token.decimals) else {
                    throw SendError.invalidAmount
                }

                txHash = try await tokenService.transfer(
                    token: token,
                    to: targetAddress,
                    amount: parsedAmount,
                    from: account.address,
                    privateKey: privateKey
                )

            case .ethscription:
                guard let ethscription = selectedEthscription else {
                    throw SendError.noEthscriptionSelected
                }

                txHash = try await ethscriptionService.transferEthscription(
                    ethscriptionId: ethscription.id,
                    to: targetAddress,
                    from: account.address,
                    privateKey: privateKey
                )
            }

            lastTransactionHash = txHash
            return txHash
        } catch {
            sendError = error.localizedDescription
            throw error
        }
    }

    /// Set to max amount (ETH and token)
    func setMaxAmount() {
        switch selectedAsset {
        case .eth:
            // Calculate max = balance - estimated gas
            let gasBuffer = gasEstimate?.estimatedCost ?? 21000 * 20_000_000_000  // Default: 21000 gas * 20 gwei
            let maxWei = availableBalance > BigUInt(gasBuffer) ? availableBalance - BigUInt(gasBuffer) : 0
            amount = web3Service.formatWei(maxWei)

        case .token:
            guard let balance = selectedTokenBalance else { return }
            amount = balance.formattedBalance

        case .ethscription:
            break // No amount for ethscription
        }
    }

    /// Reset form
    func reset() {
        recipientAddress = ""
        amount = ""
        selectedToken = nil
        selectedTokenBalance = nil
        selectedEthscription = nil
        gasEstimate = nil
        sendError = nil
        lastTransactionHash = nil
        securityWarnings = []
    }

    // MARK: - Display Helpers

    /// Get USD value of amount
    var amountUSD: String {
        guard selectedAsset == .eth,
              let ethAmount = Double(amount) else {
            return "$0.00"
        }
        return priceService.formatUSD(priceService.ethToUSD(ethAmount))
    }

    /// Get estimated gas in ETH
    var estimatedGasETH: String {
        guard let estimate = gasEstimate else { return "..." }
        return estimate.formattedCost
    }
}

// MARK: - Send Asset Type

enum SendAsset: String, CaseIterable, Identifiable {
    case eth = "ETH"
    case token = "Token"
    case ethscription = "Ethscription"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eth: return "ETH"
        case .token: return "Token"
        case .ethscription: return "Ethscription"
        }
    }
}

// MARK: - Errors

enum SendError: Error, LocalizedError {
    case notReady
    case invalidAmount
    case keyDerivationFailed
    case noEthscriptionSelected
    case transactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Transaction is not ready to send"
        case .invalidAmount:
            return "Invalid amount"
        case .keyDerivationFailed:
            return "Failed to access private key"
        case .noEthscriptionSelected:
            return "No ethscription selected"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        }
    }
}
