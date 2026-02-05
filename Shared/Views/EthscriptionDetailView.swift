import SwiftUI

/// Detail view for a single ethscription
struct EthscriptionDetailView: View {
    let ethscription: Ethscription

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletViewModel: WalletViewModel
    @State private var showingTransfer = false
    @State private var metadata: TokenMetadata?
    @State private var isLoadingMetadata = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Content preview
                    contentPreview
                        .frame(maxWidth: 400, maxHeight: 400)

                    // Collection info
                    if let collection = ethscription.collection {
                        collectionInfo(collection)
                    }

                    // Details
                    detailsSection

                    // Traits
                    if let traits = metadata?.attributes, !traits.isEmpty {
                        traitsSection(traits)
                    }

                    // Actions
                    actionsSection
                }
                .padding()
            }
            .navigationTitle(displayTitle)
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 450, minHeight: 600)
        .sheet(isPresented: $showingTransfer) {
            TransferEthscriptionSheet(ethscription: ethscription)
                .environmentObject(walletViewModel)
        }
        .task {
            await loadMetadata()
        }
    }

    // MARK: - Content Preview

    @ViewBuilder
    private var contentPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.1))

            // Show actual content
            if ethscription.isImage, let imageData = ethscription.imageData {
                #if os(macOS)
                if let nsImage = NSImage(data: imageData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.none)  // Nearest neighbor for pixel art
                        .aspectRatio(contentMode: .fit)
                }
                #else
                if let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)  // Nearest neighbor for pixel art
                        .aspectRatio(contentMode: .fit)
                }
                #endif
            } else if ethscription.isText, let text = ethscription.textContent {
                Text(text)
                    .font(.system(size: 24, design: .monospaced))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(12)
                    .padding(16)
            } else {
                // Fallback icon
                Image(systemName: ethscription.isImage ? "photo" : "doc.text")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Collection Info

    @ViewBuilder
    private func collectionInfo(_ membership: CollectionMembership) -> some View {
        VStack(spacing: 8) {
            Text(membership.collectionName ?? "Unknown Collection")
                .font(.headline)

            Text(membership.displayNumber)
                .font(.title)
                .fontWeight(.bold)

            if let url = membership.explorerURL {
                Link(destination: url) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Details Section

    @ViewBuilder
    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Details")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("ID")
                        .foregroundStyle(.secondary)
                    Text(ethscription.id)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Creator")
                        .foregroundStyle(.secondary)
                    Text(ethscription.creator)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Owner")
                        .foregroundStyle(.secondary)
                    Text(ethscription.owner)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("Content Type")
                        .foregroundStyle(.secondary)
                    Text(ethscription.mimeType)
                }

                GridRow {
                    Text("Size")
                        .foregroundStyle(.secondary)
                    Text(formattedSize)
                }

                GridRow {
                    Text("Block")
                        .foregroundStyle(.secondary)
                    Text("#\(ethscription.blockNumber)")
                }

                GridRow {
                    Text("Created")
                        .foregroundStyle(.secondary)
                    Text(ethscription.createdAt, style: .date)
                }

                if ethscription.isDuplicate {
                    GridRow {
                        Text("ESIP-6")
                            .foregroundStyle(.secondary)
                        Text("Duplicate allowed")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Traits Section

    @ViewBuilder
    private func traitsSection(_ traits: [TokenMetadata.TokenAttribute]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Traits")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 12) {
                ForEach(traits, id: \.traitType) { trait in
                    VStack(spacing: 4) {
                        Text(trait.traitType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(trait.value.displayValue)
                            .fontWeight(.medium)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        HStack(spacing: 16) {
            Button {
                showingTransfer = true
            } label: {
                Label("Transfer", systemImage: "arrow.up.right")
            }
            .buttonStyle(.borderedProminent)

            if let url = ethscription.explorerURL {
                Link(destination: url) {
                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    private var displayTitle: String {
        if let collection = ethscription.collection {
            return collection.displayNumber
        }
        return ethscription.shortId
    }

    private var formattedSize: String {
        let bytes = ethscription.contentSize
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
    }

    private func loadMetadata() async {
        guard let collection = ethscription.collection else { return }

        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        do {
            metadata = try await AppChainService.shared.getTokenMetadata(
                collection: collection.collectionAddress,
                tokenId: collection.tokenId
            )
        } catch {
            // Silently fail
        }
    }
}

// MARK: - Transfer Sheet

struct TransferEthscriptionSheet: View {
    let ethscription: Ethscription

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var walletViewModel: WalletViewModel

    @State private var recipientAddress = ""
    @State private var isTransferring = false
    @State private var error: String?
    @State private var txHash: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let hash = txHash {
                    successView(hash: hash)
                } else {
                    transferForm
                }
            }
            .padding()
            .navigationTitle("Transfer Ethscription")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 400, minHeight: 350)
    }

    @ViewBuilder
    private var transferForm: some View {
        VStack(spacing: 16) {
            // Ethscription preview
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: ethscription.isImage ? "photo" : "doc.text")
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading) {
                    if let collection = ethscription.collection {
                        Text(collection.collectionName ?? "Ethscription")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(collection.displayNumber)
                            .fontWeight(.medium)
                    } else {
                        Text(ethscription.shortId)
                            .font(.body.monospaced())
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)

            // Recipient
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipient Address")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("0x...", text: $recipientAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer()

            // Transfer button
            Button {
                transfer()
            } label: {
                if isTransferring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Transfer")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(recipientAddress.isEmpty || !recipientAddress.isValidEthereumAddress || isTransferring)
        }
    }

    @ViewBuilder
    private func successView(hash: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Transfer Sent")
                .font(.title2)
                .fontWeight(.semibold)

            Text(hash)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func transfer() {
        guard recipientAddress.isValidEthereumAddress else {
            error = "Invalid address"
            return
        }

        guard let account = walletViewModel.selectedAccount else {
            error = "No account selected"
            return
        }

        isTransferring = true
        error = nil

        Task {
            do {
                // Get private key (requires biometric auth)
                let privateKey = try await walletViewModel.getPrivateKey(for: account)

                // Create ethscription service
                let web3Service = Web3Service()
                let ethscriptionService = EthscriptionService(web3Service: web3Service)

                // Perform transfer
                let hash = try await ethscriptionService.transferEthscription(
                    ethscriptionId: ethscription.id,
                    to: recipientAddress,
                    from: account.address,
                    privateKey: privateKey
                )

                await MainActor.run {
                    txHash = hash
                    isTransferring = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isTransferring = false
                }
            }
        }
    }
}

#Preview {
    EthscriptionDetailView(
        ethscription: Ethscription(
            id: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
            creator: "0xabcdef1234567890abcdef1234567890abcdef12",
            owner: "0xabcdef1234567890abcdef1234567890abcdef12",
            contentHash: "0x...",
            mimeType: "image/png",
            contentURI: "data:,Hello World",
            contentSize: 45000,
            blockNumber: 18000000,
            createdAt: Date(),
            collection: CollectionMembership(
                collectionAddress: "0x1234...",
                tokenId: "42",
                collectionName: "Cool Collection"
            ),
            isDuplicate: false
        )
    )
}
