import SwiftUI

/// View displaying owned NFTs
struct NFTsView: View {
    let account: Account?

    @State private var nfts: [NFT] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedNFT: NFT?
    @State private var gridLayout: NFTGridLayout = .medium

    var body: some View {
        VStack(spacing: 0) {
            if let nft = selectedNFT {
                // Expanded NFT preview (hides grid)
                nftPreviewPanel(for: nft)
            } else {
                // Normal grid view
                nftGridView
            }
        }
        .onAppear {
            Task { await loadNFTs() }
        }
        .onChange(of: account?.address) { _, _ in
            Task { await loadNFTs() }
        }
    }

    // MARK: - NFT Grid View

    @ViewBuilder
    private var nftGridView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("NFTs")
                    .font(.caption.weight(.semibold))
                Spacer()
                Picker("", selection: $gridLayout) {
                    Image(systemName: "square.grid.3x3").tag(NFTGridLayout.small)
                    Image(systemName: "square.grid.2x2").tag(NFTGridLayout.medium)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 60)
                .controlSize(.small)
                Button { Task { await loadNFTs() } } label: {
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            // Content
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error)
            } else if nfts.isEmpty {
                emptyView
            } else {
                nftGrid
            }
        }
    }

    // MARK: - NFT Preview Panel (Expanded)

    @ViewBuilder
    private func nftPreviewPanel(for nft: NFT) -> some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { selectedNFT = nil } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text(nft.collectionName ?? "NFT")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // Image (handles IPFS URLs)
                    NFTPreviewImage(nft: nft)

                    // Name & Token ID
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nft.displayName)
                            .font(.caption.bold())
                        Text("#\(nft.shortTokenId)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Description
                    if let desc = nft.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Contract Info
                    VStack(spacing: 4) {
                        infoRow("Contract", nft.contractAddress.prefix(8) + "..." + nft.contractAddress.suffix(6))
                        infoRow("Standard", nft.standard.rawValue)
                        infoRow("Chain", nft.chainId == 1 ? "Ethereum" : "Chain \(nft.chainId)")
                        if nft.balance > 1 {
                            infoRow("Owned", "\(nft.balance)")
                        }
                    }

                    // Attributes
                    if let attrs = nft.attributes, !attrs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Traits")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                                ForEach(attrs.prefix(6), id: \.traitType) { attr in
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(attr.traitType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(attr.value)
                                            .font(.caption2.bold())
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(4)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }

                    Divider()

                    // Action buttons
                    HStack(spacing: 8) {
                        Button {
                            // TODO: Transfer
                        } label: {
                            Label("Transfer", systemImage: "arrow.right")
                                .font(.caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if let url = openSeaURL(for: nft) {
                            Button {
                                #if os(macOS)
                                BrowserWindowManager.shared.openURL(url)
                                #endif
                            } label: {
                                Label("OpenSea", systemImage: "safari")
                                    .font(.caption)
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    private func nftPlaceholder(text: String) -> some View {
        VStack {
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2.monospaced())
        }
    }

    private func openSeaURL(for nft: NFT) -> URL? {
        let base = nft.chainId == 1 ? "https://opensea.io/assets/ethereum" : "https://opensea.io/assets/matic"
        return URL(string: "\(base)/\(nft.contractAddress)/\(nft.tokenId)")
    }

    // MARK: - NFT Grid

    @ViewBuilder
    private var nftGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: gridLayout.columns
                ),
                spacing: 8
            ) {
                ForEach(nfts) { nft in
                    NFTGridItem(nft: nft, size: gridLayout.itemSize)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedNFT = nft
                            }
                        }
                }
            }
            .padding(10)
        }
    }

    // MARK: - Loading

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading NFTs...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No NFTs Found")
                .font(.headline)

            Text("NFTs you own will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("Note: NFT indexing requires an API key (Alchemy/OpenSea)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(error)
                .foregroundStyle(.secondary)

            Button {
                Task { await loadNFTs() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadNFTs() async {
        guard let account = account else { return }

        isLoading = true
        error = nil

        do {
            let fetchedNFTs = try await NFTService.shared.getOwnedNFTs(
                address: account.address,
                chainId: 1
            )
            await MainActor.run {
                self.nfts = fetchedNFTs
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Grid Layout

enum NFTGridLayout: String, CaseIterable {
    case small
    case medium
    case large

    var columns: Int {
        switch self {
        case .small: return 4
        case .medium: return 2
        case .large: return 1
        }
    }

    var itemSize: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 200
        }
    }
}

// MARK: - NFT Grid Item

struct NFTGridItem: View {
    let nft: NFT
    let size: CGFloat

    @State private var isHovering = false
    @State private var loadedImage: Data?

    var body: some View {
        VStack(spacing: 8) {
            // Image
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))

                if let imageData = loadedImage ?? nft.imageData {
                    #if os(macOS)
                    if let nsImage = NSImage(data: imageData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.none)  // For pixel art
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
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(spacing: 2) {
                Text(nft.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let collection = nft.collectionName {
                    Text(collection)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = nft.imageURL else { return }

        // Handle IPFS URLs
        var fetchURL = url
        if url.absoluteString.hasPrefix("ipfs://") {
            let hash = url.absoluteString.replacingOccurrences(of: "ipfs://", with: "")
            fetchURL = URL(string: "https://ipfs.io/ipfs/\(hash)") ?? url
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: fetchURL)

            // If the response is SVG wrapping a raster (on-chain pixel art NFTs),
            // extract the raw raster so NSImage doesn't bilinear-blur it
            let imageData: Data
            if let raster = NFTService.extractRasterFromSVGData(data) {
                imageData = raster
            } else {
                imageData = data
            }

            await MainActor.run {
                self.loadedImage = imageData
            }
        } catch {
            // Silently fail
        }
    }
}

// MARK: - NFT Preview Image (handles IPFS URLs)

struct NFTPreviewImage: View {
    let nft: NFT

    @State private var loadedImage: Data?
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        Group {
            if let imageData = loadedImage ?? nft.imageData {
                let finalData = NFTService.extractRasterFromSVGData(imageData) ?? imageData
                #if os(macOS)
                if let nsImage = NSImage(data: finalData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    placeholder(text: "Invalid image")
                }
                #else
                if let uiImage = UIImage(data: finalData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(8)
                } else {
                    placeholder(text: "Invalid image")
                }
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
            } else if failed {
                placeholder(text: "Failed to load")
            } else {
                placeholder(text: "No image")
            }
        }
        .frame(maxWidth: .infinity)
        .task {
            await loadImage()
        }
    }

    @ViewBuilder
    private func placeholder(text: String) -> some View {
        VStack {
            Image(systemName: "photo")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private func loadImage() async {
        guard let url = nft.imageURL else {
            isLoading = false
            return
        }

        // Handle IPFS URLs
        var fetchURL = url
        if url.absoluteString.hasPrefix("ipfs://") {
            let hash = url.absoluteString.replacingOccurrences(of: "ipfs://", with: "")
            fetchURL = URL(string: "https://ipfs.io/ipfs/\(hash)") ?? url
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: fetchURL)
            await MainActor.run {
                self.loadedImage = data
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.failed = true
                self.isLoading = false
            }
        }
    }
}

// MARK: - NFT Detail Sheet

struct NFTDetailSheet: View {
    let nft: NFT

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Image (extract raster from SVG if needed for crisp pixel art)
                    if let rawData = nft.imageData {
                        let imageData = NFTService.extractRasterFromSVGData(rawData) ?? rawData
                        #if os(macOS)
                        if let nsImage = NSImage(data: imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        #else
                        if let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .interpolation(.none)
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        #endif
                    }

                    // Info
                    VStack(alignment: .leading, spacing: 16) {
                        if let collection = nft.collectionName {
                            Text(collection)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(nft.displayName)
                            .font(.title2)
                            .fontWeight(.bold)

                        if let description = nft.description {
                            Text(description)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        // Attributes
                        if let attributes = nft.attributes, !attributes.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Attributes")
                                    .font(.headline)

                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 8) {
                                    ForEach(attributes, id: \.traitType) { attr in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(attr.traitType)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(attr.value)
                                                .font(.body)
                                                .fontWeight(.medium)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }

                        // Details
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Details")
                                .font(.headline)

                            LabeledContent("Contract") {
                                Text(nft.contractAddress.prefix(10) + "..." + nft.contractAddress.suffix(6))
                                    .font(.caption.monospaced())
                            }

                            LabeledContent("Token ID") {
                                Text(nft.shortTokenId)
                                    .font(.caption.monospaced())
                            }

                            LabeledContent("Standard") {
                                Text(nft.standard.rawValue)
                            }

                            if nft.balance > 1 {
                                LabeledContent("Owned") {
                                    Text("\(nft.balance)")
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("NFT Details")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 340, minHeight: 400)
    }
}

#Preview {
    NFTsView(account: nil)
}
