import SwiftUI
import BigInt
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// View displaying ERC-20 token balances
struct TokensView: View {
    let account: Account?
    let ethBalance: String
    let ethBalanceUSD: String

    @StateObject private var networkManager = NetworkManager.shared
    @State private var tokens: [TokenBalance] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingAddToken = false
    @State private var selectedToken: TokenBalance?

    private let tokenService = TokenService.shared

    /// Native token displayed as a token (ETH, SepoliaETH, etc.)
    private var nativeTokenBalance: TokenBalance {
        let network = networkManager.selectedNetwork
        let nativeToken = Token(
            address: "0x0000000000000000000000000000000000000000",
            symbol: network.currencySymbol,
            name: network.isTestnet ? "\(network.name) \(network.currencySymbol)" : network.name,
            decimals: 18,
            logoURL: nil,
            chainId: network.id
        )
        let usdValue = Double(ethBalanceUSD.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        return TokenBalance(
            token: nativeToken,
            rawBalance: ethBalance,
            formattedBalance: ethBalance,
            usdValue: usdValue
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let token = selectedToken {
                // Expanded chart view (hides token list)
                chartPanel(for: token)
            } else {
                // Normal token list view
                tokenListView
            }
        }
        .onAppear {
            Task { await loadTokens() }
        }
        .onChange(of: account?.address) { _, _ in
            Task { await loadTokens() }
        }
        .sheet(isPresented: $showingAddToken) {
            AddTokenSheet()
        }
    }

    // MARK: - Token List View

    @ViewBuilder
    private var tokenListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tokens")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button { showingAddToken = true } label: {
                    Image(systemName: "plus").font(.caption)
                }
                Button { Task { await loadTokens() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else {
                tokenList
            }
        }
    }

    @State private var showingSendToken = false
    @State private var showingReceiveToken = false
    @State private var tokenSendRecipient = ""
    @State private var tokenSendAmount = ""
    @State private var isTokenSending = false
    @State private var tokenSendError: String?
    @State private var tokenSendSuccess: String?
    @State private var tokenAddressCopied = false

    @EnvironmentObject var walletViewModel: WalletViewModel

    // MARK: - Chart Panel (Expanded)

    @ViewBuilder
    private func chartPanel(for token: TokenBalance) -> some View {
        if showingSendToken {
            tokenSendPanel(for: token)
        } else if showingReceiveToken {
            tokenReceivePanel
        } else {
            tokenDetailPanel(for: token)
        }
    }

