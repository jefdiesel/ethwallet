import Foundation
import Combine
import web3swift
import Web3Core
import BigInt

/// View model for creating ethscriptions
@MainActor
final class CreateViewModel: ObservableObject {
    // MARK: - Published State

    @Published var contentType: ContentInputType = .text
    @Published var textContent: String = "" {
        didSet { validateContent() }
    }
    @Published var selectedFileURL: URL? {
        didSet { loadFileContent() }
    }

    @Published var recipientAddress: String = "" {
        didSet { validateRecipient() }
    }
    @Published var inscribeToSelf: Bool = true {
        didSet {
            if inscribeToSelf {
                recipientAddress = currentFromAddress
            }
        }
    }

    @Published var allowDuplicate: Bool = false  // ESIP-6
    @Published var useCompression: Bool = false   // ESIP-7
    @Published var useRawMode: Bool = false       // Raw calldata (no data URI wrapping)

    @Published private(set) var fileContent: Data?
    @Published private(set) var fileMimeType: String = "application/octet-stream"

    @Published private(set) var isValidContent: Bool = false
    @Published private(set) var isValidRecipient: Bool = false
    @Published private(set) var contentError: String?
    @Published private(set) var recipientError: String?

    @Published private(set) var validationResult: ContentValidationResult?
    @Published private(set) var gasEstimate: GasEstimate?
    @Published private(set) var isEstimatingGas: Bool = false

    @Published private(set) var isCreating: Bool = false
    @Published private(set) var createError: String?
    @Published private(set) var lastTransactionHash: String?

    // Smart account support
    @Published var useSmartAccount: Bool = false {
        didSet {
            if inscribeToSelf {
                recipientAddress = currentFromAddress
            }
            Task { await refreshBalance() }
        }
    }
    @Published var smartAccount: SmartAccount?
    @Published var usePaymaster: Bool = false
    @Published private(set) var userOperationHash: String?

    // Balance display
    @Published private(set) var displayBalance: String = "0"
    @Published private(set) var isLoadingBalance: Bool = false

    // MARK: - Dependencies

    private let web3Service: Web3Service
    private let ethscriptionService: EthscriptionService
    private let keychainService: KeychainService

    // Smart account services
    private var smartAccountService: SmartAccountService?
    private var bundlerService: BundlerService?
    private var paymasterService: PaymasterService?

