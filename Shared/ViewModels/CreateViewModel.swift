import Foundation
import Combine
import web3swift
import Web3Core

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
            if inscribeToSelf, let account = account {
                recipientAddress = account.address
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

    // MARK: - Dependencies

    private let web3Service: Web3Service
    private let ethscriptionService: EthscriptionService
    private let keychainService: KeychainService

    private var account: Account?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        web3Service: Web3Service = Web3Service(),
        keychainService: KeychainService = .shared
    ) {
        self.web3Service = web3Service
        self.ethscriptionService = EthscriptionService(web3Service: web3Service)
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

        if inscribeToSelf, let account = account {
            recipientAddress = account.address
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
