import SwiftUI
import BigInt

/// Grid view of owned ethscriptions
struct EthscriptionsView: View {
    let account: Account?

    @EnvironmentObject var walletViewModel: WalletViewModel
    @StateObject private var viewModel = CollectionViewModel()

    @State private var gridLayout: GridLayout = .medium
    @State private var showingCreate = false
    @State private var selectedEthscription: Ethscription?

    var body: some View {
        VStack(spacing: 0) {
            if let ethscription = selectedEthscription {
                // Inline detail panel
                ethscriptionDetailPanel(for: ethscription)
            } else if showingCreate {
                // Inline create panel
                createPanel
            } else {
                // Normal grid view
                toolbar
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                Divider()

                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error)
                } else if viewModel.ethscriptions.isEmpty {
                    emptyView
                } else {
                    ethscriptionsGrid
                }
            }
        }
        .onAppear {
            if let account = account {
                viewModel.configure(account: account)
                Task { await viewModel.loadEthscriptions() }
            }
        }
        .onChange(of: account) { _, newAccount in
            if let newAccount = newAccount {
                viewModel.configure(account: newAccount)
                Task { await viewModel.loadEthscriptions() }
            }
        }
        .onChange(of: account?.address) { _, _ in
            // Also trigger when address changes (backup for account object changes)
            if let account = account {
                viewModel.configure(account: account)
                Task { await viewModel.loadEthscriptions() }
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 6) {
            Text("Inscribed")
                .font(.caption.weight(.semibold))
            Spacer()
            Picker("", selection: $gridLayout) {
                Image(systemName: "square.grid.3x3").tag(GridLayout.small)
                Image(systemName: "square.grid.2x2").tag(GridLayout.medium)
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .controlSize(.small)
            Button { showingCreate = true } label: {
                Image(systemName: "plus").font(.caption)
            }
            Button { Task { await viewModel.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
        }
    }

    // MARK: - Detail Panel (Inline)

    @ViewBuilder
    private func ethscriptionDetailPanel(for ethscription: Ethscription) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { selectedEthscription = nil } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text(ethscription.shortId)
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Content preview
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.1))

                        if ethscription.isImage, let imageData = ethscription.imageData {
                            #if os(macOS)
                            if let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fit)
                            }
                            #else
                            if let uiImage = UIImage(data: imageData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .interpolation(.none)
                                    .aspectRatio(contentMode: .fit)
                            }
                            #endif
                        } else if ethscription.isText, let text = ethscription.textContent {
                            Text(text)
                                .font(.title2.monospaced())
                                .foregroundColor(AppColors.accent)
                                .multilineTextAlignment(.center)
                                .padding()
                        } else {
                            Image(systemName: ethscription.isImage ? "photo" : "doc.text")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 10)

                    // Name
                    if let metadata = viewModel.metadata[ethscription.id], let name = metadata.name {
                        Text(name)
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                    }

                    Divider()

                    // Details
                    VStack(spacing: 4) {
                        detailRow("ID", ethscription.shortId)
                        detailRow("Type", ethscription.mimeType)
                        detailRow("Creator", String(ethscription.creator.prefix(8)) + "..." + String(ethscription.creator.suffix(6)))
                        detailRow("Owner", String(ethscription.owner.prefix(8)) + "..." + String(ethscription.owner.suffix(6)))
                    }
                    .padding(.horizontal, 10)

                    Divider()

                    // Actions
                    HStack(spacing: 8) {
                        Button {
                            // TODO: Transfer
                        } label: {
                            Label("Transfer", systemImage: "arrow.right")
                                .font(.caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.monospaced())
        }
    }

    // MARK: - Create Panel (Inline)

    @State private var createText = ""
    @State private var isCreating = false
    @State private var useSmartAccountForCreate = false
    @State private var usePaymasterForCreate = true

    private var smartAccount: SmartAccount? {
        guard let account = account else { return nil }
        return walletViewModel.smartAccountViewModel.getSmartAccount(for: account)
    }

    private var canUseSmartAccountForCreate: Bool {
        walletViewModel.smartAccountViewModel.isSmartAccountEnabled &&
        smartAccount != nil &&
        walletViewModel.smartAccountViewModel.isBundlerAvailable
    }

    @ViewBuilder
    private var createPanel: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { showingCreate = false } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Create Inscription")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    Text("Enter text to inscribe on Ethereum")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $createText)
                        .font(.body.monospaced())
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                    Text("\(createText.utf8.count) bytes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    // Smart account toggle
                    if canUseSmartAccountForCreate {
                        VStack(spacing: 8) {
                            Divider()

                            Toggle(isOn: $useSmartAccountForCreate) {
                                HStack(spacing: 6) {
                                    Image(systemName: "shield.checkered")
                                        .font(.caption)
                                    Text("Use Smart Account")
                                        .font(.caption)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)

                            if useSmartAccountForCreate {
                                Toggle(isOn: $usePaymasterForCreate) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "gift")
                                            .font(.caption)
                                        Text("Gasless")
                                            .font(.caption)
                                    }
                                }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }

                    Button {
                        createInscription()
                    } label: {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Create", systemImage: "plus")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(createText.isEmpty || isCreating)
                }
                .padding(10)
            }
        }
    }

    private func createInscription() {
        guard let account = account else { return }
        isCreating = true

        Task {
            do {
                let privateKey = try await walletViewModel.getPrivateKey(for: account)

                // Use current network
                let network = NetworkManager.shared.selectedNetwork
                let web3 = Web3Service()
                web3.switchNetwork(network)
                let ethscriptionService = EthscriptionService(web3Service: web3)

                if useSmartAccountForCreate, let smartAccount = smartAccount {
                    // Create via smart account
                    try await createViaSmartAccount(
                        ethscriptionService: ethscriptionService,
                        smartAccount: smartAccount,
                        privateKey: privateKey
                    )
                } else {
                    // Create via EOA
                    let _ = try await ethscriptionService.createEthscription(
                        content: createText.data(using: .utf8) ?? Data(),
                        mimeType: "text/plain",
                        recipient: account.address,
                        from: account.address,
                        privateKey: privateKey
                    )
                }

                await MainActor.run {
                    isCreating = false
                    showingCreate = false
                    createText = ""
                    Task { await viewModel.refresh() }
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                }
            }
        }
    }

    private func createViaSmartAccount(
        ethscriptionService: EthscriptionService,
        smartAccount: SmartAccount,
        privateKey: Data
    ) async throws {
        let network = NetworkManager.shared.selectedNetwork
        let web3 = Web3Service()
        web3.switchNetwork(network)

        let bundlerService = BundlerService(chainId: network.id)
        let smartAccountService = SmartAccountService(
            web3Service: web3,
            bundlerService: bundlerService,
            chainId: network.id
        )

        // Build calldata
        let calldata = ethscriptionService.buildEthscriptionCalldata(
            content: createText.data(using: .utf8) ?? Data(),
            mimeType: "text/plain",
            allowDuplicate: false,
            compress: false
        )

        // Inscribe to smart account address
        let call = UserOperationCall(
            to: smartAccount.smartAccountAddress,
            value: 0,
            data: calldata
        )

        // Build UserOperation
        var userOp = try await smartAccountService.buildUserOperation(
            account: smartAccount,
            calls: [call]
        )

        // Apply paymaster if enabled
        if usePaymasterForCreate {
            let paymasterService = PaymasterService(chainId: network.id)
            userOp = try await paymasterService.buildSponsoredUserOperation(
                from: userOp,
                mode: .sponsored
            )
        }

        // Sign and send
        userOp = try smartAccountService.signUserOperation(userOp, privateKey: privateKey)
        let _ = try await bundlerService.sendUserOperation(userOp)
    }

    // MARK: - Grid

    @ViewBuilder
    private var ethscriptionsGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 16),
                    count: gridLayout.columns
                ),
                spacing: 16
            ) {
                ForEach(viewModel.ethscriptions) { ethscription in
                    EthscriptionGridItem(
                        ethscription: ethscription,
                        size: gridLayout.itemSize,
                        metadata: viewModel.metadata[ethscription.id]
                    )
                    .onTapGesture {
                        selectedEthscription = ethscription
                    }
                    .onAppear {
                        Task { await viewModel.loadMetadata(for: ethscription) }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            if account == nil {
                Text("No Account Selected")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Select an account to view ethscriptions.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            } else {
                Text("No Ethscriptions")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Create your first ethscription or receive one from another address.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)

                Button {
                    showingCreate = true
                } label: {
                    Label("Create Ethscription", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading ethscriptions...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Failed to Load")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid Item

struct EthscriptionGridItem: View {
    let ethscription: Ethscription
    let size: CGFloat
    let metadata: TokenMetadata?

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
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
                        .font(.system(size: min(size / 6, 14), design: .monospaced))
                        .foregroundColor(AppColors.accent)
                        .multilineTextAlignment(.center)
                        .lineLimit(size > 100 ? 6 : 3)
                        .padding(8)
                } else {
                    // Fallback icon
                    Image(systemName: ethscription.isImage ? "photo" : "doc.text")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(spacing: 2) {
                if let collection = ethscription.collection {
                    Text(collection.displayNumber)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else {
                    Text(ethscription.shortId)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                }

                Text(ethscription.mimeType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Collection Section Header

struct CollectionSectionHeader: View {
    let collection: Collection

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.headline)
                Text("\(collection.totalSupply) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let url = collection.explorerURL {
                Link(destination: url) {
                    Image(systemName: "arrow.up.right.square")
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    EthscriptionsView(account: nil)
}
