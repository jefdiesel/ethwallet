import Foundation
import Combine

/// Manages network selection and RPC endpoints
final class NetworkManager: ObservableObject {
    static let shared = NetworkManager()

    @Published private(set) var networks: [Network] = Network.defaults
    @Published var selectedNetwork: Network = .ethereum {
        didSet {
            UserDefaults.standard.set(selectedNetwork.id, forKey: "selectedNetworkId")
            NotificationCenter.default.post(name: .networkDidChange, object: selectedNetwork)
        }
    }
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var blockNumber: UInt64 = 0
    @Published private(set) var latency: TimeInterval = 0

    private var healthCheckTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Load custom networks from storage
        if let customNetworks = Self.loadCustomNetworks() {
            self.networks.append(contentsOf: customNetworks)
        }

        // Restore last selected network
        let lastSelectedId = UserDefaults.standard.integer(forKey: "selectedNetworkId")
        if let network = networks.first(where: { $0.id == lastSelectedId }) {
            self.selectedNetwork = network
        }

        // Start health check
        startHealthCheck()
    }

    // MARK: - Network Selection

    /// Switch to a different network
    func selectNetwork(_ network: Network) {
        guard networks.contains(where: { $0.id == network.id }) else { return }
        selectedNetwork = network
        checkHealth()
    }

    /// Select network by chain ID
    func selectNetwork(chainId: Int) {
        guard let network = networks.first(where: { $0.id == chainId }) else { return }
        selectedNetwork = network
    }

    // MARK: - Custom Networks

    /// Add a custom network
    func addCustomNetwork(_ network: Network) {
        guard !networks.contains(where: { $0.id == network.id }) else { return }
        networks.append(network)
        saveCustomNetworks()
    }

    /// Remove a custom network
    func removeCustomNetwork(_ network: Network) {
        // Don't allow removing default networks
        guard !Network.defaults.contains(where: { $0.id == network.id }) else { return }
        networks.removeAll { $0.id == network.id }
        saveCustomNetworks()

        // If the removed network was selected, switch to Ethereum
        if selectedNetwork.id == network.id {
            selectedNetwork = .ethereum
        }
    }

    /// Update a custom network's RPC URL
    func updateRPCURL(for networkId: Int, newURL: URL) {
        guard let index = networks.firstIndex(where: { $0.id == networkId }) else { return }
        let network = networks[index]

        let updated = Network(
            chainId: network.id,
            name: network.name,
            rpcURLString: newURL.absoluteString,
            currencySymbol: network.currencySymbol,
            explorerURLString: network.explorerURL?.absoluteString,
            isTestnet: network.isTestnet
        )

        networks[index] = updated
        saveCustomNetworks()

        if selectedNetwork.id == networkId {
            selectedNetwork = updated
        }
    }

    // MARK: - RPC Health Check

    /// Check the health of the current RPC endpoint
    func checkHealth() {
        Task {
            let startTime = Date()
            let result = await performRPCCall(method: "eth_blockNumber", params: [])

            await MainActor.run {
                self.latency = Date().timeIntervalSince(startTime)

                switch result {
                case .success(let response):
                    self.isConnected = true
                    if let hexBlock = response as? String,
                       let blockNum = UInt64(hexBlock.dropFirst(2), radix: 16) {
                        self.blockNumber = blockNum
                    }
                case .failure:
                    self.isConnected = false
                }
            }
        }
    }

    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        checkHealth()  // Initial check
    }

    // MARK: - RPC Calls

    /// Make a JSON-RPC call to the current network
    func rpcCall<T: Decodable>(
        method: String,
        params: [Any]
    ) async throws -> T {
        let result = await performRPCCall(method: method, params: params)

        switch result {
        case .success(let value):
            if let typed = value as? T {
                return typed
            }
            throw NetworkError.decodingFailed
        case .failure(let error):
            throw error
        }
    }

    /// Make a raw JSON-RPC call
    func rawRPCCall(
        method: String,
        params: [Any],
        to network: Network? = nil
    ) async throws -> Any {
        let targetNetwork = network ?? selectedNetwork
        let result = await performRPCCall(method: method, params: params, network: targetNetwork)

        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        }
    }

    private func performRPCCall(
        method: String,
        params: [Any],
        network: Network? = nil
    ) async -> Result<Any, NetworkError> {
        let targetNetwork = network ?? selectedNetwork

        var request = URLRequest(url: targetNetwork.rpcURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            return .failure(.invalidRequest)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .failure(.httpError)
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decodingFailed)
            }

            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return .failure(.rpcError(message))
            }

            guard let result = json["result"] else {
                return .failure(.emptyResponse)
            }

            return .success(result)
        } catch {
            return .failure(.networkError(error))
        }
    }

    // MARK: - Persistence

    private static func loadCustomNetworks() -> [Network]? {
        guard let data = UserDefaults.standard.data(forKey: "customNetworks"),
              let networks = try? JSONDecoder().decode([Network].self, from: data) else {
            return nil
        }
        return networks
    }

    private func saveCustomNetworks() {
        let customNetworks = networks.filter { network in
            !Network.defaults.contains { $0.id == network.id }
        }

        if let data = try? JSONEncoder().encode(customNetworks) {
            UserDefaults.standard.set(data, forKey: "customNetworks")
        }
    }
}

// MARK: - Network Errors

enum NetworkError: Error, LocalizedError {
    case invalidRequest
    case httpError
    case decodingFailed
    case emptyResponse
    case rpcError(String)
    case networkError(Error)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "Invalid RPC request"
        case .httpError:
            return "HTTP request failed"
        case .decodingFailed:
            return "Failed to decode response"
        case .emptyResponse:
            return "Empty response from server"
        case .rpcError(let message):
            return "RPC error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out"
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let networkDidChange = Notification.Name("networkDidChange")
}
