import SwiftUI

/// Settings view for wallet configuration
struct SettingsView: View {
    var account: Account? = nil
    @ObservedObject var smartAccountViewModel: SmartAccountViewModel = SmartAccountViewModel()

    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkManager = NetworkManager.shared

    @State private var showingDeleteConfirmation = false
    @State private var showingExportWarning = false
    @State private var showingRecoveryPhrase = false
    @State private var showingApprovals = false
    @State private var showingSmartAccountUpgrade = false
    @State private var showingAPIKeySheet = false
    @State private var pimlicoAPIKey = ""

    @AppStorage("showTestnets") private var showTestnets = true
    @AppStorage("defaultNetwork") private var defaultNetworkId = 1
    @AppStorage("currencyDisplay") private var currencyDisplay = "USD"
    @AppStorage("mevProtectionEnabled") private var mevProtectionEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                // Network Settings
                networkSection

                // Smart Account Settings
                smartAccountSection

                // Transaction Protection
                transactionProtectionSection

                // Security Settings
                securitySection

                // Display Settings
                displaySection

                // About
                aboutSection

                // Danger Zone
                dangerZoneSection
            }
            .formStyle(.automatic)
            .navigationTitle("Settings")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 340, minHeight: 400)
        .alert("Delete Wallet", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWallet()
            }
        } message: {
            Text("This will permanently delete your wallet from this device. Make sure you have backed up your recovery phrase before proceeding.")
        }
        .sheet(isPresented: $showingRecoveryPhrase) {
            RecoveryPhraseSheet()
        }
        .sheet(isPresented: $showingApprovals) {
            if let account = account {
                ApprovalsView(account: account, chainId: networkManager.selectedNetwork.id)
            }
        }
        .sheet(isPresented: $showingSmartAccountUpgrade) {
            if let account = account {
                AccountUpgradeView(
                    viewModel: smartAccountViewModel,
                    account: account,
                    onUpgrade: { _ in
                        showingSmartAccountUpgrade = false
                    },
                    onCancel: {
                        showingSmartAccountUpgrade = false
                    }
                )
            }
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            PimlicoAPIKeySheet(
                viewModel: smartAccountViewModel,
                apiKey: $pimlicoAPIKey,
                onSave: {
                    showingAPIKeySheet = false
                },
                onCancel: {
                    showingAPIKeySheet = false
                }
            )
        }
    }

    // MARK: - Network Section

    @ViewBuilder
    private var networkSection: some View {
        Section("Networks") {
            // Default network picker
            Picker("Default Network", selection: $defaultNetworkId) {
                ForEach(Network.defaults.filter { showTestnets || !$0.isTestnet }, id: \.id) { network in
                    Text(network.name).tag(network.id)
                }
            }

            // Show testnets toggle
            Toggle("Show Testnets", isOn: $showTestnets)

            // Network status
            NetworkStatusView()
        }
    }

    // MARK: - Smart Account Section

    @ViewBuilder
    private var smartAccountSection: some View {
        Section {
            if let account = account {
                if let smartAccount = smartAccountViewModel.getSmartAccount(for: account) {
                    // Smart account exists
                    LabeledContent("Address") {
                        Text(smartAccount.shortAddress)
                            .font(.system(.caption, design: .monospaced))
                    }

                    LabeledContent("Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(smartAccount.isDeployed ? .green : .orange)
                                .frame(width: 8, height: 8)
                            Text(smartAccount.isDeployed ? "Active" : "Not Deployed")
                        }
                    }

                    Toggle("Use Paymaster (Gasless)", isOn: $smartAccountViewModel.usePaymaster)
                        .disabled(!smartAccountViewModel.isPaymasterAvailable)

                } else if smartAccountViewModel.isBundlerAvailable {
                    // Can upgrade to smart account
                    Button {
                        showingSmartAccountUpgrade = true
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                            Text("Upgrade to Smart Account")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    // Need to configure API key
                    Button {
                        showingAPIKeySheet = true
                    } label: {
                        HStack {
                            Image(systemName: "key.fill")
                            Text("Configure Pimlico API Key")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // API key status
            if smartAccountViewModel.hasPimlicoAPIKey {
                LabeledContent("Pimlico API Key") {
                    HStack {
                        Text(smartAccountViewModel.maskedAPIKey ?? "")
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            showingAPIKeySheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

        } header: {
            Text("Smart Account (ERC-4337)")
        } footer: {
            Text("Smart accounts enable batch transactions, gasless transactions, and enhanced security features.")
        }
    }

    // MARK: - Transaction Protection Section

    @ViewBuilder
    private var transactionProtectionSection: some View {
        Section {
            Toggle("MEV Protection", isOn: $mevProtectionEnabled)
                .onChange(of: mevProtectionEnabled) { _, newValue in
                    MEVProtectionService.shared.isEnabled = newValue
                }
        } header: {
            Text("Transaction Protection")
        } footer: {
            Text("Routes Ethereum mainnet transactions through Flashbots to prevent front-running and sandwich attacks. Recommended for swaps and large transactions.")
        }
    }

    // MARK: - Security Section

    @ViewBuilder
    private var securitySection: some View {
        Section("Security") {
            // Biometric info
            HStack {
                Image(systemName: biometricIcon)
                Text(KeychainService.shared.biometricType.displayName)
                Spacer()
                Text(KeychainService.shared.isBiometricAvailable ? "Available" : "Unavailable")
                    .foregroundStyle(.secondary)
            }

            // Token approvals
            if let account = account {
                Button {
                    showingApprovals = true
                } label: {
                    ApprovalSummaryRow(account: account, chainId: networkManager.selectedNetwork.id)
                }
                .buttonStyle(.plain)
            }

            // View recovery phrase
            Button {
                showingRecoveryPhrase = true
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text("View Recovery Phrase")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Display Section

    @ViewBuilder
    private var displaySection: some View {
        Section("Display") {
            // Currency display
            Picker("Currency", selection: $currencyDisplay) {
                Text("USD").tag("USD")
                Text("EUR").tag("EUR")
                Text("GBP").tag("GBP")
                Text("JPY").tag("JPY")
            }
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://ethscriptions.com")!) {
                HStack {
                    Text("Ethscriptions Protocol")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }

            Link(destination: URL(string: "https://explorer.ethscriptions.com")!) {
                HStack {
                    Text("Ethscriptions Explorer")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Danger Zone Section

    @ViewBuilder
    private var dangerZoneSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Wallet")
                }
            }
        } header: {
            Text("Danger Zone")
        } footer: {
            Text("Deleting your wallet will remove all data from this device. You can recover your wallet using your recovery phrase.")
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        switch KeychainService.shared.biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none:
            return "lock.fill"
        }
    }

    private func deleteWallet() {
        // This would call the wallet view model to delete the wallet
        dismiss()
    }
}

// MARK: - Recovery Phrase Sheet

struct RecoveryPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isAuthenticated = false
    @State private var mnemonic: String?
    @State private var error: String?
    @State private var isAuthenticating = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let mnemonic = mnemonic {
                    recoveryPhraseView(mnemonic: mnemonic)
                } else {
                    authenticationView
                }
            }
            .padding()
            .navigationTitle("Recovery Phrase")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 320, minHeight: 380)
    }

    @ViewBuilder
    private var authenticationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your recovery phrase will be shown after authentication. Make sure no one is watching your screen.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                authenticate()
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Show Recovery Phrase")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAuthenticating)
        }
    }

    @ViewBuilder
    private func recoveryPhraseView(mnemonic: String) -> some View {
        VStack(spacing: 24) {
            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Never share your recovery phrase with anyone!")
                    .font(.subheadline)
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .cornerRadius(8)

            // Words grid
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

            // Copy button
            Button {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mnemonic, forType: .string)
                #else
                UIPasteboard.general.string = mnemonic
                #endif
            } label: {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
        }
    }

    private func authenticate() {
        isAuthenticating = true
        error = nil

        Task {
            do {
                // This would actually retrieve the mnemonic from the seed
                // For now, show a placeholder
                let seed = try await KeychainService.shared.retrieveSeed()
                // In production, you'd convert seed back to mnemonic
                // This is a placeholder
                await MainActor.run {
                    self.mnemonic = "word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12"
                    self.isAuthenticating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isAuthenticating = false
                }
            }
        }
    }
}

// MARK: - Pimlico API Key Sheet

struct PimlicoAPIKeySheet: View {
    @ObservedObject var viewModel: SmartAccountViewModel
    @Binding var apiKey: String

    var onSave: () -> Void
    var onCancel: () -> Void

    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("API Key", text: $apiKey)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                } header: {
                    Text("Pimlico API Key")
                } footer: {
                    Text("Required for smart account features. Get a free key at pimlico.io")
                }

                Section {
                    Link(destination: URL(string: "https://dashboard.pimlico.io")!) {
                        HStack {
                            Image(systemName: "arrow.up.right.square")
                            Text("Get API Key from Pimlico")
                        }
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Pimlico Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 300)
    }

    private func saveAPIKey() {
        do {
            try viewModel.setPimlicoAPIKey(apiKey)
            apiKey = ""
            onSave()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    SettingsView(smartAccountViewModel: SmartAccountViewModel())
}
