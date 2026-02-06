import SwiftUI
import BigInt

/// View for displaying transaction history
struct TransactionHistoryView: View {
    let address: String
    let chainId: Int

    @State private var transactions: [TxHistoryEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedTransaction: TxHistoryEntry?

    private let historyService = TransactionHistoryService.shared

    var body: some View {
        Group {
            if isLoading && transactions.isEmpty {
                loadingView
            } else if let error = error, transactions.isEmpty {
                errorView(error: error)
            } else if transactions.isEmpty {
                emptyView
            } else {
                transactionsList
            }
        }
        .task {
            await loadTransactions()
        }
        .refreshable {
            await loadTransactions()
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailView(transaction: transaction, chainId: chainId)
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading transactions...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Failed to load history")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await loadTransactions() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Transactions")
                .font(.headline)

            Text("Your transaction history will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Transactions List

    @ViewBuilder
    private var transactionsList: some View {
        List {
            ForEach(groupedTransactions, id: \.0) { date, txs in
                Section(header: Text(formatSectionDate(date))) {
                    ForEach(txs) { transaction in
                        Button {
                            selectedTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Grouped Transactions

    private var groupedTransactions: [(Date, [TxHistoryEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.timestamp)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    // MARK: - Data Loading

    private func loadTransactions() async {
        isLoading = true
        error = nil

        do {
            transactions = try await historyService.getTransactionHistory(
                for: address,
                chainId: chainId
            )
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let transaction: TxHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor)
                    .frame(width: 40, height: 40)

                Image(systemName: transaction.type.icon)
                    .foregroundStyle(iconColor)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(transaction.type.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if transaction.status == .pending {
                        Text("Pending")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    } else if transaction.status == .failed {
                        Text("Failed")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.2))
                            .foregroundStyle(.red)
                            .cornerRadius(4)
                    }
                }

                Text(transaction.isOutgoing ? "To: \(transaction.shortTo)" : "From: \(transaction.shortFrom)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Value
            VStack(alignment: .trailing, spacing: 4) {
                Text(valueText)
                    .font(.body.monospaced())
                    .foregroundStyle(valueColor)

                Text(formatTime(transaction.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var valueText: String {
        let prefix = transaction.isOutgoing ? "-" : "+"
        return "\(prefix)\(transaction.formattedValue)"
    }

    private var valueColor: Color {
        if transaction.status == .failed {
            return .secondary
        }
        return transaction.isOutgoing ? .primary : .green
    }

    private var iconBackgroundColor: Color {
        switch transaction.type {
        case .send:
            return Color.orange.opacity(0.15)
        case .receive:
            return Color.green.opacity(0.15)
        case .swap:
            return Color.blue.opacity(0.15)
        case .approval:
            return Color.purple.opacity(0.15)
        default:
            return Color.secondary.opacity(0.15)
        }
    }

    private var iconColor: Color {
        switch transaction.type {
        case .send:
            return .orange
        case .receive:
            return .green
        case .swap:
            return .blue
        case .approval:
            return .purple
        default:
            return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Transaction Detail View

struct TransactionDetailView: View {
    let transaction: TxHistoryEntry
    let chainId: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Status section
                Section {
                    HStack {
                        statusIcon
                        VStack(alignment: .leading, spacing: 4) {
                            Text(transaction.type.displayName)
                                .font(.headline)
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(statusColor)
                        }
                    }
                }

                // Value section
                Section("Amount") {
                    HStack {
                        Text(transaction.isOutgoing ? "Sent" : "Received")
                        Spacer()
                        Text(transaction.formattedValue)
                            .font(.body.monospaced())
                            .foregroundColor(transaction.isOutgoing ? Color.primary : Color.green)
                    }
                }

                // Addresses section
                Section("Details") {
                    row(label: "From", value: transaction.from, mono: true)
                    row(label: "To", value: transaction.to, mono: true)
                    row(label: "Transaction Hash", value: transaction.hash, mono: true)
                }

                // Timing section
                Section("Timing") {
                    row(label: "Date", value: formatDate(transaction.timestamp))
                    row(label: "Time", value: formatTime(transaction.timestamp))
                }

                // Gas section
                if transaction.gasUsed > 0 {
                    Section("Gas") {
                        row(label: "Gas Used", value: transaction.gasUsed.description)
                        row(label: "Gas Price", value: formatGwei(transaction.gasPrice))
                        row(label: "Gas Cost", value: formatETH(transaction.gasCost))
                    }
                }

                // Explorer link
                Section {
                    if let url = explorerURL {
                        Link(destination: url) {
                            HStack {
                                Text("View on Explorer")
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transaction Details")
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

    @ViewBuilder
    private func row(label: String, value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(mono ? .caption.monospaced() : .body)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusBackgroundColor)
                .frame(width: 48, height: 48)

            Image(systemName: transaction.type.icon)
                .font(.title2)
                .foregroundStyle(statusIconColor)
        }
    }

    private var statusText: String {
        switch transaction.status {
        case .pending:
            return "Pending confirmation"
        case .confirmed:
            return "Confirmed"
        case .failed:
            return "Transaction failed"
        }
    }

    private var statusColor: Color {
        switch transaction.status {
        case .pending:
            return .orange
        case .confirmed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusBackgroundColor: Color {
        statusColor.opacity(0.15)
    }

    private var statusIconColor: Color {
        statusColor
    }

    private var explorerURL: URL? {
        let baseURL: String
        switch chainId {
        case 1:
            baseURL = "https://etherscan.io"
        case 8453:
            baseURL = "https://basescan.org"
        case 11155111:
            baseURL = "https://sepolia.etherscan.io"
        default:
            return nil
        }
        return URL(string: "\(baseURL)/tx/\(transaction.hash)")
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatGwei(_ wei: BigUInt) -> String {
        let gwei = wei / BigUInt(10).power(9)
        return "\(gwei) Gwei"
    }

    private func formatETH(_ wei: BigUInt) -> String {
        let divisor = BigUInt(10).power(18)
        let whole = wei / divisor
        let frac = wei % divisor

        if frac == 0 {
            return "\(whole) ETH"
        }

        let fracStr = String(frac).prefix(6)
        return "\(whole).\(fracStr) ETH"
    }
}

#Preview {
    TransactionHistoryView(
        address: "0x1234567890abcdef1234567890abcdef12345678",
        chainId: 1
    )
}
