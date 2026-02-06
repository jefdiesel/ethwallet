import SwiftUI
import Web3Wallet

/// View for managing WalletConnect dApp connections
struct WalletConnectView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var wcService: WalletConnectService

    @State private var wcURI = ""
    @State private var isConnecting = false
    @State private var showingProposal = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("WalletConnect")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Connect section
            connectSection
                .padding()

            Divider()

            // Active sessions
            if wcService.sessions.isEmpty {
                emptyView
            } else {
                sessionsList
            }
        }
        .sheet(isPresented: $showingProposal) {
            if let proposal = wcService.pendingProposal {
                ProposalSheet(proposal: proposal, wcService: wcService, walletViewModel: walletViewModel)
            }
        }
        .onChange(of: wcService.pendingProposal) { _, newValue in
            showingProposal = newValue != nil
        }
    }

    // MARK: - Connect Section

    @ViewBuilder
    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect to dApp")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Paste WalletConnect URI (wc:...)", text: $wcURI)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                Button {
                    connect()
                } label: {
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(wcURI.isEmpty || isConnecting)
            }

            if let error = wcService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Sessions List

    @ViewBuilder
    private var sessionsList: some View {
        List {
            Section("Active Sessions") {
                ForEach(wcService.sessions, id: \.topic) { session in
                    SessionRow(session: session, onDisconnect: {
                        Task {
                            try? await wcService.disconnect(session: session)
                        }
                    })
                }
            }
        }
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Active Connections")
                .font(.headline)

            Text("Connect to a dApp by pasting a WalletConnect URI from the dApp's connect modal.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func connect() {
        guard !wcURI.isEmpty else { return }

        isConnecting = true

        Task {
            do {
                try await wcService.connect(uri: wcURI)
                await MainActor.run {
                    wcURI = ""
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                }
            }
        }
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session
    let onDisconnect: () -> Void

    var body: some View {
        HStack {
            // dApp icon
            AsyncImage(url: URL(string: session.peer.icons.first ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } placeholder: {
                Image(systemName: "app.fill")
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // dApp info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.peer.name)
                    .font(.body)
                    .fontWeight(.medium)

                Text(session.peer.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Disconnect button
            Button(role: .destructive) {
                onDisconnect()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Proposal Sheet

struct ProposalSheet: View {
    let proposal: Session.Proposal
    @ObservedObject var wcService: WalletConnectService
    @ObservedObject var walletViewModel: WalletViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isApproving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // dApp info
                VStack(spacing: 12) {
                    AsyncImage(url: URL(string: proposal.proposer.icons.first ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(proposal.proposer.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(proposal.proposer.url)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("wants to connect to your wallet")
                    .font(.body)
                    .foregroundStyle(.secondary)

                // Requested permissions
                VStack(alignment: .leading, spacing: 8) {
                    Text("Requested Permissions")
                        .font(.headline)

                    ForEach(Array(proposal.requiredNamespaces.keys), id: \.self) { key in
                        if let namespace = proposal.requiredNamespaces[key] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chain: \(key)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("Methods: \(namespace.methods.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 16) {
                    Button("Reject") {
                        Task {
                            try? await wcService.rejectProposal()
                            dismiss()
                        }
                    }
                    .buttonStyle(.bordered)

                    Button {
                        approve()
                    } label: {
                        if isApproving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Approve")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isApproving)
                }
            }
            .padding()
            .navigationTitle("Connection Request")
        }
        .frame(minWidth: 340, minHeight: 380)
    }

    private func approve() {
        guard let account = walletViewModel.selectedAccount else {
            wcService.error = "No wallet account selected"
            return
        }

        isApproving = true

        Task {
            do {
                try await wcService.approveProposal(accounts: [account.address])
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isApproving = false
                }
            }
        }
    }
}

// MARK: - Request Sheet

struct RequestSheet: View {
    let request: Request
    @ObservedObject var wcService: WalletConnectService
    @ObservedObject var walletViewModel: WalletViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isSigning = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Request type
                Image(systemName: requestIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text(requestTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Request details
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

                    if let message = extractMessage() {
                        Text("Message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(message)
                                .font(.body)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                // Actions
                HStack(spacing: 16) {
                    Button("Reject") {
                        Task {
                            try? await wcService.rejectRequest()
                            dismiss()
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
        .frame(minWidth: 340, minHeight: 340)
    }

    private var requestIcon: String {
        switch request.method {
        case "personal_sign", "eth_sign":
            return "signature"
        case "eth_sendTransaction":
            return "arrow.up.circle"
        default:
            return "doc.text"
        }
    }

    private var requestTitle: String {
        switch request.method {
        case "personal_sign":
            return "Sign Message"
        case "eth_sign":
            return "Sign Data"
        case "eth_signTypedData", "eth_signTypedData_v4":
            return "Sign Typed Data"
        case "eth_sendTransaction":
            return "Send Transaction"
        case "eth_signTransaction":
            return "Sign Transaction"
        default:
            return "Sign Request"
        }
    }

    private func extractMessage() -> String? {
        guard let params = request.params.value as? [Any] else { return nil }

        switch request.method {
        case "personal_sign":
            // personal_sign: [message, address]
            guard let hexMessage = params.first as? String else { return nil }
            return hexToString(hexMessage) ?? hexMessage

        case "eth_sign":
            // eth_sign: [address, message]
            guard params.count >= 2, let hexMessage = params[1] as? String else { return nil }
            return hexToString(hexMessage) ?? hexMessage

        case "eth_sendTransaction", "eth_signTransaction":
            // [txObject]
            guard let tx = params.first as? [String: Any] else { return nil }
            return formatTransaction(tx)

        default:
            return nil
        }
    }

    private func hexToString(_ hex: String) -> String? {
        let clean = hex.replacingOccurrences(of: "0x", with: "")
        guard let data = Data(hexString: clean) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func formatTransaction(_ tx: [String: Any]) -> String {
        var lines: [String] = []
        if let to = tx["to"] as? String {
            lines.append("To: \(to)")
        }
        if let value = tx["value"] as? String {
            lines.append("Value: \(value)")
        }
        if let data = tx["data"] as? String, data != "0x" {
            lines.append("Data: \(data.prefix(50))...")
        }
        return lines.joined(separator: "\n")
    }

    private func sign() {
        guard let account = walletViewModel.selectedAccount else {
            error = "No account selected"
            return
        }

        isSigning = true
        error = nil

        Task {
            do {
                // Get private key
                let privateKey = try await walletViewModel.getPrivateKey(for: account)

                // Sign based on method
                let signature: String

                switch request.method {
                case "personal_sign":
                    signature = try await signPersonalMessage(privateKey: privateKey)
                case "eth_sign":
                    signature = try await signEthMessage(privateKey: privateKey)
                case "eth_sendTransaction":
                    signature = try await sendTransaction(privateKey: privateKey, from: account.address)
                default:
                    throw WalletConnectError.signingFailed
                }

                try await wcService.approveRequest(response: AnyCodable(signature))

                await MainActor.run {
                    dismiss()
                }
            } catch {
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

        // Use web3swift to sign
        let web3Service = Web3Service()
        return try await web3Service.signPersonalMessage(message: message, privateKey: privateKey)
    }

    private func signEthMessage(privateKey: Data) async throws -> String {
        guard let params = request.params.value as? [String],
              params.count >= 2 else {
            throw WalletConnectError.signingFailed
        }

        let message = params[1]
        let web3Service = Web3Service()
        return try await web3Service.signMessage(message: message, privateKey: privateKey)
    }

    private func sendTransaction(privateKey: Data, from: String) async throws -> String {
        guard let params = request.params.value as? [[String: Any]],
              let txDict = params.first else {
            throw WalletConnectError.signingFailed
        }

        // Get the chain ID from the request
        // The request.chainId.reference is the chain number (e.g., "1" for mainnet)
        let chainId = Int(request.chainId.reference) ?? 1

        // Find or create network for this chain
        let network = Network.forChainId(chainId) ?? .ethereum
        let web3Service = Web3Service(network: network)
        return try await web3Service.sendTransactionFromDict(txDict, from: from, privateKey: privateKey)
    }
}

// MARK: - Data Extension

private extension Data {
    init?(hexString: String) {
        let hex = hexString.replacingOccurrences(of: "0x", with: "")
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}

#Preview {
    WalletConnectView()
        .environmentObject(WalletViewModel())
        .environmentObject(WalletConnectService.shared)
}
