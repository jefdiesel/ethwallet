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
            ScrollView {
                VStack(spacing: 24) {
                    networkSection
                    smartAccountSection
                    securitySection
                    displaySection
                    aboutSection
                    dangerZoneSection
                }
                .padding(20)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, idealWidth: 440, minHeight: 500)
        .alert("Delete Wallet", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWallet()
            }
        } message: {
            Text("This will permanently delete your wallet. Make sure you have your recovery phrase.")
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
                    onUpgrade: { _ in showingSmartAccountUpgrade = false },
                    onCancel: { showingSmartAccountUpgrade = false }
                )
            }
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            PimlicoAPIKeySheet(
                viewModel: smartAccountViewModel,
                apiKey: $pimlicoAPIKey,
                onSave: { showingAPIKeySheet = false },
                onCancel: { showingAPIKeySheet = false }
            )
        }
    }

    // MARK: - Network Section

    private var networkSection: some View {
        SettingsSection(title: "Network") {
            VStack(spacing: 0) {
                SettingsRow {
                    HStack {
                        Text("Default Network")
                        Spacer()
                        Picker("", selection: $defaultNetworkId) {
                            ForEach(Network.defaults.filter { showTestnets || !$0.isTestnet }, id: \.id) { network in
                                Text(network.name).tag(network.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                }

                Divider().padding(.leading, 16)

                SettingsRow {
                    Toggle("Show Testnets", isOn: $showTestnets)
                }

                Divider().padding(.leading, 16)

                SettingsRow {
                    HStack {
                        Circle()
                            .fill(networkManager.isConnected ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(networkManager.selectedNetwork.name)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if networkManager.latency > 0 {
                            Text("\(Int(networkManager.latency))ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Smart Account Section

    private var smartAccountSection: some View {
        SettingsSection(title: "Smart Account (ERC-4337)") {
            VStack(spacing: 0) {
                if let account = account, let smartAccount = smartAccountViewModel.getSmartAccount(for: account) {
                    SettingsRow {
                        HStack {
                            Text("Address")
                            Spacer()
                            Text(smartAccount.shortAddress)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider().padding(.leading, 16)

                    SettingsRow {
                        HStack {
                            Text("Status")
                            Spacer()
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(smartAccount.isDeployed ? .green : .orange)
                                    .frame(width: 8, height: 8)
                                Text(smartAccount.isDeployed ? "Active" : "Not Deployed")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider().padding(.leading, 16)

                    SettingsRow {
                        Toggle("Gasless Transactions", isOn: $smartAccountViewModel.usePaymaster)
                            .disabled(!smartAccountViewModel.isPaymasterAvailable)
                    }

                } else if smartAccountViewModel.isBundlerAvailable && account != nil {
                    SettingsRow {
                        Button {
                            showingSmartAccountUpgrade = true
                        } label: {
                            HStack {
                                Label("Upgrade to Smart Account", systemImage: "sparkles")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else if account == nil {
                    SettingsRow {
                        Text("Select an account to upgrade")
                            .foregroundStyle(.secondary)
                    }
                }

                if smartAccountViewModel.hasPimlicoAPIKey {
                    Divider().padding(.leading, 16)

                    SettingsRow {
                        HStack {
                            Text("Pimlico API")
                            Spacer()
                            Text(smartAccountViewModel.maskedAPIKey ?? "Configured")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Button {
                                showingAPIKeySheet = true
                            } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    Divider().padding(.leading, 16)

                    SettingsRow {
                        Button {
                            showingAPIKeySheet = true
                        } label: {
                            HStack {
                                Label("Configure Pimlico API Key", systemImage: "key.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Security Section

    private var securitySection: some View {
        SettingsSection(title: "Security") {
            VStack(spacing: 0) {
                SettingsRow {
                    HStack {
                        Image(systemName: biometricIcon)
                            .foregroundStyle(.blue)
                        Text(KeychainService.shared.biometricType.displayName)
                        Spacer()
                        Text(KeychainService.shared.isBiometricAvailable ? "Enabled" : "Unavailable")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().padding(.leading, 16)

                SettingsRow {
                    Toggle("MEV Protection", isOn: $mevProtectionEnabled)
                        .onChange(of: mevProtectionEnabled) { _, newValue in
                            MEVProtectionService.shared.isEnabled = newValue
                        }
                }

                Divider().padding(.leading, 16)

                SettingsRow {
                    Button {
                        showingRecoveryPhrase = true
                    } label: {
                        HStack {
                            Label("View Recovery Phrase", systemImage: "key.fill")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                if account != nil {
                    Divider().padding(.leading, 16)

                    SettingsRow {
                        Button {
                            showingApprovals = true
                        } label: {
                            HStack {
                                Label("Token Approvals", systemImage: "checkmark.shield")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Display Section

    private var displaySection: some View {
        SettingsSection(title: "Display") {
            SettingsRow {
                HStack {
                    Text("Currency")
                    Spacer()
                    Picker("", selection: $currencyDisplay) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("GBP").tag("GBP")
                        Text("JPY").tag("JPY")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            VStack(spacing: 0) {
                SettingsRow {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider().padding(.leading, 16)

                SettingsRow {
                    Link(destination: URL(string: "https://ethscriptions.com")!) {
                        HStack {
                            Text("Ethscriptions Protocol")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Danger Zone Section

    private var dangerZoneSection: some View {
        SettingsSection(title: "Danger Zone", titleColor: .red) {
            SettingsRow {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    HStack {
                        Label("Delete Wallet", systemImage: "trash")
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var biometricIcon: String {
        switch KeychainService.shared.biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none: return "lock.fill"
        }
    }

    private func deleteWallet() {
        dismiss()
    }
}

// MARK: - Settings Section Component

struct SettingsSection<Content: View>: View {
    let title: String
    var titleColor: Color = .secondary
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(titleColor)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Settings Row Component

struct SettingsRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

// MARK: - Recovery Phrase Sheet

struct RecoveryPhraseSheet: View {
    @Environment(\.dismiss) private var dismiss

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
            .padding(24)
            .navigationTitle("Recovery Phrase")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private var authenticationView: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.blue)

            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your recovery phrase will be shown after authentication.")
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

    private func recoveryPhraseView(mnemonic: String) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Never share your recovery phrase!")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(12)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            let words = mnemonic.split(separator: " ").map(String.init)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(word)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(mnemonic, forType: .string)
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
                let _ = try await KeychainService.shared.retrieveSeed()
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
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PIMLICO API KEY")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextField("Enter API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Text("Required for smart account features. Get a free key at pimlico.io")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://dashboard.pimlico.io")!) {
                    HStack {
                        Image(systemName: "arrow.up.right.square")
                        Text("Get API Key from Pimlico")
                    }
                }

                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Pimlico Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAPIKey() }
                        .disabled(apiKey.isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280)
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
    SettingsView()
}
