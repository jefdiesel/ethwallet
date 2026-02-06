import SwiftUI
import Combine
import Web3Wallet

// Make WalletConnect Request identifiable for sheet binding
extension Request: @retroactive Identifiable {}

/// Main entry point for the macOS application
@main
struct PixelWalletApp: App {
    @StateObject private var walletViewModel = WalletViewModel()
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var priceService = PriceService.shared
    @StateObject private var wcService = WalletConnectService.shared

    @State private var activeWCRequest: Request?

    var body: some Scene {
        WindowGroup {
            WalletView()
                .environmentObject(walletViewModel)
                .environmentObject(networkManager)
                .environmentObject(priceService)
                .environmentObject(wcService)
                .frame(width: 440, height: 700)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.765, green: 1.0, blue: 0.0)) // #c3ff00
                .onAppear {
                    // Configure WalletConnect at app launch
                    wcService.configure()
                }
                .onChange(of: wcService.pendingRequest) { _, newValue in
                    if let request = newValue {
                        activeWCRequest = request
                    }
                }
                .sheet(item: $activeWCRequest) { request in
                    WCRequestSheet(request: request, wcService: wcService, walletViewModel: walletViewModel) {
                        activeWCRequest = nil
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            MacMenuCommands(walletViewModel: walletViewModel)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(networkManager)
        }
        #endif
    }
}

// MARK: - WalletConnect Request Sheet (App-level)

struct WCRequestSheet: View {
    let request: Request
    @ObservedObject var wcService: WalletConnectService
    @ObservedObject var walletViewModel: WalletViewModel
    let onDismiss: () -> Void

    @State private var isSigning = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: requestIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text(requestTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Method")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.method)
                        .font(.body.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                HStack(spacing: 16) {
                    Button("Reject") {
                        Task {
                            try? await wcService.rejectRequest()
                            onDismiss()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        sign()
                    } label: {
                        if isSigning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Sign")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning)
                }
            }
            .padding()
            .navigationTitle("Signature Request")
        }
        .frame(minWidth: 320, minHeight: 320)
    }

    private var requestIcon: String {
        switch request.method {
        case "personal_sign", "eth_sign": return "signature"
        case "eth_sendTransaction": return "arrow.up.circle"
        default: return "doc.text"
        }
    }

    private var requestTitle: String {
        switch request.method {
        case "personal_sign": return "Sign Message"
        case "eth_sign": return "Sign Data"
        case "eth_signTypedData", "eth_signTypedData_v4": return "Sign Typed Data"
        case "eth_sendTransaction": return "Send Transaction"
        default: return "Sign Request"
        }
    }

    private func sign() {
        guard let account = walletViewModel.selectedAccount else {
            error = "No account selected"
            return
        }

        print("[WC Sign] Starting sign for \(request.method)")
        isSigning = true
        error = nil

        Task {
            do {
                print("[WC Sign] Getting private key...")
                let privateKey = try await walletViewModel.getPrivateKey(for: account)
                print("[WC Sign] Got private key, length: \(privateKey.count)")
                let signature: String

                switch request.method {
                case "personal_sign":
                    print("[WC Sign] Signing personal message...")
                    signature = try await signPersonalMessage(privateKey: privateKey)
                case "eth_sign":
                    print("[WC Sign] Signing eth message...")
                    signature = try await signEthMessage(privateKey: privateKey)
                case "eth_sendTransaction":
                    print("[WC Sign] Sending transaction...")
                    signature = try await sendTransaction(privateKey: privateKey, from: account.address)
                default:
                    throw WalletConnectError.signingFailed
                }

                print("[WC Sign] Success! Result: \(signature.prefix(20))...")
                try await wcService.approveRequest(response: AnyCodable(signature))
                print("[WC Sign] Approved request, dismissing")
                await MainActor.run { onDismiss() }
            } catch {
                print("[WC Sign] ERROR: \(error)")
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSigning = false
                }
            }
        }
    }

    private func signPersonalMessage(privateKey: Data) async throws -> String {
        guard let params = request.params.value as? [String],
              let message = params.first else {
            throw WalletConnectError.signingFailed
        }
        let web3Service = Web3Service()
        return try await web3Service.signPersonalMessage(message: message, privateKey: privateKey)
    }

    private func signEthMessage(privateKey: Data) async throws -> String {
        guard let params = request.params.value as? [String],
              params.count >= 2 else {
            throw WalletConnectError.signingFailed
        }
        let web3Service = Web3Service()
        return try await web3Service.signMessage(message: params[1], privateKey: privateKey)
    }

    private func sendTransaction(privateKey: Data, from: String) async throws -> String {
        print("[WC] sendTransaction params raw: \(request.params)")
        guard let params = request.params.value as? [[String: Any]],
              let txDict = params.first else {
            print("[WC] Failed to parse params as [[String: Any]]")
            throw WalletConnectError.signingFailed
        }
        print("[WC] Transaction dict: \(txDict)")
        let chainId = Int(request.chainId.reference) ?? 1
        let network = Network.forChainId(chainId) ?? .ethereum
        print("[WC] Using chain \(chainId), network: \(network.name)")
        let web3Service = Web3Service(network: network)
        print("[WC] Calling sendTransactionFromDict...")
        let result = try await web3Service.sendTransactionFromDict(txDict, from: from, privateKey: privateKey)
        print("[WC] sendTransactionFromDict returned: \(result)")
        return result
    }
}
