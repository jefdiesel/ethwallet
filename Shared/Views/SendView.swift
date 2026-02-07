import SwiftUI

/// View for sending ETH or tokens via smart account
struct SendView: View {
    let account: Account?
    var smartAccount: SmartAccount? = nil
    var isSmartAccountEnabled: Bool = false
    @StateObject private var viewModel = SendViewModel()
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkManager = NetworkManager.shared

    @State private var showingConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Asset type selector
                    assetSelector

                    // From section
                    fromSection

                    // Recipient section
                    recipientSection

                    // Amount section (for ETH/Token)
                    if viewModel.selectedAsset != .ethscription {
                        amountSection
                    }

                    // Smart account toggle
                    if isSmartAccountEnabled && viewModel.canUseSmartAccount {
                        smartAccountSection
                    }

                    // Fee section
                    feeSection

                    // Error display
                    if let error = viewModel.sendError {
                        errorSection(error)
                    }

                    Spacer(minLength: 20)
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Send")
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
        }
        .frame(minWidth: 380, idealWidth: 400, minHeight: 500)
        .onAppear {
            configureViewModel()
        }
        .sheet(isPresented: $showingConfirmation) {
            SendConfirmationSheet(viewModel: viewModel) {
                dismiss()
            }
        }
    }

    // MARK: - Asset Selector

    private var assetSelector: some View {
        Picker("", selection: $viewModel.selectedAsset) {
            Text("ETH").tag(SendAsset.eth)
            Text("Token").tag(SendAsset.token)
            Text("Ethscription").tag(SendAsset.ethscription)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - From Section

    private var fromSection: some View {
        SendSection(title: "FROM") {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(String((account?.label ?? "Account").prefix(1)))
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account?.label ?? "Account")
                        .font(.headline)

                    if viewModel.useSmartAccount, let sa = viewModel.smartAccount {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(sa.smartAccountAddress, forType: .string)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption2)
                                Text(sa.shortAddress)
                                    .font(.caption.monospaced())
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                        .help("Click to copy: \(sa.smartAccountAddress)")
                    } else {
                        Text(account?.shortAddress ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if viewModel.isLoadingBalance {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(viewModel.displayBalance)
                            .font(.headline.monospacedDigit())
                        Text(networkManager.selectedNetwork.currencySymbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Recipient Section

    private var recipientSection: some View {
        SendSection(title: "TO") {
            VStack(spacing: 8) {
                TextField("Address or ENS name", text: $viewModel.recipientAddress)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Resolution status
                if viewModel.isResolvingName {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Resolving...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if let name = viewModel.resolvedName, viewModel.resolvedAddress != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(name)
                            .font(.caption)
                        Spacer()
                    }
                }

                // Error
                if let error = viewModel.recipientError {
                    HStack {
                        Image(systemName: error.hasPrefix("Warning") ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                            .foregroundStyle(error.hasPrefix("Warning") ? .orange : .red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(error.hasPrefix("Warning") ? .orange : .red)
                        Spacer()
                    }
                }

                // Security warnings
                if !viewModel.securityWarnings.isEmpty {
                    SecurityWarningBanner(warnings: viewModel.securityWarnings)
                }
            }
            .padding(12)
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        SendSection(title: "AMOUNT") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("0.0", text: $viewModel.amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                        .padding(12)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(spacing: 4) {
                        Text(viewModel.selectedAsset == .token ? (viewModel.selectedToken?.symbol ?? "TOKEN") : "ETH")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Button("MAX") {
                            viewModel.setMaxAmount()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // USD value
                if !viewModel.amount.isEmpty && viewModel.selectedAsset == .eth {
                    HStack {
                        Text("≈ \(viewModel.amountUSD)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }

                // Error
                if let error = viewModel.amountError {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: - Smart Account Section

    private var smartAccountSection: some View {
        SendSection(title: "SEND FROM") {
            VStack(spacing: 0) {
                // EOA option
                Button {
                    viewModel.useSmartAccount = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.useSmartAccount ? "circle" : "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(viewModel.useSmartAccount ? .secondary : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Regular Wallet (EOA)")
                                .foregroundStyle(.primary)
                            Text(account?.shortAddress ?? "")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 44)

                // Smart Account option
                Button {
                    viewModel.useSmartAccount = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: viewModel.useSmartAccount ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(viewModel.useSmartAccount ? .blue : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption)
                                Text("Smart Account")
                            }
                            .foregroundStyle(.primary)

                            if let sa = viewModel.smartAccount {
                                Text(sa.shortAddress)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if let sa = viewModel.smartAccount, !sa.isDeployed {
                            Text("Not deployed")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Gasless option (only when smart account selected)
                if viewModel.useSmartAccount {
                    Divider().padding(.leading, 44)

                    Toggle(isOn: $viewModel.usePaymaster) {
                        HStack(spacing: 8) {
                            Image(systemName: "gift")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Gasless (Sponsored)")
                                Text("Pimlico pays the gas fee")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!viewModel.isPaymasterAvailable)
                    .padding(12)
                }
            }
        }
    }

    // MARK: - Fee Section

    private var feeSection: some View {
        SendSection(title: "NETWORK FEE") {
            HStack {
                if viewModel.useSmartAccount && viewModel.usePaymaster {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Sponsored - Free!")
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                } else if viewModel.isEstimatingGas {
                    ProgressView().controlSize(.small)
                    Text("Estimating...")
                        .foregroundStyle(.secondary)
                } else if let estimate = viewModel.gasEstimate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.formattedCost)
                            .font(.headline)
                        Text("Gas: \(estimate.gasLimit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Enter recipient and amount")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.callout)
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Configuration

    private func configureViewModel() {
        guard let account = account else { return }
        viewModel.configure(account: account, balance: 0)

        if isSmartAccountEnabled, let smartAccount = smartAccount {
            viewModel.configureSmartAccount(smartAccount: smartAccount)
            // Auto-enable smart account if available
            viewModel.useSmartAccount = true
            viewModel.usePaymaster = true
        }
    }
}

// MARK: - Send Section Component

struct SendSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Send Confirmation Sheet

struct SendConfirmationSheet: View {
    @ObservedObject var viewModel: SendViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkManager = NetworkManager.shared

    var onSuccess: () -> Void

    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Amount display
                VStack(spacing: 8) {
                    Text(viewModel.amount.isEmpty ? "0" : viewModel.amount)
                        .font(.system(size: 48, weight: .semibold, design: .rounded))

                    Text(viewModel.selectedAsset == .token ? (viewModel.selectedToken?.symbol ?? "TOKEN") : networkManager.selectedNetwork.currencySymbol)
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    if viewModel.selectedAsset == .eth {
                        Text(viewModel.amountUSD)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Arrow
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)

                // Recipient
                VStack(spacing: 4) {
                    if let name = viewModel.resolvedName {
                        Text(name)
                            .font(.headline)
                    }
                    Text(viewModel.resolvedAddress ?? viewModel.recipientAddress)
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Smart account badge
                if viewModel.useSmartAccount {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                        Text("Smart Account Transaction")
                        if viewModel.usePaymaster {
                            Text("• Gasless")
                                .foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }

                Spacer()

                // Fee
                if let estimate = viewModel.gasEstimate, !(viewModel.useSmartAccount && viewModel.usePaymaster) {
                    HStack {
                        Text("Network Fee")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(estimate.formattedCost)
                    }
                    .font(.callout)
                }

                // Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button {
                        send()
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Confirm Send")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isSending)
                }
            }
            .padding(24)
            .navigationTitle("Confirm")
        }
        .frame(minWidth: 340, minHeight: 420)
        .sheet(isPresented: $showingSuccess) {
            SendSuccessSheet(
                txHash: viewModel.lastTransactionHash ?? viewModel.userOperationHash ?? "",
                isUserOperation: viewModel.userOperationHash != nil,
                onDone: {
                    showingSuccess = false
                    onSuccess()
                }
            )
        }
    }

    private func send() {
        Task {
            do {
                _ = try await viewModel.send()
                await MainActor.run {
                    showingSuccess = true
                }
            } catch {
                // Error displayed in viewModel
            }
        }
    }
}

// MARK: - Send Success Sheet

struct SendSuccessSheet: View {
    let txHash: String
    var isUserOperation: Bool = false
    var onDone: () -> Void

    @StateObject private var networkManager = NetworkManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Sent!")
                .font(.title)
                .fontWeight(.semibold)

            if isUserOperation {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                    Text("Smart Account Transaction")
                }
                .font(.callout)
                .foregroundStyle(.blue)

                Text("Your transaction is being bundled and will appear on-chain shortly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text(isUserOperation ? "UserOperation Hash" : "Transaction Hash")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(txHash)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !isUserOperation, let url = networkManager.selectedNetwork.explorerTransactionURL(txHash) {
                Link(destination: url) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                }
            }

            Spacer()

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(minWidth: 300, minHeight: 340)
    }
}

#Preview {
    SendView(account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"))
}
