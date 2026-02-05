import SwiftUI

/// Main wallet dashboard view
struct WalletView: View {
    @EnvironmentObject var viewModel: WalletViewModel
    @State private var showingCreateWallet = false
    @State private var showingImportWallet = false
    @State private var showingSend = false
    @State private var showingReceive = false
    @State private var showingSettings = false
    @State private var selectedTab: WalletTab = .tokens

    enum WalletTab: Hashable {
        case tokens, nfts, ethscriptions, connect, browser, history
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.wallet != nil {
                    walletContent
                } else if viewModel.hasWallet && viewModel.wallet == nil {
                    // Wallet exists but not loaded (auth failed/canceled)
                    authRetryView
                } else {
                    onboardingView
                }
            }
            .navigationTitle(selectedTab == .browser ? "" : "EthWallet")
            #if os(macOS)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if viewModel.hasWallet {
                        toolbarItems
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showingCreateWallet) {
            CreateWalletSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingImportWallet) {
            ImportWalletSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSend) {
            SendView(account: viewModel.selectedAccount)
        }
        .sheet(isPresented: $showingReceive) {
            ReceiveView(account: viewModel.selectedAccount)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }

    // MARK: - Wallet Content

    @ViewBuilder
    private var walletContent: some View {
        VStack(spacing: 0) {
            if selectedTab != .browser {
                // Account & Network selectors
                HStack {
                    AccountSwitcher(
                        accounts: viewModel.wallet?.accounts ?? [],
                        selectedAccount: $viewModel.selectedAccount
                    )

                    Spacer()

                    NetworkSwitcher(selectedNetwork: $viewModel.selectedNetwork)
                }
                .padding()

                Divider()

                // Balance display
                balanceSection
                    .padding()

                // Action buttons
                actionButtons
                    .padding()

                Divider()
            }

            // Tab view for different sections
            TabView(selection: $selectedTab) {
                TokensView(account: viewModel.selectedAccount, ethBalance: viewModel.balance, ethBalanceUSD: viewModel.balanceUSD)
                    .tabItem {
                        Label("Tokens", systemImage: "dollarsign.circle")
                    }
                    .tag(WalletTab.tokens)

                NFTsView(account: viewModel.selectedAccount)
                    .tabItem {
                        Label("NFTs", systemImage: "square.stack.3d.up")
                    }
                    .tag(WalletTab.nfts)

                EthscriptionsView(account: viewModel.selectedAccount)
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Ethscriptions", systemImage: "photo.on.rectangle")
                    }
                    .tag(WalletTab.ethscriptions)

                WalletConnectView()
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Connect", systemImage: "link")
                    }
                    .tag(WalletTab.connect)

                BrowserView()
                    .environmentObject(viewModel)
                    .tabItem {
                        Label("Browser", systemImage: "globe")
                    }
                    .tag(WalletTab.browser)

                TransactionHistoryView()
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(WalletTab.history)
            }
        }
    }

    // MARK: - Balance Section

    @ViewBuilder
    private var balanceSection: some View {
        VStack(spacing: 4) {
            Text("Total Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(viewModel.balanceUSD)
                .font(.system(size: 48, weight: .medium))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 20) {
            Button {
                showingSend = true
            } label: {
                Label("Send", systemImage: "arrow.up.circle.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                showingReceive = true
            } label: {
                Label("Receive", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await viewModel.refreshBalance() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Toolbar Items

    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gear")
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Loading Wallet...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Auth Retry View

    @ViewBuilder
    private var authRetryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Unlock your wallet to continue")
                .font(.body)
                .foregroundStyle(.secondary)

            if let error = viewModel.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Button {
                Task { await viewModel.loadWallet() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    // MARK: - Onboarding View

    @ViewBuilder
    private var onboardingView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            Text("Welcome to EthWallet")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Create a new wallet or import an existing one to get started.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 16) {
                Button {
                    showingCreateWallet = true
                } label: {
                    Text("Create New Wallet")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isLoading)

                Button {
                    showingImportWallet = true
                } label: {
                    Text("Import Existing Wallet")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(viewModel.isLoading)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Create Wallet Sheet

struct CreateWalletSheet: View {
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var wordCount: MnemonicWordCount = .twelve
    @State private var generatedMnemonic: String?
    @State private var hasConfirmedBackup = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let mnemonic = generatedMnemonic {
                    backupView(mnemonic: mnemonic)
                } else {
                    createOptionsView
                }
            }
            .padding()
            .navigationTitle("Create Wallet")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    @ViewBuilder
    private var createOptionsView: some View {
        VStack(spacing: 24) {
            Text("Choose the security level for your wallet")
                .font(.headline)

            Picker("Word Count", selection: $wordCount) {
                Text("12 Words (Standard)").tag(MnemonicWordCount.twelve)
                Text("24 Words (Enhanced)").tag(MnemonicWordCount.twentyFour)
            }
            .pickerStyle(.segmented)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                createWallet()
            } label: {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Generate Wallet")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCreating)
        }
    }

    @ViewBuilder
    private func backupView(mnemonic: String) -> some View {
        VStack(spacing: 24) {
            Text("Backup Your Recovery Phrase")
                .font(.headline)

            Text("Write down these words in order and store them safely. You will need them to recover your wallet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Display mnemonic words in grid
            let words = mnemonic.split(separator: " ").map(String.init)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(word)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Toggle("I have safely backed up my recovery phrase", isOn: $hasConfirmedBackup)

            Button("Continue") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasConfirmedBackup)
        }
    }

    private func createWallet() {
        isCreating = true
        error = nil

        Task {
            do {
                let mnemonic = try await viewModel.createWallet(wordCount: wordCount)
                await MainActor.run {
                    self.generatedMnemonic = mnemonic
                    self.isCreating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isCreating = false
                }
            }
        }
    }
}

// MARK: - Import Wallet Sheet

struct ImportWalletSheet: View {
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var importMethod: ImportMethod = .mnemonic
    @State private var mnemonicInput: String = ""
    @State private var privateKeyInput: String = ""
    @State private var isImporting = false
    @State private var error: String?

    enum ImportMethod: String, CaseIterable {
        case mnemonic = "Recovery Phrase"
        case privateKey = "Private Key"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Import Method", selection: $importMethod) {
                    ForEach(ImportMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch importMethod {
                case .mnemonic:
                    mnemonicImportView
                case .privateKey:
                    privateKeyImportView
                }

                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Wallet")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    @ViewBuilder
    private var mnemonicImportView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your 12 or 24 word recovery phrase")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $mnemonicInput)
                .font(.body.monospaced())
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            Button {
                importMnemonic()
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Import Wallet")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(mnemonicInput.isEmpty || isImporting)
        }
    }

    @ViewBuilder
    private var privateKeyImportView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your private key (with or without 0x prefix)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Private Key", text: $privateKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            Button {
                importPrivateKey()
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Import Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(privateKeyInput.isEmpty || isImporting)
        }
    }

    private func importMnemonic() {
        isImporting = true
        error = nil

        Task {
            do {
                try await viewModel.importWallet(mnemonic: mnemonicInput.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isImporting = false
                }
            }
        }
    }

    private func importPrivateKey() {
        isImporting = true
        error = nil

        Task {
            do {
                try await viewModel.importFromPrivateKey(privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isImporting = false
                }
            }
        }
    }
}

// MARK: - Transaction History View (Placeholder)

struct TransactionHistoryView: View {
    var body: some View {
        VStack {
            Text("Transaction History")
                .font(.headline)
            Text("Coming soon...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    WalletView()
        .environmentObject(WalletViewModel())
}
