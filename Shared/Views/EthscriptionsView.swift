import SwiftUI

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
            // Toolbar
            toolbar
                .padding()

            Divider()

            // Content
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
        .sheet(isPresented: $showingCreate) {
            CreateEthscriptionView(account: account)
        }
        .sheet(item: $selectedEthscription) { ethscription in
            EthscriptionDetailView(ethscription: ethscription)
                .environmentObject(walletViewModel)
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
        HStack {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .frame(maxWidth: 200)

            // Collection filter
            if !viewModel.collections.isEmpty {
                Picker("Collection", selection: $viewModel.filterCollection) {
                    Text("All Collections").tag(String?.none)
                    ForEach(viewModel.collections) { collection in
                        Text(collection.name).tag(Optional(collection.id))
                    }
                }
                .frame(maxWidth: 150)
            }

            Spacer()

            // Sort order
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(SortOrder.allCases) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .frame(maxWidth: 100)

            // Grid size
            Picker("Size", selection: $gridLayout) {
                Image(systemName: "square.grid.3x3").tag(GridLayout.small)
                Image(systemName: "square.grid.2x2").tag(GridLayout.medium)
                Image(systemName: "rectangle.grid.1x2").tag(GridLayout.large)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 120)

            // Create button
            Button {
                showingCreate = true
            } label: {
                Label("Create", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            // Refresh button
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
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
                        .foregroundStyle(.primary)
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
