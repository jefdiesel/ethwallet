import Foundation
import Combine
import Web3Wallet
import web3swift
import Web3Core

/// Service for WalletConnect v2 dApp connections
@MainActor
final class WalletConnectService: ObservableObject {
    static let shared = WalletConnectService()

    // MARK: - Published State

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var pendingProposal: Session.Proposal?
    @Published private(set) var pendingRequest: Request?
    @Published private(set) var isConnecting = false
    @Published var error: String?

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var isConfigured = false

    // WalletConnect Project ID
    private let projectId = "c10f1058133aeedd0549f82a1209c62c"

    private init() {}

    // MARK: - Setup

    func configure() {
        guard !isConfigured else {
            print("[WC] Already configured, skipping")
            return
        }
        isConfigured = true
        print("[WC] Configuring WalletConnect...")

        let metadata = AppMetadata(
            name: "EthWallet",
            description: "Ethereum & Ethscription Wallet",
            url: "https://ethwallet.app",
            icons: ["https://ethwallet.app/icon.png"],
            redirect: AppMetadata.Redirect(native: "ethwallet://", universal: nil)
        )

        // Use the app's keychain access group to avoid App Group entitlement issues
        let keychainGroup = "G849HTGU43.com.jef.ethwallet.dev"

        Networking.configure(
            groupIdentifier: keychainGroup,
            projectId: projectId,
            socketFactory: DefaultSocketFactory()
        )

        Web3Wallet.configure(
            metadata: metadata,
            crypto: Web3CryptoProvider()
        )

        // Subscribe to session proposals
        Web3Wallet.instance.sessionProposalPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (proposal, _) in
                self?.pendingProposal = proposal
            }
            .store(in: &cancellables)

        // Subscribe to session requests
        Web3Wallet.instance.sessionRequestPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (request, _) in
                print("[WC] Received request: \(request.method) on chain \(request.chainId)")
                self?.pendingRequest = request
            }
            .store(in: &cancellables)

        // Subscribe to sessions
        Web3Wallet.instance.sessionsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sessions in
                self?.sessions = sessions
            }
            .store(in: &cancellables)

        // Load existing sessions
        refreshSessions()
        print("[WC] Configuration complete. Sessions: \(sessions.count)")
    }

    // MARK: - Pairing

    /// Connect to a dApp using WalletConnect URI
    func connect(uri: String) async throws {
        isConnecting = true
        error = nil

        do {
            guard let wcUri = WalletConnectURI(string: uri) else {
                throw WalletConnectError.invalidURI
            }
            try await Web3Wallet.instance.pair(uri: wcUri)
        } catch {
            self.error = "Failed to connect: \(error.localizedDescription)"
            isConnecting = false
            throw error
        }

        isConnecting = false
    }

    // MARK: - Session Management

    /// Approve a session proposal
    func approveProposal(accounts: [String]) async throws {
        guard let proposal = pendingProposal else {
            throw WalletConnectError.noProposal
        }

        guard let walletAddress = accounts.first, !walletAddress.isEmpty else {
            throw WalletConnectError.noProposal
        }

        var sessionNamespaces: [String: SessionNamespace] = [:]

        // Handle required namespaces
        for (key, requiredNamespace) in proposal.requiredNamespaces {
            var chains: [Blockchain] = requiredNamespace.chains ?? []

            // If no chains specified, try to infer from the namespace key (e.g., "eip155" -> eip155:1)
            if chains.isEmpty {
                if key == "eip155" {
                    // Default to Ethereum mainnet
                    if let mainnet = Blockchain("eip155:1") {
                        chains = [mainnet]
                    }
                }
            }

            // Create accounts for each chain
            let accountsForChains: [WalletConnectUtils.Account] = chains.compactMap { chain in
                WalletConnectUtils.Account(blockchain: chain, address: walletAddress)
            }

            // Only add namespace if we have accounts
            if !accountsForChains.isEmpty {
                sessionNamespaces[key] = SessionNamespace(
                    chains: chains,
                    accounts: accountsForChains,
                    methods: requiredNamespace.methods,
                    events: requiredNamespace.events
                )
            }
        }

        // Also handle optional namespaces if they exist
        if let optionalNamespaces = proposal.optionalNamespaces {
            for (key, optionalNamespace) in optionalNamespaces {
                // Skip if we already have this namespace from required
                if sessionNamespaces[key] != nil { continue }

                let chains = optionalNamespace.chains ?? []
                let accountsForChains: [WalletConnectUtils.Account] = chains.compactMap { chain in
                    WalletConnectUtils.Account(blockchain: chain, address: walletAddress)
                }

                if !accountsForChains.isEmpty {
                    sessionNamespaces[key] = SessionNamespace(
                        chains: chains,
                        accounts: accountsForChains,
                        methods: optionalNamespace.methods,
                        events: optionalNamespace.events
                    )
                }
            }
        }

        do {
            try await Web3Wallet.instance.approve(proposalId: proposal.id, namespaces: sessionNamespaces)
            pendingProposal = nil
        } catch {
            self.error = "Failed to approve: \(error.localizedDescription)"
            throw error
        }
    }

    /// Reject a session proposal
    func rejectProposal() async throws {
        guard let proposal = pendingProposal else { return }

        try await Web3Wallet.instance.rejectSession(proposalId: proposal.id, reason: .userRejected)
        pendingProposal = nil
    }

    /// Disconnect a session
    func disconnect(session: Session) async throws {
        try await Web3Wallet.instance.disconnect(topic: session.topic)
        refreshSessions()
    }

    // MARK: - Request Handling

    /// Approve a signing request
    func approveRequest(response: AnyCodable) async throws {
        guard let request = pendingRequest else {
            throw WalletConnectError.noRequest
        }

        try await Web3Wallet.instance.respond(topic: request.topic, requestId: request.id, response: .response(response))
        pendingRequest = nil
    }

    /// Reject a signing request
    func rejectRequest() async throws {
        guard let request = pendingRequest else { return }

        let error = JSONRPCError(code: 4001, message: "User rejected")
        try await Web3Wallet.instance.respond(topic: request.topic, requestId: request.id, response: .error(error))
        pendingRequest = nil
    }

    // MARK: - Helpers

    private func refreshSessions() {
        sessions = Web3Wallet.instance.getSessions()
    }
}

