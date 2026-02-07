import SwiftUI
import UniformTypeIdentifiers

/// View for creating new ethscriptions
struct CreateEthscriptionView: View {
    let account: Account?
    var smartAccount: SmartAccount? = nil
    var isSmartAccountEnabled: Bool = false

    @StateObject private var viewModel = CreateViewModel()
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkManager = NetworkManager.shared

    @State private var showingFilePicker = false
    @State private var showingConfirmation = false
    @State private var showingSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                // Content type selector
                Section {
                    Picker("Content Type", selection: $viewModel.contentType) {
                        ForEach(ContentInputType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // From account selector (if smart account available)
                if isSmartAccountEnabled && viewModel.canUseSmartAccount {
                    fromAccountSection
                }

                // Content input
                contentSection

                // Recipient
                recipientSection

                // Options
                optionsSection

                // Size & gas info
                infoSection

                // Error display
                if let error = viewModel.createError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.automatic)
            .navigationTitle("Create Ethscription")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Review") {
                        showingConfirmation = true
                    }
                    .disabled(!viewModel.canCreate)
                }
            }
            #endif
        }
        .frame(minWidth: 360, minHeight: 480)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: supportedFileTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingConfirmation) {
            CreateConfirmationSheet(viewModel: viewModel) {
                showingSuccess = true
            }
        }
        .sheet(isPresented: $showingSuccess) {
            CreateSuccessSheet(
                txHash: viewModel.lastTransactionHash ?? viewModel.userOperationHash ?? "",
                isUserOperation: viewModel.userOperationHash != nil,
                onDone: {
                    viewModel.reset()
                    dismiss()
                }
            )
        }
        .onAppear {
            if let account = account {
                viewModel.configure(account: account)

                if isSmartAccountEnabled, let smartAccount = smartAccount {
                    viewModel.configureSmartAccount(smartAccount: smartAccount)
                    viewModel.useSmartAccount = true
                    viewModel.usePaymaster = true
                }
            }
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        Section("Content") {
            switch viewModel.contentType {
            case .text:
                TextEditor(text: $viewModel.textContent)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)

            case .file:
                if let url = viewModel.selectedFileURL {
                    HStack {
                        Image(systemName: fileIcon(for: viewModel.fileMimeType))
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                                .fontWeight(.medium)
                            Text(viewModel.fileMimeType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Change") {
                            showingFilePicker = true
                        }
                    }
                } else {
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Select File")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)
                }
            }

            // Size indicator
            HStack {
                Text("Size: \(viewModel.formattedContentSize)")
                    .font(.caption)
                    .foregroundColor(viewModel.isWithinSizeLimit ? .secondary : .red)

                Spacer()

                Text("Max: 90 KB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.contentError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(
                        viewModel.validationResult?.errors.isEmpty == true ? .orange : .red
                    )
            }
        }
    }

    // MARK: - Recipient Section

    @ViewBuilder
    private var recipientSection: some View {
        Section("Recipient") {
            Toggle("Inscribe to my address", isOn: $viewModel.inscribeToSelf)

            if !viewModel.inscribeToSelf {
                TextField("Recipient Address (0x...)", text: $viewModel.recipientAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                if let error = viewModel.recipientError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - From Account Section

    @ViewBuilder
    private var fromAccountSection: some View {
        Section("Inscribe From") {
            // EOA option
            Button {
                viewModel.useSmartAccount = false
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.useSmartAccount ? "circle" : "checkmark.circle.fill")
                        .foregroundColor(viewModel.useSmartAccount ? .secondary : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Regular Wallet (EOA)")
                        Text(account?.shortAddress ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !viewModel.useSmartAccount {
                        Text(viewModel.displayBalance)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Smart Account option
            Button {
                viewModel.useSmartAccount = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.useSmartAccount ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(viewModel.useSmartAccount ? .blue : .secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .font(.caption)
                            Text("Smart Account")
                        }
                        if let sa = viewModel.smartAccount {
                            Text(sa.shortAddress)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if viewModel.useSmartAccount {
                        Text(viewModel.displayBalance)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            // Gasless option
            if viewModel.useSmartAccount {
                Toggle(isOn: $viewModel.usePaymaster) {
                    HStack(spacing: 8) {
                        Image(systemName: "gift")
                            .foregroundStyle(.green)
                        Text("Gasless (Sponsored)")
                    }
                }
                .disabled(!viewModel.isPaymasterAvailable)
            }
        }
    }

    // MARK: - Options Section

    @ViewBuilder
    private var optionsSection: some View {
        Section("Options") {
            if viewModel.contentType == .text {
                Toggle(isOn: $viewModel.useRawMode) {
                    VStack(alignment: .leading) {
                        Text("Raw Mode")
                        Text("Send text as-is without data URI encoding")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !viewModel.useRawMode {
                Toggle(isOn: $viewModel.allowDuplicate) {
                    VStack(alignment: .leading) {
                        Text("Allow Duplicate (ESIP-6)")
                        Text("Create even if identical content exists")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $viewModel.useCompression) {
                    VStack(alignment: .leading) {
                        Text("Use Compression (ESIP-7)")
                        Text("Compress content to reduce gas costs")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Info Section

    @ViewBuilder
    private var infoSection: some View {
        Section("Transaction") {
            if viewModel.isEstimatingGas {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Estimating gas...")
                        .foregroundStyle(.secondary)
                }
            } else if let estimate = viewModel.gasEstimate {
                HStack {
                    Text("Estimated Fee")
                    Spacer()
                    Text(estimate.formattedCost)
                        .fontWeight(.medium)
                }

                if let result = viewModel.validationResult {
                    HStack {
                        Text("Calldata Size")
                        Spacer()
                        Text("\(result.estimatedCalldataSize) bytes")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var supportedFileTypes: [UTType] {
        [.png, .gif, .jpeg, .webP, .svg, .plainText, .html, .json]
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                viewModel.selectedFileURL = url
            }
        case .failure:
            break
        }
    }

    private func fileIcon(for mimeType: String) -> String {
        if mimeType.hasPrefix("image/") {
            return "photo"
        } else if mimeType.contains("text") {
            return "doc.text"
        } else if mimeType.contains("json") {
            return "curlybraces"
        }
        return "doc"
    }
}

// MARK: - Create Confirmation Sheet

struct CreateConfirmationSheet: View {
    @ObservedObject var viewModel: CreateViewModel
    @Environment(\.dismiss) private var dismiss

    var onSuccess: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Preview
                VStack(spacing: 16) {
                    Image(systemName: previewIcon)
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)

                    Text(previewTitle)
                        .font(.headline)

                    Text(viewModel.formattedContentSize)
                        .foregroundStyle(.secondary)
                }

                // Summary
                VStack(spacing: 12) {
                    summaryRow(label: "Type", value: mimeTypeDisplay)
                    summaryRow(label: "Recipient", value: recipientDisplay)

                    if viewModel.useRawMode {
                        summaryRow(label: "Mode", value: "Raw (no encoding)")
                    }

                    if viewModel.allowDuplicate && !viewModel.useRawMode {
                        summaryRow(label: "ESIP-6", value: "Duplicate allowed")
                    }

                    if viewModel.useCompression && !viewModel.useRawMode {
                        summaryRow(label: "ESIP-7", value: "Compressed")
                    }

                    if let estimate = viewModel.gasEstimate {
                        summaryRow(label: "Estimated Fee", value: estimate.formattedCost)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)

                Spacer()

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                    Text("This action cannot be undone. The ethscription will be permanently recorded on the blockchain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                // Buttons
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        create()
                    } label: {
                        if viewModel.isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Create Ethscription")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(viewModel.isCreating)
                }
            }
            .padding()
            .navigationTitle("Confirm Creation")
        }
        .frame(minWidth: 320, minHeight: 400)
    }

    @ViewBuilder
    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var previewIcon: String {
        switch viewModel.contentType {
        case .text:
            return "doc.text"
        case .file:
            if viewModel.fileMimeType.hasPrefix("image/") {
                return "photo"
            }
            return "doc"
        }
    }

    private var previewTitle: String {
        switch viewModel.contentType {
        case .text:
            return "Text Ethscription"
        case .file:
            return viewModel.selectedFileURL?.lastPathComponent ?? "File Ethscription"
        }
    }

    private var mimeTypeDisplay: String {
        switch viewModel.contentType {
        case .text:
            return viewModel.useRawMode ? "Raw text (as-is)" : "text/plain"
        case .file:
            return viewModel.fileMimeType
        }
    }

    private var recipientDisplay: String {
        let address = viewModel.recipientAddress
        guard address.count >= 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    private func create() {
        Task {
            do {
                _ = try await viewModel.create()
                await MainActor.run {
                    dismiss()
                    onSuccess()
                }
            } catch {
                // Error displayed in viewModel
            }
        }
    }
}

// MARK: - Create Success Sheet

struct CreateSuccessSheet: View {
    let txHash: String
    var isUserOperation: Bool = false
    var onDone: () -> Void

    @StateObject private var networkManager = NetworkManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Ethscription Created!")
                .font(.title)
                .fontWeight(.semibold)

            if isUserOperation {
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                    Text("Smart Account Transaction")
                }
                .font(.callout)
                .foregroundStyle(.blue)

                Text("Your ethscription is being bundled and will appear on-chain shortly.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Your ethscription is being confirmed on the blockchain.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 4) {
                Text(isUserOperation ? "UserOperation Hash" : "Transaction Hash")
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

            if !isUserOperation, let explorerURL = networkManager.selectedNetwork.explorerTransactionURL(txHash) {
                Link(destination: explorerURL) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                }
            }

            Button("Done") {
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding()
        .frame(minWidth: 280, minHeight: 320)
    }
}

#Preview {
    CreateEthscriptionView(account: nil)
}
