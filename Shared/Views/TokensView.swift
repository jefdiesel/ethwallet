import SwiftUI

/// View displaying ERC-20 token balances
struct TokensView: View {
    let account: Account?
    let ethBalance: String
    let ethBalanceUSD: String

    @State private var tokens: [TokenBalance] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var showingAddToken = false

    private let tokenService = TokenService.shared

    /// ETH displayed as a token
    private var ethTokenBalance: TokenBalance {
        let eth = Token(
            address: "0x0000000000000000000000000000000000000000",
            symbol: "ETH",
            name: "Ethereum",
            decimals: 18,
            logoURL: nil,
            chainId: 1
        )
        let usdValue = Double(ethBalanceUSD.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""))
        return TokenBalance(
            token: eth,
            rawBalance: ethBalance,
            formattedBalance: ethBalance,
            usdValue: usdValue
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tokens")
                    .font(.headline)

                Spacer()

                Button {
                    showingAddToken = true
                } label: {
                    Image(systemName: "plus")
                }

                Button {
                    Task { await loadTokens() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else {
                // Always show token list (ETH is always present)
                tokenList
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

    // MARK: - Token List

    @ViewBuilder
    private var tokenList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // ETH always first
                TokenRow(balance: ethTokenBalance)
                Divider()
                    .padding(.leading, 56)

                // Other tokens with balance
                ForEach(tokens.filter { $0.hasBalance }) { balance in
                    TokenRow(balance: balance)
                    Divider()
                        .padding(.leading, 56)
                }

                // Show zero balances in a separate section
                let zeroBalances = tokens.filter { !$0.hasBalance }
                if !zeroBalances.isEmpty {
                    Section {
                        ForEach(zeroBalances) { balance in
                            TokenRow(balance: balance)
                            Divider()
                                .padding(.leading, 56)
                        }
                    } header: {
                        Text("Zero Balances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.top, 16)
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
        HStack(spacing: 12) {
            // Token icon
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))

                Text(balance.token.symbol.prefix(2))
                    .font(.caption.bold())
            }
            .frame(width: 40, height: 40)

            // Token info
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.token.symbol)
                    .font(.body.weight(.medium))

                Text(balance.token.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                Text(balance.formattedBalance)
                    .font(.body.monospacedDigit())

                if let usdValue = balance.usdValue {
                    Text("$\(usdValue, specifier: "%.2f")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
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
        .frame(minWidth: 400, minHeight: 300)
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

#Preview {
    TokensView(account: nil, ethBalance: "1.5", ethBalanceUSD: "$3,450.00")
}
