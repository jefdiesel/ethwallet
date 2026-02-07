import Foundation
import Combine

/// Service for fetching cryptocurrency prices
final class PriceService: ObservableObject {
    static let shared = PriceService()

    @Published private(set) var ethPrice: Double = 0
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: PriceServiceError?

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 60  // Refresh every minute

    private init() {
        startAutoRefresh()
    }

    // MARK: - Price Fetching

    /// Fetch current ETH price in USD
    func fetchETHPrice() async {
        await MainActor.run {
            isLoading = true
            error = nil
        }

        do {
            let price = try await fetchFromCoinGecko()
            await MainActor.run {
                self.ethPrice = price
                self.lastUpdated = Date()
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error as? PriceServiceError ?? .fetchFailed
                self.isLoading = false
            }
        }
    }

    /// Convert ETH amount to USD
    func ethToUSD(_ ethAmount: Double) -> Double {
        ethAmount * ethPrice
    }

    /// Convert USD amount to ETH
    func usdToETH(_ usdAmount: Double) -> Double {
        guard ethPrice > 0 else { return 0 }
        return usdAmount / ethPrice
    }

    /// Format USD value
    func formatUSD(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    /// Format ETH value with USD equivalent
    func formatETHWithUSD(_ ethAmount: Double) -> String {
        let ethFormatted = String(format: "%.6f ETH", ethAmount)
        if ethPrice > 0 {
            let usdValue = formatUSD(ethToUSD(ethAmount))
            return "\(ethFormatted) (\(usdValue))"
        }
        return ethFormatted
    }

    // MARK: - Auto Refresh

    private func startAutoRefresh() {
        // Initial fetch
        Task {
            await fetchETHPrice()
        }

        // Setup timer for periodic refresh
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.fetchETHPrice()
            }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - API Calls

    private func fetchFromCoinGecko() async throws -> Double {
        let url = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd")!

        let (data, response) = try await URLSession.shared.rateLimitedData(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PriceServiceError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ethereum = json["ethereum"] as? [String: Any],
              let price = ethereum["usd"] as? Double else {
            throw PriceServiceError.invalidResponse
        }

        return price
    }

    // MARK: - Historical Prices (Optional)

    /// Fetch price history for chart display
    func fetchPriceHistory(days: Int = 7) async throws -> [PricePoint] {
        let url = URL(string: "https://api.coingecko.com/api/v3/coins/ethereum/market_chart?vs_currency=usd&days=\(days)")!

        let (data, response) = try await URLSession.shared.rateLimitedData(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PriceServiceError.httpError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prices = json["prices"] as? [[Double]] else {
            throw PriceServiceError.invalidResponse
        }

        return prices.compactMap { point -> PricePoint? in
            guard point.count >= 2 else { return nil }
            let timestamp = Date(timeIntervalSince1970: point[0] / 1000)
            let price = point[1]
            return PricePoint(timestamp: timestamp, price: price)
        }
    }
}

// MARK: - Supporting Types

struct PricePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let price: Double
}

enum PriceServiceError: Error, LocalizedError {
    case fetchFailed
    case httpError
    case invalidResponse
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Failed to fetch price"
        case .httpError:
            return "Network request failed"
        case .invalidResponse:
            return "Invalid price data received"
        case .rateLimited:
            return "Rate limited, try again later"
        }
    }
}
