import SwiftUI

/// View for sending ETH or ethscriptions
struct SendView: View {
    let account: Account?
    @StateObject private var viewModel = SendViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingConfirmation = false
    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                // Asset type selector
                Section {
                    Picker("Send", selection: $viewModel.selectedAsset) {
                        ForEach(SendAsset.allCases) { asset in
                            Text(asset.displayName).tag(asset)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // Recipient address
                Section("Recipient") {
                    TextField("Address or ethscription name", text: $viewModel.recipientAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                        #if os(iOS)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        #endif

                    // Name resolution status
                    if viewModel.isResolvingName {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Resolving \(viewModel.resolvedName ?? "")...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let name = viewModel.resolvedName, let address = viewModel.resolvedAddress {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(address)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }

                    if let error = viewModel.recipientError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(error.hasPrefix("Warning") ? .orange : .red)
                    }

                    // Security warnings
                    if !viewModel.securityWarnings.isEmpty {
                        SecurityWarningBanner(warnings: viewModel.securityWarnings)
                    } else if viewModel.isCheckingSecurity {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking recipient security...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Token selector (for Token type)
                if viewModel.selectedAsset == .token {
                    Section("Token") {
                        if let token = viewModel.selectedToken,
                           let balance = viewModel.selectedTokenBalance {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(token.symbol)
                                        .font(.headline)
                                    Text(token.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(balance.formattedBalance)
                                        .font(.body.monospaced())
                                    Button("Change") {
                                        viewModel.selectedToken = nil
                                        viewModel.selectedTokenBalance = nil
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                }
                            }
                        } else {
                            NavigationLink {
                                TokenPickerView(
                                    address: account?.address ?? "",
                                    selectedToken: $viewModel.selectedToken,
                                    selectedBalance: $viewModel.selectedTokenBalance
                                )
                            } label: {
                                Text("Select Token")
                            }
                        }
                    }
                }

                // Amount (for ETH and Token)
                if viewModel.selectedAsset == .eth || viewModel.selectedAsset == .token {
                    Section("Amount") {
                        HStack {
                            TextField("0.0", text: $viewModel.amount)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif

                            Text(viewModel.selectedAsset == .token ? (viewModel.selectedToken?.symbol ?? "Token") : "ETH")
                                .foregroundStyle(.secondary)

                            Button("Max") {
                                viewModel.setMaxAmount()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !viewModel.amount.isEmpty && viewModel.selectedAsset == .eth {
                            Text(viewModel.amountUSD)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let error = viewModel.amountError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                // Ethscription selector
                if viewModel.selectedAsset == .ethscription {
                    Section("Ethscription") {
                        if let ethscription = viewModel.selectedEthscription {
                            HStack {
                                EthscriptionRow(ethscription: ethscription)
                                Spacer()
                                Button("Change") {
                                    viewModel.selectedEthscription = nil
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            NavigationLink {
                                EthscriptionPickerView(
                                    address: account?.address ?? "",
                                    selectedEthscription: $viewModel.selectedEthscription
                                )
                            } label: {
                                Text("Select Ethscription")
                            }
                        }
                    }
                }

                // Gas estimate
                Section("Transaction Fee") {
                    if viewModel.isEstimatingGas {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Estimating...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let estimate = viewModel.gasEstimate {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Estimated Fee")
                                Spacer()
                                Text(estimate.formattedCost)
                                    .fontWeight(.medium)
                            }

                            HStack {
                                Text("Gas Limit")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(estimate.gasLimit)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Enter valid recipient and amount to estimate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Error display
                if let error = viewModel.sendError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.automatic)
            .navigationTitle("Send")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        showingConfirmation = true
                    }
                    .disabled(!viewModel.canSend)
                }
            }
            #endif
        }
        .frame(minWidth: 340, minHeight: 420)
        .onAppear {
            if let account = account {
                viewModel.configure(account: account, balance: 0)
            }
        }
        .sheet(isPresented: $showingConfirmation) {
            SendConfirmationSheet(viewModel: viewModel) {
                showingSuccess = true
            }
        }
        .sheet(isPresented: $showingSuccess) {
            SendSuccessSheet(
                txHash: viewModel.lastTransactionHash ?? "",
                onDone: { dismiss() }
            )
        }
    }
}

// MARK: - Send Confirmation Sheet

struct SendConfirmationSheet: View {
    @ObservedObject var viewModel: SendViewModel
    @Environment(\.dismiss) private var dismiss

    var onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Summary
                VStack(spacing: 16) {
                    if viewModel.selectedAsset == .eth {
                        Text(viewModel.amount)
                            .font(.system(size: 48, weight: .medium, design: .monospaced))

                        Text("ETH")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text(viewModel.amountUSD)
                            .foregroundStyle(.secondary)
                    } else if viewModel.selectedAsset == .token, let token = viewModel.selectedToken {
                        Text(viewModel.amount)
                            .font(.system(size: 48, weight: .medium, design: .monospaced))

                        Text(token.symbol)
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text(token.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let ethscription = viewModel.selectedEthscription {
                        EthscriptionRow(ethscription: ethscription)
                    }
                }

                // Arrow
                Image(systemName: "arrow.down")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                // Recipient
                VStack(spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let name = viewModel.resolvedName {
                        Text(name)
                            .font(.headline)
                    }

                    Text(viewModel.resolvedAddress ?? viewModel.recipientAddress)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(viewModel.resolvedName != nil ? .secondary : .primary)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

                // Fee
                if let estimate = viewModel.gasEstimate {
                    HStack {
                        Text("Network Fee")
                        Spacer()
                        Text(estimate.formattedCost)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Buttons
                HStack(spacing: 8) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.secondary)

                    Button {
                        send()
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Confirm")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(viewModel.isSending)
                }
            }
            .padding()
            .navigationTitle("Confirm")
        }
        .frame(minWidth: 300, minHeight: 360)
    }

    private func send() {
        Task {
            do {
                _ = try await viewModel.send()
                await MainActor.run {
                    dismiss()
                    onSuccess()
                }
            } catch {
                // Error is displayed in viewModel.sendError
            }
        }
    }
}

// MARK: - Send Success Sheet

struct SendSuccessSheet: View {
    let txHash: String
    var onDone: () -> Void

    @StateObject private var networkManager = NetworkManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Sent")
                .font(.headline)

            VStack(spacing: 4) {
                Text("Transaction Hash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(txHash)
                    .font(.caption2.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(6)

            if let explorerURL = networkManager.selectedNetwork.explorerTransactionURL(txHash) {
                Link(destination: explorerURL) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }

            Button("Done") {
                onDone()
            }
            .buttonStyle(.primary)
        }
        .padding()
        .frame(minWidth: 280, minHeight: 260)
    }
}

// MARK: - Ethscription Picker View

struct EthscriptionPickerView: View {
    let address: String
    @Binding var selectedEthscription: Ethscription?
    @Environment(\.dismiss) private var dismiss

    @State private var ethscriptions: [Ethscription] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading ethscriptions...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadEthscriptions() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ethscriptions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No ethscriptions found")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(ethscriptions) { ethscription in
                    Button {
                        selectedEthscription = ethscription
                        dismiss()
                    } label: {
                        EthscriptionRow(ethscription: ethscription)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Select Ethscription")
        .task {
            await loadEthscriptions()
        }
    }

    private func loadEthscriptions() async {
        guard !address.isEmpty else {
            error = "No account address"
            return
        }

        isLoading = true
        error = nil

        do {
            let fetched = try await AppChainService.shared.getOwnedEthscriptions(address: address)
            await MainActor.run {
                self.ethscriptions = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Ethscription Row

struct EthscriptionRow: View {
    let ethscription: Ethscription

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail placeholder
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay {
                    if ethscription.isImage {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.secondary)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                if let collection = ethscription.collection {
                    Text(collection.collectionName ?? "Unknown Collection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(collection.displayNumber)
                        .fontWeight(.medium)
                } else {
                    Text(ethscription.shortId)
                        .font(.body.monospaced())
                }

                Text(ethscription.mimeType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

// MARK: - Token Picker View

struct TokenPickerView: View {
    let address: String
    @Binding var selectedToken: Token?
    @Binding var selectedBalance: TokenBalance?
    @Environment(\.dismiss) private var dismiss

    @State private var balances: [TokenBalance] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var customTokenAddress = ""
    @State private var isAddingCustomToken = false

    private let tokenService = TokenService.shared
    private let networkManager = NetworkManager.shared

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading tokens...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadTokens() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Token list
                    Section("Your Tokens") {
                        ForEach(balances.filter { $0.hasBalance }) { balance in
                            Button {
                                selectedToken = balance.token
                                selectedBalance = balance
                                dismiss()
                            } label: {
                                tokenRow(balance: balance)
                            }
                            .buttonStyle(.plain)
                        }

                        if balances.filter({ $0.hasBalance }).isEmpty {
                            Text("No token balances found")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Add custom token
                    Section("Add Custom Token") {
                        TextField("Token contract address", text: $customTokenAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())

                        Button {
                            Task { await addCustomToken() }
                        } label: {
                            if isAddingCustomToken {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Add Token")
                            }
                        }
                        .disabled(customTokenAddress.isEmpty || isAddingCustomToken)
                    }
                }
            }
        }
        .navigationTitle("Select Token")
        .task {
            await loadTokens()
        }
    }

    @ViewBuilder
    private func tokenRow(balance: TokenBalance) -> some View {
        HStack(spacing: 12) {
            // Token icon placeholder
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(balance.token.symbol.prefix(2)))
                        .font(.caption)
                        .fontWeight(.bold)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(balance.token.symbol)
                    .font(.headline)
                Text(balance.token.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(balance.formattedBalance)
                .font(.body.monospaced())
        }
        .padding(.vertical, 4)
    }

    private func loadTokens() async {
        guard !address.isEmpty else {
            error = "No account address"
            return
        }

        isLoading = true
        error = nil

        let chainId = networkManager.selectedNetwork.id
        balances = await tokenService.getCommonTokenBalances(for: address, chainId: chainId)

        isLoading = false
    }

    private func addCustomToken() async {
        guard HexUtils.isValidAddress(customTokenAddress) else {
            error = "Invalid token address"
            return
        }

        isAddingCustomToken = true

        do {
            let chainId = networkManager.selectedNetwork.id
            let token = try await tokenService.getTokenInfo(address: customTokenAddress, chainId: chainId)
            let balance = try await tokenService.getBalance(of: token, for: address)

            await MainActor.run {
                balances.append(balance)
                customTokenAddress = ""
                isAddingCustomToken = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to add token: \(error.localizedDescription)"
                isAddingCustomToken = false
            }
        }
    }
}

#Preview {
    SendView(account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"))
}
