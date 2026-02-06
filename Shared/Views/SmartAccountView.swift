import SwiftUI

/// View for displaying smart account status and features
struct SmartAccountView: View {
    @ObservedObject var viewModel: SmartAccountViewModel
    let account: Account
    let onDeploy: () -> Void

    @State private var showingAPIKeySheet = false
    @State private var apiKeyInput = ""

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundStyle(.blue)

                Text("Smart Account")
                    .font(.headline)

                Spacer()

                statusBadge
            }

            Divider()

            if let smartAccount = viewModel.getSmartAccount(for: account) {
                // Smart account exists
                smartAccountDetails(smartAccount)
            } else if !viewModel.isBundlerAvailable {
                // No API key configured
                apiKeyPrompt
            } else {
                // No smart account yet
                noSmartAccountView
            }
        }
        .padding()
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        .sheet(isPresented: $showingAPIKeySheet) {
            apiKeySheet
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        Group {
            if let smartAccount = viewModel.getSmartAccount(for: account) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(smartAccount.isDeployed ? .green : .orange)
                        .frame(width: 8, height: 8)

                    Text(smartAccount.isDeployed ? "Active" : "Not Deployed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Smart Account Details

    @ViewBuilder
    private func smartAccountDetails(_ smartAccount: SmartAccount) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Address
            LabeledContent("Address") {
                HStack {
                    Text(smartAccount.shortAddress)
                        .font(.system(.body, design: .monospaced))

                    Button {
                        copyToClipboard(smartAccount.smartAccountAddress)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Balance
            LabeledContent("Balance") {
                VStack(alignment: .trailing) {
                    Text(viewModel.smartAccountBalance + " ETH")
                        .font(.system(.body, design: .monospaced))

                    Text(viewModel.smartAccountBalanceUSD)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Owner
            LabeledContent("Owner (EOA)") {
                Text(smartAccount.shortOwnerAddress)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Features
            Text("Features")
                .font(.subheadline)
                .fontWeight(.medium)

            ForEach(viewModel.availableFeatures, id: \.rawValue) { feature in
                featureRow(feature)
            }

            Divider()

            // Actions
            if !smartAccount.isDeployed {
                VStack(spacing: 8) {
                    Text("Your smart account will be deployed with your first transaction")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button("Deploy Now") {
                            onDeploy()
                        }
                        .buttonStyle(.bordered)

                        Button("Send First Tx") {
                            // This will trigger deployment
                            onDeploy()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            // Paymaster toggle
            Toggle(isOn: $viewModel.usePaymaster) {
                HStack {
                    Image(systemName: "gift")
                    Text("Gasless Transactions")
                }
            }
            .disabled(!viewModel.isPaymasterAvailable)

            if viewModel.usePaymaster {
                Picker("Paymaster", selection: $viewModel.paymasterMode) {
                    ForEach(PaymasterMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Feature Row

    private func featureRow(_ feature: SmartAccountFeature) -> some View {
        HStack {
            Image(systemName: feature.iconName)
                .foregroundStyle(feature.isAvailable ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.subheadline)

                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if feature.isAvailable {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - No Smart Account View

    private var noSmartAccountView: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No Smart Account")
                .font(.headline)

            Text("Upgrade to a smart account to access advanced features like batch transactions and gasless transactions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Create Smart Account") {
                Task {
                    try? await viewModel.createSmartAccount(for: account)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - API Key Prompt

    private var apiKeyPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("API Key Required")
                .font(.headline)

            Text("Smart accounts require a Pimlico API key. Get a free key at pimlico.io")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Add API Key") {
                showingAPIKeySheet = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - API Key Sheet

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pimlico API Key", text: $apiKeyInput)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Get a free API key at pimlico.io")
                }

                Section {
                    Link(destination: URL(string: "https://dashboard.pimlico.io")!) {
                        HStack {
                            Text("Get API Key")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            .navigationTitle("Pimlico Setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAPIKeySheet = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(apiKeyInput.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    private func saveAPIKey() {
        do {
            try viewModel.setPimlicoAPIKey(apiKeyInput)
            showingAPIKeySheet = false
            apiKeyInput = ""
        } catch {
            // Handle error
        }
    }
}

// MARK: - Compact Smart Account Badge

/// A compact badge showing smart account status
struct SmartAccountBadge: View {
    let smartAccount: SmartAccount?

    var body: some View {
        if let smartAccount = smartAccount {
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.caption2)

                Text(smartAccount.isDeployed ? "Smart" : "Pending")
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(smartAccount.isDeployed ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundStyle(smartAccount.isDeployed ? .blue : .orange)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    SmartAccountView(
        viewModel: SmartAccountViewModel(),
        account: Account(index: 0, address: "0x1234567890123456789012345678901234567890"),
        onDeploy: {}
    )
    .padding()
}