    private var account: Account?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        keychainService: KeychainService = .shared
    ) {
        // Use the current network from NetworkManager
        let network = NetworkManager.shared.selectedNetwork
        let web3 = Web3Service()
        web3.switchNetwork(network)

        self.web3Service = web3
        self.ethscriptionService = EthscriptionService(web3Service: web3)
        self.keychainService = keychainService

        setupBindings()
    }

    private func setupBindings() {
        // Re-estimate gas when inputs change
        $textContent
            .combineLatest($fileContent, $allowDuplicate, $useCompression)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _, _ in
                Task { await self?.estimateGas() }
            }
            .store(in: &cancellables)

        // Also re-estimate when raw mode changes
        $useRawMode
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.validateContent()
                Task { await self?.estimateGas() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    /// Configure the view model with an account
    func configure(account: Account) {
        self.account = account
        if inscribeToSelf {
            recipientAddress = account.address
        }
        validateRecipient()
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

    /// Check if smart account is available
    var canUseSmartAccount: Bool {
        smartAccount != nil && smartAccountService != nil
    }

    /// Check if paymaster is available
    var isPaymasterAvailable: Bool {
        paymasterService?.isAvailable ?? false
    }

    /// The address that will be used as "from"
    var currentFromAddress: String {
        if useSmartAccount, let sa = smartAccount {
            return sa.smartAccountAddress
        }
        return account?.address ?? ""
    }

    // MARK: - Balance

    func refreshBalance() async {
        isLoadingBalance = true
        defer { isLoadingBalance = false }

        let address = currentFromAddress
        guard !address.isEmpty else {
            displayBalance = "0"
            return
        }

        do {
            displayBalance = try await web3Service.getFormattedBalance(for: address)
        } catch {
            displayBalance = "Error"
        }
    }

    // MARK: - Validation

    private func validateContent() {
        contentError = nil
        validationResult = nil

        let content: Data
        let mimeType: String

        switch contentType {
        case .text:
            guard !textContent.isEmpty else {
                isValidContent = false
                return
            }
            guard let data = textContent.data(using: .utf8) else {
                contentError = "Failed to encode text"
                isValidContent = false
                return
            }
            content = data
            mimeType = "text/plain"

        case .file:
            guard let data = fileContent else {
                isValidContent = false
                return
            }
            content = data
            mimeType = fileMimeType
        }

        // Validate using service
        let result = ethscriptionService.validateContent(content, mimeType: mimeType)
        validationResult = result

        if !result.isValid {
            contentError = result.errors.first
            isValidContent = false
            return
        }

        if !result.warnings.isEmpty {
            // Show warnings but allow creation
            contentError = result.warnings.first
        }

        isValidContent = true
    }

    private func validateRecipient() {
        recipientError = nil

        if recipientAddress.isEmpty {
            isValidRecipient = false
            return
        }

        if !HexUtils.isValidAddress(recipientAddress) {
            recipientError = "Invalid Ethereum address"
            isValidRecipient = false
            return
        }

        isValidRecipient = true
    }

    private func loadFileContent() {
        guard let url = selectedFileURL else {
            fileContent = nil
            return
        }

        do {
            fileContent = try Data(contentsOf: url)
            fileMimeType = mimeTypeForExtension(url.pathExtension)
            validateContent()
        } catch {
            contentError = "Failed to read file: \(error.localizedDescription)"
            fileContent = nil
            isValidContent = false
        }
    }

    // MARK: - Gas Estimation

    func estimateGas() async {
        guard isValidContent, isValidRecipient, let account = account else {
            gasEstimate = nil
            return
        }

        isEstimatingGas = true
        defer { isEstimatingGas = false }

        do {
            let (content, mimeType) = getCurrentContent()

            if useRawMode && contentType == .text {
                // Raw mode: estimate gas for raw calldata
                gasEstimate = try await ethscriptionService.estimateRawCreateGas(
                    rawCalldata: content,
                    recipient: recipientAddress,
                    from: account.address
                )
            } else {
                gasEstimate = try await ethscriptionService.estimateCreateGas(
                    content: content,
                    mimeType: mimeType,
                    recipient: recipientAddress,
                    allowDuplicate: allowDuplicate,
                    compress: useCompression,
                    from: account.address
                )
            }
        } catch {
            gasEstimate = nil
        }
    }

    // MARK: - Create Operation

    /// Check if creation is ready
    var canCreate: Bool {
        isValidContent && isValidRecipient && !isCreating
    }

    /// Create the ethscription
    func create() async throws -> String {
        guard canCreate, let account = account else {
            throw CreateError.notReady
        }

        isCreating = true
        createError = nil
        lastTransactionHash = nil
        userOperationHash = nil

        defer { isCreating = false }

        do {
            // Get private key (requires biometric auth)
            let seed = try await keychainService.retrieveSeed()

            guard let keystore = try? BIP32Keystore(
                seed: seed,
                password: "",
                prefixPath: "m/44'/60'/0'/0"
            ) else {
                throw CreateError.keyDerivationFailed
            }

            guard let address = EthereumAddress(account.address),
                  let privateKey = try? keystore.UNSAFE_getPrivateKeyData(
                    password: "",
                    account: address
                  ) else {
                throw CreateError.keyDerivationFailed
            }

            let (content, mimeType) = getCurrentContent()

            // Use smart account if enabled
            if useSmartAccount, let smartAccount = smartAccount, let smartAccountService = smartAccountService {
                return try await createViaSmartAccount(
                    content: content,
                    mimeType: mimeType,
                    smartAccount: smartAccount,
                    smartAccountService: smartAccountService,
                    privateKey: privateKey
                )
            }

            // Regular EOA transaction
            let txHash: String
            if useRawMode && contentType == .text {
                // Raw mode: send text directly as calldata without data URI encoding
                txHash = try await ethscriptionService.createRawEthscription(
                    rawCalldata: content,
                    recipient: recipientAddress,
                    from: account.address,
                    privateKey: privateKey
                )
            } else {
                txHash = try await ethscriptionService.createEthscription(
                    content: content,
                    mimeType: mimeType,
                    recipient: recipientAddress,
                    allowDuplicate: allowDuplicate,
                    compress: useCompression,
                    from: account.address,
                    privateKey: privateKey
                )
            }

            lastTransactionHash = txHash
            return txHash
        } catch {
            createError = error.localizedDescription
            throw error
        }
    }

    /// Create ethscription via smart account
    private func createViaSmartAccount(
        content: Data,
        mimeType: String,
        smartAccount: SmartAccount,
        smartAccountService: SmartAccountService,
        privateKey: Data
    ) async throws -> String {
        guard let bundler = bundlerService else {
            throw CreateError.transactionFailed("Bundler service not initialized")
        }

        // Build the calldata for the inscription
        let calldata: Data
        if useRawMode && contentType == .text {
            calldata = content
        } else {
            calldata = ethscriptionService.buildEthscriptionCalldata(
                content: content,
                mimeType: mimeType,
                allowDuplicate: allowDuplicate,
                compress: useCompression
            )
        }

        // Create UserOperation call
        let call = UserOperationCall(
            to: recipientAddress,
            value: 0,
            data: calldata
        )

        // Build UserOperation
        var userOp = try await smartAccountService.buildUserOperation(
            account: smartAccount,
            calls: [call]
        )

        // Apply paymaster if enabled
        if usePaymaster, let paymaster = paymasterService {
            userOp = try await paymaster.buildSponsoredUserOperation(
                from: userOp,
                mode: .sponsored
            )
        }

        // Sign the UserOperation
        userOp = try smartAccountService.signUserOperation(userOp, privateKey: privateKey)

        // Send to bundler
        let userOpHash = try await bundler.sendUserOperation(userOp)

        userOperationHash = userOpHash
        lastTransactionHash = userOpHash
        return userOpHash
    }

    /// Reset form
    func reset() {
        textContent = ""
        selectedFileURL = nil
        fileContent = nil
        allowDuplicate = false
        useCompression = false
        useRawMode = false
        gasEstimate = nil
        createError = nil
        lastTransactionHash = nil
        userOperationHash = nil

        if inscribeToSelf {
            recipientAddress = currentFromAddress
        }
    }

    // MARK: - Helpers

    private func getCurrentContent() -> (Data, String) {
        switch contentType {
        case .text:
            let data = textContent.data(using: .utf8) ?? Data()
            return (data, "text/plain")
        case .file:
            return (fileContent ?? Data(), fileMimeType)
        }
    }

    private func mimeTypeForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "json": return "application/json"
        default: return "application/octet-stream"
        }
    }

    // MARK: - Display Helpers

    /// Current content size in bytes
    var contentSize: Int {
        switch contentType {
        case .text:
            return textContent.data(using: .utf8)?.count ?? 0
        case .file:
            return fileContent?.count ?? 0
        }
    }

    /// Formatted content size
    var formattedContentSize: String {
        let bytes = contentSize
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
    }

    /// Is content size within limits
    var isWithinSizeLimit: Bool {
        contentSize <= EthscriptionService.maxContentSize
    }

    /// Estimated gas in ETH
    var estimatedGasETH: String {
        guard let estimate = gasEstimate else { return "..." }
        return estimate.formattedCost
    }
}

// MARK: - Content Input Type

enum ContentInputType: String, CaseIterable, Identifiable {
    case text = "Text"
    case file = "File"

    var id: String { rawValue }
}

// MARK: - Errors

enum CreateError: Error, LocalizedError {
    case notReady
    case keyDerivationFailed
    case encodingFailed
    case transactionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Ethscription is not ready to create"
        case .keyDerivationFailed:
            return "Failed to access private key"
        case .encodingFailed:
            return "Failed to encode content"
        case .transactionFailed(let reason):
            return "Transaction failed: \(reason)"
        }
    }
}
