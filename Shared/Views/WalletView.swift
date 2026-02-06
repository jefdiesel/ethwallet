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
            SettingsView(account: viewModel.selectedAccount)
        }
    }

    // MARK: - Wallet Content

    @ViewBuilder
    private var walletContent: some View {
        VStack(spacing: 0) {
            // Header row 1: Account and Network
            HStack(spacing: 6) {
                AccountSwitcher(
                    accounts: viewModel.wallet?.accounts ?? [],
                    selectedAccount: $viewModel.selectedAccount
                )
                Spacer()
                NetworkSwitcher(selectedNetwork: $viewModel.selectedNetwork)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Header row 2: Total Holdings + Actions
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total Holdings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.balanceUSD)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(AppColors.accent)
                }

                Spacer()

                Button { showingSend = true } label: {
                    Label("Send", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AccentButtonStyle())

                Button { showingReceive = true } label: {
                    Label("Receive", systemImage: "arrow.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Tab picker
            Picker("", selection: $selectedTab) {
                Text("Tokens").tag(WalletTab.tokens)
                Text("NFTs").tag(WalletTab.nfts)
                Text("Etch").tag(WalletTab.ethscriptions)
                Text("WC").tag(WalletTab.connect)
                Text("Web").tag(WalletTab.browser)
                Text("Tx").tag(WalletTab.history)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            Divider()

            // Content based on selection
            switch selectedTab {
            case .tokens:
                TokensView(account: viewModel.selectedAccount, ethBalance: viewModel.balance, ethBalanceUSD: viewModel.balanceUSD)
            case .nfts:
                NFTsView(account: viewModel.selectedAccount)
            case .ethscriptions:
                EthscriptionsView(account: viewModel.selectedAccount)
                    .environmentObject(viewModel)
            case .connect:
                WalletConnectView()
                    .environmentObject(viewModel)
            case .browser:
                BrowserView()
                    .environmentObject(viewModel)
            case .history:
                if let account = viewModel.selectedAccount {
                    TransactionHistoryView(
                        address: account.address,
                        chainId: viewModel.selectedNetwork.id
                    )
                }
            }
        }
    }

    // MARK: - Balance Section

    @ViewBuilder
    private var balanceSection: some View {
        VStack(spacing: 2) {
            Text("Total Balance")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.balanceUSD)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                showingSend = true
            } label: {
                Label("Send", systemImage: "arrow.up")
            }
            .buttonStyle(.primary)

            Button {
                showingReceive = true
            } label: {
                Label("Receive", systemImage: "arrow.down")
            }
            .buttonStyle(.secondary)

            Button {
                Task { await viewModel.refreshBalance() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
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
        VStack(spacing: 12) {
            ProgressView()

            Text("Loading...")
                .font(.subheadline)
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
                    .frame(maxWidth: 160)
            }
            .buttonStyle(.primary)
        }
        .padding()
    }

    // MARK: - Onboarding View

    @ViewBuilder
    private var onboardingView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to EthWallet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a new wallet or import an existing one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    showingCreateWallet = true
                } label: {
                    Text("Create New Wallet")
                        .frame(width: 160)
                }
                .buttonStyle(.primary)
                .disabled(viewModel.isLoading)

                Button {
                    showingImportWallet = true
                } label: {
                    Text("Import Wallet")
                        .frame(width: 160)
                }
                .buttonStyle(.secondary)
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
        .frame(minWidth: 320, minHeight: 380)
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
            .buttonStyle(.primary)
            .disabled(isCreating)
        }
    }

    @ViewBuilder
    private func backupView(mnemonic: String) -> some View {
        VStack(spacing: 16) {
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
            .buttonStyle(.primary)
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
        .frame(minWidth: 320, minHeight: 320)
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
            .buttonStyle(.primary)
            .disabled(mnemonicInput.isEmpty || isImporting)
        }
    }

    @ViewBuilder
    private var privateKeyImportView: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            .buttonStyle(.primary)
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

#Preview {
    WalletView()
        .environmentObject(WalletViewModel())
}
