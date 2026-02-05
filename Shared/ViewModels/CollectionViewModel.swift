import Foundation
import Combine

/// View model for viewing ethscription collections
@MainActor
final class CollectionViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var ethscriptions: [Ethscription] = []
    @Published private(set) var collections: [Collection] = []
    @Published var selectedCollection: Collection?
    @Published var selectedEthscription: Ethscription?

    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMetadata: Bool = false
    @Published private(set) var error: String?

    @Published private(set) var metadata: [String: TokenMetadata] = [:]  // ethscriptionId -> metadata

    // MARK: - Filters

    @Published var searchQuery: String = ""
    @Published var filterCollection: String?
    @Published var sortOrder: SortOrder = .newest

    // MARK: - Dependencies

    private let appChainService: AppChainService

    private var account: Account?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(appChainService: AppChainService = .shared) {
        self.appChainService = appChainService
        setupBindings()
    }

    private func setupBindings() {
        // Filter ethscriptions when search/filter changes
        $searchQuery
            .combineLatest($filterCollection, $sortOrder)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    /// Configure with an account
    func configure(account: Account) {
        self.account = account
    }

    // MARK: - Loading

    /// Load ethscriptions for the current account
    func loadEthscriptions() async {
        guard let account = account else { return }

        isLoading = true
        error = nil

        defer { isLoading = false }

        do {
            // Fetch owned ethscriptions
            let owned = try await appChainService.getOwnedEthscriptions(address: account.address)
            self.allEthscriptions = owned
            self.ethscriptions = owned

            // Extract unique collections
            let collectionAddresses = Set(owned.compactMap { $0.collection?.collectionAddress })
            await loadCollections(addresses: Array(collectionAddresses))

            applyFilters()
        } catch {
            self.error = error.localizedDescription
            self.ethscriptions = []
            self.allEthscriptions = []
        }
    }

    /// Load collection details
    private func loadCollections(addresses: [String]) async {
        var loadedCollections: [Collection] = []

        for address in addresses {
            do {
                let name = try await appChainService.getCollectionName(address)
                let symbol = try await appChainService.getCollectionSymbol(address)
                let totalSupply = try await appChainService.getCollectionTotalSupply(address)

                let collection = Collection(
                    id: address,
                    name: name,
                    symbol: symbol,
                    totalSupply: Int(totalSupply),
                    description: nil,
                    imageURL: nil,
                    externalURL: nil
                )

                loadedCollections.append(collection)
            } catch {
                // Skip collections that fail to load
                continue
            }
        }

        self.collections = loadedCollections
    }

    /// Load metadata for an ethscription
    func loadMetadata(for ethscription: Ethscription) async {
        guard let membership = ethscription.collection,
              metadata[ethscription.id] == nil else {
            return
        }

        isLoadingMetadata = true

        do {
            let tokenMetadata = try await appChainService.getTokenMetadata(
                collection: membership.collectionAddress,
                tokenId: membership.tokenId
            )
            metadata[ethscription.id] = tokenMetadata
        } catch {
            // Silently fail for metadata loading
        }

        isLoadingMetadata = false
    }

    /// Refresh ethscriptions
    func refresh() async {
        await loadEthscriptions()
    }

    // MARK: - Filtering

    private var allEthscriptions: [Ethscription] = []

    private func applyFilters() {
        var filtered = allEthscriptions

        // Apply search filter
        if !searchQuery.isEmpty {
            let query = searchQuery.lowercased()
            filtered = filtered.filter { ethscription in
                ethscription.id.lowercased().contains(query) ||
                ethscription.collection?.collectionName?.lowercased().contains(query) == true ||
                ethscription.mimeType.lowercased().contains(query)
            }
        }

        // Apply collection filter
        if let collectionFilter = filterCollection {
            filtered = filtered.filter { $0.collection?.collectionAddress == collectionFilter }
        }

        // Apply sort
        switch sortOrder {
        case .newest:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            filtered.sort { $0.createdAt < $1.createdAt }
        case .collection:
            filtered.sort { ($0.collection?.collectionName ?? "") < ($1.collection?.collectionName ?? "") }
        }

        ethscriptions = filtered
    }

    func clearFilters() {
        searchQuery = ""
        filterCollection = nil
        sortOrder = .newest
    }

    // MARK: - Display Helpers

    /// Get filtered ethscriptions count
    var filteredCount: Int {
        ethscriptions.count
    }

    /// Get total ethscriptions count
    var totalCount: Int {
        allEthscriptions.count
    }

    /// Get ethscriptions by collection
    func ethscriptions(in collection: Collection) -> [Ethscription] {
        ethscriptions.filter { $0.collection?.collectionAddress == collection.id }
    }

    /// Get collection for an ethscription
    func collection(for ethscription: Ethscription) -> Collection? {
        guard let membership = ethscription.collection else { return nil }
        return collections.first { $0.id == membership.collectionAddress }
    }

    /// Get explorer URL for an ethscription
    func explorerURL(for ethscription: Ethscription) -> URL? {
        appChainService.explorerURL(for: ethscription.id)
    }

    /// Get explorer URL for a collection token
    func tokenExplorerURL(for ethscription: Ethscription) -> URL? {
        guard let membership = ethscription.collection else { return nil }
        return appChainService.explorerURL(
            collection: membership.collectionAddress,
            tokenId: membership.tokenId
        )
    }

    /// Get traits for an ethscription
    func traits(for ethscription: Ethscription) -> [TokenMetadata.TokenAttribute] {
        metadata[ethscription.id]?.attributes ?? []
    }
}

// MARK: - Sort Order

enum SortOrder: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case collection = "Collection"

    var id: String { rawValue }
}

// MARK: - Grid Layout

enum GridLayout: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var columns: Int {
        switch self {
        case .small: return 6
        case .medium: return 4
        case .large: return 2
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
