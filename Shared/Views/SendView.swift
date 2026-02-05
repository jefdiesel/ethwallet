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
                }

                // Amount (for ETH)
                if viewModel.selectedAsset == .eth {
                    Section("Amount") {
                        HStack {
                            TextField("0.0", text: $viewModel.amount)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                #if os(iOS)
                                .keyboardType(.decimalPad)
                                #endif

                            Text("ETH")
                                .foregroundStyle(.secondary)

                            Button("Max") {
                                viewModel.setMaxAmount()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if !viewModel.amount.isEmpty {
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
                            EthscriptionRow(ethscription: ethscription)
                        } else {
                            NavigationLink {
                                EthscriptionPickerView(
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
            .formStyle(.grouped)
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
        .frame(minWidth: 400, minHeight: 500)
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
                HStack(spacing: 16) {
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
                            Text("Confirm & Send")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isSending)
                }
            }
            .padding()
            .navigationTitle("Confirm Transaction")
        }
        .frame(minWidth: 350, minHeight: 450)
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
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Transaction Sent")
                .font(.title)
                .fontWeight(.semibold)

            VStack(spacing: 4) {
                Text("Transaction Hash")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(txHash)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            if let explorerURL = networkManager.selectedNetwork.explorerTransactionURL(txHash) {
                Link(destination: explorerURL) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                }
            }

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(minWidth: 350, minHeight: 350)
    }
}

// MARK: - Ethscription Picker View

struct EthscriptionPickerView: View {
    @Binding var selectedEthscription: Ethscription?
    @Environment(\.dismiss) private var dismiss

    // Placeholder - would load from CollectionViewModel
    let ethscriptions: [Ethscription] = []

    var body: some View {
        List(ethscriptions) { ethscription in
            Button {
                selectedEthscription = ethscription
                dismiss()
            } label: {
                EthscriptionRow(ethscription: ethscription)
            }
        }
        .navigationTitle("Select Ethscription")
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

#Preview {
    SendView(account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"))
}