// MARK: - Errors

enum WalletConnectError: Error, LocalizedError {
    case noProposal
    case noRequest
    case invalidURI
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .noProposal: return "No pending proposal"
        case .noRequest: return "No pending request"
        case .invalidURI: return "Invalid WalletConnect URI"
        case .signingFailed: return "Failed to sign"
        }
    }
}

// MARK: - Crypto Provider

/// Crypto provider implementation using web3swift
final class Web3CryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        // Reconstruct the 65-byte signature: r (32) + s (32) + v (1)
        // Note: EthereumSignature.v is already normalized (0 or 1), we need to add 27 back
        let sigData = signature.serialized

        // Use SECP256K1 to recover public key
        guard let result = SECP256K1.recoverPublicKey(hash: message, signature: sigData, compressed: false) else {
            throw Web3ServiceError.transactionFailed("Failed to recover public key")
        }
        return result
    }

    func keccak256(_ data: Data) -> Data {
        return data.sha3(.keccak256)
    }
}

// MARK: - Socket Factory

class DefaultSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        return WebSocketConnection(url: url)
    }
}

class WebSocketConnection: WebSocketConnecting {
    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    private var task: URLSessionWebSocketTask?

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    func connect() {
        print("[WC WebSocket] Connecting to \(request.url?.absoluteString ?? "unknown")")
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: request)
        task?.resume()
        isConnected = true
        print("[WC WebSocket] Connected")
        onConnect?()
        receiveMessage()
    }

    func disconnect() {
        print("[WC WebSocket] Disconnecting")
        task?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
        onDisconnect?(nil)
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in
            completion?()
        }
    }

    private func receiveMessage() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("[WC WebSocket] Received text message (\(text.prefix(100))...)")
                    self?.onText?(text)
                case .data(let data):
                    print("[WC WebSocket] Received data message (\(data.count) bytes)")
                    if let text = String(data: data, encoding: .utf8) {
                        self?.onText?(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
            case .failure(let error):
                print("[WC WebSocket] Receive error: \(error.localizedDescription)")
                self?.isConnected = false
                self?.onDisconnect?(error)
            }
        }
    }
}