    @ViewBuilder
    private func tokenDetailPanel(for token: TokenBalance) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { selectedToken = nil } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text(token.token.symbol)
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Balance section
                    HStack(spacing: 6) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(token.formattedBalance)
                            .font(.title3.bold().monospacedDigit())
                            .foregroundColor(AppColors.accent)
                        Spacer()
                        if let usd = token.usdValue {
                            Text("$\(usd, specifier: "%.2f")")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                    // Send/Receive buttons
                    HStack(spacing: 8) {
                        Button { withAnimation(.easeInOut(duration: 0.15)) { showingSendToken = true } } label: {
                            Label("Send", systemImage: "arrow.up")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccentButtonStyle())

                        Button { withAnimation(.easeInOut(duration: 0.15)) { showingReceiveToken = true } } label: {
                            Label("Receive", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AccentButtonStyle())
                    }
                    .padding(.horizontal, 10)

                    Divider()

                    // Chart (1:1 square)
                    GeometryReader { geo in
                        TradingViewChart(
                            symbol: token.token.symbol.tradingViewSymbol,
                            interval: "D",
                            theme: "dark"
                        )
                    }
                    .aspectRatio(1, contentMode: .fit)

                    Divider()

                    // Token info
                    VStack(spacing: 6) {
                        HStack {
                            Text("Contract")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if token.token.address != "0x0000000000000000000000000000000000000000" {
                                Text(token.token.address.prefix(8) + "..." + token.token.address.suffix(6))
                                    .font(.caption2.monospaced())
                            } else {
                                Text("Native")
                                    .font(.caption2)
                            }
                        }
                        HStack {
                            Text("Decimals")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(token.token.decimals)")
                                .font(.caption2.monospaced())
                        }
                        HStack {
                            Text("Chain")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(token.token.chainId == 1 ? "Ethereum" : "Chain \(token.token.chainId)")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 10)

                    Divider()

                    // Recent activity placeholder
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Activity")
                            .font(.caption.bold())
                        if let account = account {
                            TokenActivityView(token: token.token, address: account.address)
                        } else {
                            Text("No account selected")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Token Send Panel (Inline)

    @ViewBuilder
    private func tokenSendPanel(for token: TokenBalance) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) {
                    showingSendToken = false
                    tokenSendRecipient = ""
                    tokenSendAmount = ""
                    tokenSendError = nil
                    tokenSendSuccess = nil
                } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Send \(token.token.symbol)")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            if let success = tokenSendSuccess {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                    Text("Sent!")
                        .font(.headline)
                    Text(success)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingSendToken = false
                            tokenSendRecipient = ""
                            tokenSendAmount = ""
                            tokenSendError = nil
                            tokenSendSuccess = nil
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Recipient
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recipient")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("Address", text: $tokenSendRecipient)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 10)

                        // Amount
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack {
                                TextField("0.0", text: $tokenSendAmount)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption.monospaced())
                                Text(token.token.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 10)

                        // Balance
                        HStack {
                            Text("Balance")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(token.formattedBalance)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(AppColors.accent)
                            Text(token.token.symbol)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)

                        if let error = tokenSendError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                        }

                        // Send button
                        Button {
                            performTokenSend(token: token)
                        } label: {
                            if isTokenSending {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Send", systemImage: "arrow.up")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(tokenSendRecipient.isEmpty || tokenSendAmount.isEmpty || isTokenSending)
                        .padding(.horizontal, 10)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func performTokenSend(token: TokenBalance) {
        guard let account = account else { return }
        isTokenSending = true
        tokenSendError = nil

        Task {
            do {
                let privateKey = try await walletViewModel.getPrivateKey(for: account)
                let web3 = Web3Service()

                // Check if native ETH or ERC-20
                if token.token.address == "0x0000000000000000000000000000000000000000" {
                    // Native ETH - convert to Wei
                    guard let weiAmount = parseTokenAmount(tokenSendAmount, decimals: 18) else {
                        await MainActor.run {
                            isTokenSending = false
                            tokenSendError = "Invalid amount"
                        }
                        return
                    }

                    let transaction = try await web3.buildTransaction(
                        from: account.address,
                        to: tokenSendRecipient,
                        value: weiAmount
                    )
                    let txHash = try await web3.sendTransaction(transaction, privateKey: privateKey)

                    await MainActor.run {
                        isTokenSending = false
                        tokenSendSuccess = txHash
                    }
                } else {
                    // ERC-20 token transfer - convert decimal string to BigUInt
                    guard let amount = parseTokenAmount(tokenSendAmount, decimals: token.token.decimals) else {
                        await MainActor.run {
                            isTokenSending = false
                            tokenSendError = "Invalid amount"
                        }
                        return
                    }

                    let txHash = try await tokenService.transfer(
                        token: token.token,
                        to: tokenSendRecipient,
                        amount: amount,
                        from: account.address,
                        privateKey: privateKey
                    )
                    await MainActor.run {
                        isTokenSending = false
                        tokenSendSuccess = txHash
                    }
                }
            } catch {
                await MainActor.run {
                    isTokenSending = false
                    tokenSendError = error.localizedDescription
                }
            }
        }
    }

    private func parseTokenAmount(_ amount: String, decimals: Int) -> BigUInt? {
        let parts = amount.split(separator: ".")
        let integerPart = String(parts.first ?? "0")
        let fractionalPart = parts.count > 1 ? String(parts[1]) : ""

        // Pad or truncate fractional part to match decimals
        let paddedFractional = fractionalPart.padding(toLength: decimals, withPad: "0", startingAt: 0)
        let fullString = integerPart + paddedFractional.prefix(decimals)

        return BigUInt(fullString)
    }

    // MARK: - Token Receive Panel (Inline)

    @ViewBuilder
    private var tokenReceivePanel: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { showingReceiveToken = false } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Receive")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // QR Code
                    if let account = account {
                        tokenQRCodeImage(for: account.address)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                    }

                    // Address
                    VStack(spacing: 4) {
                        Text("Your Address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let address = account?.address {
                            Text(address)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)

                    // Copy button
                    Button {
                        copyTokenAddress()
                    } label: {
                        Label(tokenAddressCopied ? "Copied!" : "Copy Address", systemImage: tokenAddressCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    // Warning
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text("Only send ETH or EVM tokens to this address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func copyTokenAddress() {
        guard let address = account?.address else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #else
        UIPasteboard.general.string = address
        #endif

        withAnimation { tokenAddressCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { tokenAddressCopied = false }
        }
    }

    #if canImport(CoreImage)
    private func tokenQRCodeImage(for address: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(address.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return Image(systemName: "qrcode")
        }

        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return Image(systemName: "qrcode")
        }

        return Image(cgImage, scale: 1, label: Text("QR Code"))
    }
    #else
    private func tokenQRCodeImage(for address: String) -> Image {
        return Image(systemName: "qrcode")
    }
    #endif

    // MARK: - Token List

    @ViewBuilder
    private var tokenList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // ETH always first
                Button { withAnimation(.easeInOut(duration: 0.2)) { selectedToken = nativeTokenBalance } } label: {
                    TokenRow(balance: nativeTokenBalance)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 40)

                // Other tokens with balance
                ForEach(tokens.filter { $0.hasBalance }) { balance in
                    Button { withAnimation(.easeInOut(duration: 0.2)) { selectedToken = balance } } label: {
                        TokenRow(balance: balance)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 40)
                }

                // Show zero balances in a separate section
                let zeroBalances = tokens.filter { !$0.hasBalance }
                if !zeroBalances.isEmpty {
                    Section {
                        ForEach(zeroBalances) { balance in
                            Button { withAnimation(.easeInOut(duration: 0.2)) { selectedToken = balance } } label: {
                                TokenRow(balance: balance)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 40)
                        }
                    } header: {
                        Text("Zero Balances")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading tokens...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Tokens")
                .font(.headline)

            Text("Add a token to track its balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showingAddToken = true
            } label: {
                Label("Add Token", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(error)
                .foregroundStyle(.secondary)

            Button {
                Task { await loadTokens() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadTokens() async {
        guard let account = account else { return }

        isLoading = true
        error = nil

        // Load common tokens for the current network
        let balances = await tokenService.getCommonTokenBalances(
            for: account.address,
            chainId: 1  // TODO: Use actual selected network
        )

        await MainActor.run {
            self.tokens = balances
            self.isLoading = false
        }
    }
}

// MARK: - Token Row

struct TokenRow: View {
    let balance: TokenBalance

    var body: some View {
        HStack(spacing: 8) {
            // Token icon
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                Text(balance.token.symbol.prefix(2))
                    .font(.caption2.bold())
            }
            .frame(width: 32, height: 32)

            // Token info
            VStack(alignment: .leading, spacing: 1) {
                Text(balance.token.symbol)
                    .font(.caption.weight(.medium))
                Text(balance.token.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Balance
            VStack(alignment: .trailing, spacing: 1) {
                Text(balance.formattedBalance)
                    .font(.caption.monospacedDigit())
                if let usdValue = balance.usdValue {
                    Text("$\(usdValue, specifier: "%.2f")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Add Token Sheet

struct AddTokenSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var contractAddress = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var tokenInfo: Token?

    var body: some View {
        NavigationStack {
            Form {
                Section("Contract Address") {
                    TextField("0x...", text: $contractAddress)
                        .font(.body.monospaced())
                }

                if let token = tokenInfo {
                    Section("Token Info") {
                        LabeledContent("Name", value: token.name)
                        LabeledContent("Symbol", value: token.symbol)
                        LabeledContent("Decimals", value: String(token.decimals))
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Token")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        // Add token to tracked list
                        dismiss()
                    }
                    .disabled(tokenInfo == nil)
                }
            }
            .onChange(of: contractAddress) { _, newValue in
                if newValue.count == 42 {
                    Task { await lookupToken() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)
    }

    private func lookupToken() async {
        isLoading = true
        error = nil

        do {
            let info = try await TokenService.shared.getTokenInfo(
                address: contractAddress,
                chainId: 1
            )
            await MainActor.run {
                self.tokenInfo = info
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = "Failed to load token: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
}

// MARK: - Token Activity View

struct TokenActivityView: View {
    let token: Token
    let address: String

    @State private var transactions: [TxHistoryEntry] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 4) {
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if transactions.isEmpty {
                Text("No recent activity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(transactions.prefix(3)) { tx in
                    HStack {
                        Image(systemName: tx.isOutgoing ? "arrow.up.circle" : "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(tx.isOutgoing ? .red : .green)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(tx.isOutgoing ? "Sent" : "Received")
                                .font(.caption2)
                            Text(tx.shortTo)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(tx.formattedValue)
                            .font(.caption2.monospacedDigit())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            await loadActivity()
        }
    }

    private func loadActivity() async {
        do {
            let history = try await TransactionHistoryService.shared.getTransactionHistory(
                for: address,
                chainId: token.chainId,
                pageSize: 10
            )
            // Filter for this token if it's not ETH
            let filtered: [TxHistoryEntry]
            if token.address == "0x0000000000000000000000000000000000000000" {
                filtered = history.filter { $0.type == .send || $0.type == .receive }
            } else {
                filtered = history.filter {
                    $0.tokenSymbol?.lowercased() == token.symbol.lowercased()
                }
            }
            await MainActor.run {
                self.transactions = Array(filtered.prefix(5))
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

#Preview {
    TokensView(account: nil, ethBalance: "1.5", ethBalanceUSD: "$3,450.00")
}
