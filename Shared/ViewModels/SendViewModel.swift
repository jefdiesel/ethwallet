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

    // Smart account support
    @Published var useSmartAccount: Bool = false {
        didSet {
            Task { await refreshBalance() }
        }
    }
    @Published var smartAccount: SmartAccount?
    @Published var usePaymaster: Bool = false
    @Published var paymasterMode: PaymasterMode = .none
    @Published private(set) var userOperationHash: String?  // For tracking smart account tx

    // Balance display
    @Published private(set) var displayBalance: String = "0"
    @Published private(set) var isLoadingBalance: Bool = false

    // MARK: - Dependencies

    private let web3Service: Web3Service
    private let ethscriptionService: EthscriptionService
    private let keychainService: KeychainService
    private let priceService: PriceService
    private let nameService: NameService
    private let tokenService: TokenService

    // Smart account services
    private var smartAccountService: SmartAccountService?
    private var bundlerService: BundlerService?
    private var paymasterService: PaymasterService?

    private var account: Account?
    private var availableBalance: BigUInt = 0
    private var cancellables = Set<AnyCancellable>()
    private var nameResolutionTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        keychainService: KeychainService = .shared,
        priceService: PriceService = .shared,
        nameService: NameService = .shared,
        tokenService: TokenService = .shared
    ) {
        // Use the current network from NetworkManager
        let network = NetworkManager.shared.selectedNetwork
        let web3 = Web3Service()
        web3.switchNetwork(network)

        self.web3Service = web3
        self.ethscriptionService = EthscriptionService(web3Service: web3)
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
        Task { await refreshBalance() }
    }

    /// Configure smart account support
    func configureSmartAccount(smartAccount: SmartAccount?) {
        self.smartAccount = smartAccount

        if let smartAccount = smartAccount {
            let chainId = web3Service.network.id
            bundlerService = BundlerService(chainId: chainId)
            paymasterService = PaymasterService(chainId: chainId)

            if let bundler = bundlerService {
                smartAccountService = SmartAccountService(
                    web3Service: web3Service,
                    bundlerService: bundler,
                    chainId: chainId
                )
            }
        } else {
            bundlerService = nil
            paymasterService = nil
            smartAccountService = nil
            useSmartAccount = false
        }
    }

    // MARK: - Balance

    /// Refresh the balance for the current "from" address
    func refreshBalance() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }

        let address: String
        if useSmartAccount, let sa = smartAccount {
            address = sa.smartAccountAddress
        } else if let acc = account {
            address = acc.address
        } else {
            displayBalance = "0"
            availableBalance = 0
            return
        }

        do {
            let balanceString = try await web3Service.getFormattedBalance(for: address)
            displayBalance = balanceString

            // Also update availableBalance for validation
            if let balance = try? await web3Service.getBalance(for: address) {
                availableBalance = balance
            }
        } catch {
            displayBalance = "Error"
            availableBalance = 0
        }

        // Re-validate amount with new balance
        validateAmount()
    }

    /// The address funds will be sent FROM
    var fromAddress: String {
        if useSmartAccount, let sa = smartAccount {
            return sa.smartAccountAddress
        }
        return account?.address ?? ""
    }

    /// Check if smart account sending is available
    var canUseSmartAccount: Bool {
        smartAccount != nil && smartAccountService != nil
    }

    /// Check if paymaster is available
    var isPaymasterAvailable: Bool {
        paymasterService?.isAvailable ?? false
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
            resolvedAddress = recipientAddress

            // Validate checksum - only warn, don't block
            if !HexUtils.isValidChecksumAddress(recipientAddress) {
                recipientError = "Warning: Address checksum may be invalid - verify before sending"
            }

            // Check if sending to self (warning only)
            if recipientAddress.lowercased() == account?.address.lowercased() {
                recipientError = "Warning: Sending to yourself"
            }

            isValidRecipient = true
            isResolvingName = false

            // Check for security warnings asynchronously
            Task { @MainActor in
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

    @MainActor
    private func checkRecipientSecurity(_ address: String) async {
        isCheckingSecurity = true
        securityWarnings = []

        do {
            let chainId = web3Service.network.id
            let warnings = await PhishingProtectionService.shared.checkRecipient(address, chainId: chainId)
            securityWarnings = warnings
        } catch {
            // Silently ignore security check failures
        }

        isCheckingSecurity = false
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
        userOperationHash = nil

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

            // Use smart account if enabled
            if useSmartAccount, let smartAccount = smartAccount {
                return try await sendViaSmartAccount(
                    smartAccount: smartAccount,
                    to: targetAddress,
                    privateKey: privateKey
                )
            }

            // Standard EOA send
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

    // MARK: - Smart Account Send

    /// Send via smart account using ERC-4337 UserOperation
    private func sendViaSmartAccount(
        smartAccount: SmartAccount,
        to: String,
        privateKey: Data
    ) async throws -> String {
        print("[SendVM] === SMART ACCOUNT SEND ===")
        print("[SendVM] smartAccount: \(smartAccount.smartAccountAddress)")
        print("[SendVM] owner: \(smartAccount.ownerAddress)")
        print("[SendVM] to: \(to)")
        print("[SendVM] amount: \(amount)")
        print("[SendVM] usePaymaster: \(usePaymaster)")

        guard let service = smartAccountService,
              let bundler = bundlerService else {
            print("[SendVM] ERROR: Service not initialized")
            throw SendError.smartAccountServiceNotInitialized
        }

        // Build the call(s)
        var calls: [UserOperationCall] = []

        switch selectedAsset {
        case .eth:
            guard let parsedAmount = try? web3Service.parseEther(amount) else {
                throw SendError.invalidAmount
            }
            calls.append(UserOperationCall.transfer(to: to, value: parsedAmount))

        case .token:
            guard let token = selectedToken,
                  let parsedAmount = tokenService.parseTokenAmount(amount, decimals: token.decimals) else {
                throw SendError.invalidAmount
            }
            // Encode ERC-20 transfer
            let transferData = encodeERC20Transfer(to: to, amount: parsedAmount)
            calls.append(UserOperationCall.contractCall(to: token.address, data: transferData))

        case .ethscription:
            guard let ethscription = selectedEthscription else {
                throw SendError.noEthscriptionSelected
            }
            // Ethscription transfer is sending 0 ETH with ethscription ID as data
            let data = Data(hex: ethscription.id)
            calls.append(UserOperationCall(to: to, value: 0, data: data))
        }

        // Build UserOperation
        // Skip gas estimation if using paymaster (paymaster endpoint will provide gas values)
        print("[SendVM] Building UserOperation (skipEstimation: \(usePaymaster))...")
        var userOp = try await service.buildUserOperation(
            account: smartAccount,
            calls: calls,
            skipEstimation: usePaymaster
        )
        print("[SendVM] UserOperation built")

        // Apply paymaster if enabled
        if usePaymaster, let paymaster = paymasterService {
            print("[SendVM] Applying paymaster with .sponsored mode...")
            userOp = try await paymaster.buildSponsoredUserOperation(
                from: userOp,
                mode: .sponsored  // Always use sponsored when usePaymaster is true
            )
            print("[SendVM] Paymaster applied, paymasterAndData length: \(userOp.paymasterAndData.count)")
        }

        // Sign the UserOperation
        print("[SendVM] Signing...")
        userOp = try service.signUserOperation(userOp, privateKey: privateKey)
        print("[SendVM] Signed")

        // Send to bundler
        print("[SendVM] Sending to bundler...")
        let userOpHash = try await bundler.sendUserOperation(userOp)
        print("[SendVM] Success! Hash: \(userOpHash)")
        userOperationHash = userOpHash

        return userOpHash
    }

    private func encodeERC20Transfer(to: String, amount: BigUInt) -> Data {
        // transfer(address,uint256) selector: 0xa9059cbb
        var data = Data()
        data.append(Data(hex: "a9059cbb"))

        // Pad address to 32 bytes
        var toHex = to.lowercased()
        if toHex.hasPrefix("0x") {
            toHex = String(toHex.dropFirst(2))
        }
        let toPadded = String(repeating: "0", count: 64 - toHex.count) + toHex
        data.append(Data(hex: toPadded))

        // Pad amount to 32 bytes
        let amountHex = String(amount, radix: 16)
        let amountPadded = String(repeating: "0", count: 64 - amountHex.count) + amountHex
        data.append(Data(hex: amountPadded))

        return data
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
        userOperationHash = nil
        // Keep smart account settings between sends
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
    case smartAccountServiceNotInitialized
    case userOperationFailed(String)

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
        case .smartAccountServiceNotInitialized:
            return "Smart account service not initialized"
        case .userOperationFailed(let reason):
            return "UserOperation failed: \(reason)"
        }
    }
}
