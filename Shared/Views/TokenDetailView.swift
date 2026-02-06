import SwiftUI

/// Detail view for a token with TradingView chart
struct TokenDetailView: View {
    let balance: TokenBalance

    @Environment(\.dismiss) private var dismiss
    @State private var selectedInterval = "D"

    private let intervals = [
        ("1H", "60"),
        ("4H", "240"),
        ("1D", "D"),
        ("1W", "W"),
        ("1M", "M")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Token header
                tokenHeader

                Divider()

                // Interval picker
                Picker("Interval", selection: $selectedInterval) {
                    ForEach(intervals, id: \.1) { label, value in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Chart
                TradingViewChart(
                    symbol: balance.token.symbol.tradingViewSymbol,
                    interval: selectedInterval,
                    theme: "dark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(balance.token.symbol)
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    @ViewBuilder
    private var tokenHeader: some View {
        HStack(spacing: 12) {
            // Token icon
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                Text(balance.token.symbol.prefix(2))
                    .font(.headline.bold())
            }
            .frame(width: 48, height: 48)

            // Token info
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.token.name)
                    .font(.headline)
                Text(balance.token.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance
            VStack(alignment: .trailing, spacing: 2) {
                Text(balance.formattedBalance)
                    .font(.title3.monospacedDigit().bold())
                if let usdValue = balance.usdValue {
                    Text("$\(usdValue, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }
}

#Preview {
    let token = Token(
        address: "0x0",
        symbol: "ETH",
        name: "Ethereum",
        decimals: 18,
        logoURL: nil,
        chainId: 1
    )
    let balance = TokenBalance(
        token: token,
        rawBalance: "1500000000000000000",
        formattedBalance: "1.5",
        usdValue: 3450.00
    )
    return TokenDetailView(balance: balance)
}
