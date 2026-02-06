import SwiftUI
import BigInt

/// View for swapping tokens
struct SwapView: View {
    let account: Account
    let chainId: Int

    @StateObject private var viewModel = SwapViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var showingConfirmation = false
    @State private var showingSuccess = false
    @State private var showingTokenPicker: TokenPickerType?

    enum TokenPickerType: Identifiable {
        case sell, buy
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.isSwapSupported {
                    unsupportedChainView
                } else {
                    swapForm
                }
            }
            .navigationTitle("Swap")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 340, minHeight: 440)
        .onAppear {
            viewModel.configure(account: account, chainId: chainId)
        }
        .sheet(item: $showingTokenPicker) { type in
            TokenSelectorView(
                tokens: viewModel.availableTokens,
                selectedToken: type == .sell ? viewModel.sellToken : viewModel.buyToken,
                excludeToken: type == .sell ? viewModel.buyToken : viewModel.sellToken
            ) { token in
                if type == .sell {
                    viewModel.sellToken = token
                } else {
                    viewModel.buyToken = token
                }
                showingTokenPicker = nil
            }
        }
        .sheet(isPresented: $showingConfirmation) {
            SwapConfirmationSheet(viewModel: viewModel) {
                showingSuccess = true
            }
        }
        .sheet(isPresented: $showingSuccess) {
            SwapSuccessSheet(
                txHash: viewModel.lastSwapHash ?? "",
                chainId: chainId,
                onDone: { dismiss() }
            )
        }
    }

    // MARK: - Unsupported Chain View

    @ViewBuilder
    private var unsupportedChainView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Swaps Not Supported")
                .font(.headline)

            Text("Token swaps are not available on this network. Switch to Ethereum mainnet or Base to use swaps.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Swap Form

    @ViewBuilder
    private var swapForm: some View {
        Form {
            // Sell token section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You Pay")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            showingTokenPicker = .sell
                        } label: {
                            HStack(spacing: 8) {
                                tokenIcon(viewModel.sellToken)
                                Text(viewModel.sellToken.symbol)
                                    .font(.headline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        TextField("0.0", text: $viewModel.sellAmount)
                            .textFieldStyle(.plain)
                            .font(.system(size: 24, weight: .medium, design: .monospaced))
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }

                    HStack {
                        Text("Balance: \(viewModel.formattedSellBalance)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Max") {
                            viewModel.setMaxAmount()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                }
            }

            // Swap direction button
            Section {
                HStack {
                    Spacer()
                    Button {
                        viewModel.swapTokens()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.title2)
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }

            // Buy token section
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("You Receive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            showingTokenPicker = .buy
                        } label: {
                            HStack(spacing: 8) {
                                tokenIcon(viewModel.buyToken)
                                Text(viewModel.buyToken.symbol)
                                    .font(.headline)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        if viewModel.isLoadingQuote {
                            ProgressView()
                                .controlSize(.small)
                        } else if let quote = viewModel.quote {
                            Text(quote.formattedBuyAmount.replacingOccurrences(of: " \(viewModel.buyToken.symbol)", with: ""))
                                .font(.system(size: 24, weight: .medium, design: .monospaced))
                        } else {
                            Text("0.0")
                                .font(.system(size: 24, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Balance: \(viewModel.formattedBuyBalance)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Quote details
            if let quote = viewModel.quote {
                Section("Quote Details") {
                    LabeledContent("Rate", value: quote.formattedPrice)
                    LabeledContent("Price Impact", value: quote.formattedPriceImpact)
                    LabeledContent("Estimated Gas", value: quote.formattedGasCost)

                    if !quote.sources.isEmpty {
                        LabeledContent("Route", value: quote.routeSummary)
                    }
                }
            }

            // Error display
            if let error = viewModel.quoteError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            // Slippage settings
            Section {
                Picker("Slippage Tolerance", selection: $viewModel.slippage) {
                    ForEach(SlippageTolerance.allCases) { slippage in
                        Text(slippage.displayName).tag(slippage)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Settings")
            } footer: {
                Text("Slippage tolerance is the maximum price change you're willing to accept.")
            }

            // Swap button
            Section {
                Button {
                    showingConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.needsApproval {
                            Text("Approve & Swap")
                        } else {
                            Text("Swap")
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.primary)
                .disabled(!viewModel.canSwap)
            }
        }
        .formStyle(.automatic)
    }

    @ViewBuilder
    private func tokenIcon(_ token: SwapToken) -> some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: 28, height: 28)
            .overlay {
                Text(String(token.symbol.prefix(2)))
                    .font(.caption2)
                    .fontWeight(.bold)
            }
    }
}

// MARK: - Token Selector View

struct TokenSelectorView: View {
    let tokens: [SwapToken]
    let selectedToken: SwapToken
    let excludeToken: SwapToken
    let onSelect: (SwapToken) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(tokens.filter { $0.address != excludeToken.address }, id: \.address) { token in
                    Button {
                        onSelect(token)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(String(token.symbol.prefix(2)))
                                        .font(.caption)
                                        .fontWeight(.bold)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(token.symbol)
                                    .font(.headline)
                                Text(token.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if token.address == selectedToken.address {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Token")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 300, minHeight: 320)
    }
}

// MARK: - Swap Confirmation Sheet

struct SwapConfirmationSheet: View {
    @ObservedObject var viewModel: SwapViewModel
    @Environment(\.dismiss) private var dismiss

    var onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let quote = viewModel.quote {
                    // Sell amount
                    VStack(spacing: 8) {
                        Text(quote.formattedSellAmount)
                            .font(.system(size: 32, weight: .medium, design: .monospaced))

                        Text("You Pay")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Image(systemName: "arrow.down")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    // Buy amount
                    VStack(spacing: 8) {
                        Text(quote.formattedBuyAmount)
                            .font(.system(size: 32, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green)

                        Text("You Receive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Details
                    VStack(spacing: 8) {
                        detailRow("Rate", quote.formattedPrice)
                        detailRow("Price Impact", quote.formattedPriceImpact)
                        detailRow("Network Fee", quote.formattedGasCost)
                        detailRow("Slippage", viewModel.slippage.displayName)
                    }
                }

                if let error = viewModel.swapError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()

                // Buttons
                HStack(spacing: 8) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.secondary)

                    Button {
                        executeSwap()
                    } label: {
                        if viewModel.isApproving || viewModel.isSwapping {
                            ProgressView()
                                .controlSize(.small)
                        } else if viewModel.needsApproval {
                            Text("Approve & Swap")
                        } else {
                            Text("Confirm")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(viewModel.isApproving || viewModel.isSwapping)
                }
            }
            .padding()
            .navigationTitle("Confirm Swap")
        }
        .frame(minWidth: 300, minHeight: 360)
    }

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }

    private func executeSwap() {
        Task {
            do {
                // Approve if needed
                if viewModel.needsApproval {
                    try await viewModel.approve()
                }

                // Execute swap
                _ = try await viewModel.executeSwap()

                await MainActor.run {
                    dismiss()
                    onSuccess()
                }
            } catch {
                // Error is displayed in viewModel.swapError
            }
        }
    }
}

// MARK: - Swap Success Sheet

struct SwapSuccessSheet: View {
    let txHash: String
    let chainId: Int
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Swap Submitted")
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

            if let explorerURL = explorerURL {
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
        .frame(minWidth: 280, minHeight: 240)
    }

    private var explorerURL: URL? {
        let baseURL: String
        switch chainId {
        case 1:
            baseURL = "https://etherscan.io"
        case 8453:
            baseURL = "https://basescan.org"
        default:
            return nil
        }
        return URL(string: "\(baseURL)/tx/\(txHash)")
    }
}

#Preview {
    SwapView(
        account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"),
        chainId: 1
    )
}
