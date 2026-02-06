import SwiftUI
import BigInt

/// View for displaying transaction simulation results
struct SimulationResultView: View {
    let result: SimulationResult
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: headerIcon)
                    .foregroundStyle(headerColor)
                Text(headerText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !isLoading {
                // Balance changes
                if !result.balanceChanges.isEmpty {
                    balanceChangesSection
                }

                // Approval changes
                if !result.approvalChanges.isEmpty {
                    approvalChangesSection
                }

                // NFT transfers
                if !result.nftTransfers.isEmpty {
                    nftTransfersSection
                }

                // Warnings
                if !result.riskWarnings.isEmpty {
                    warningsSection
                }

                // Revert reason
                if let revertReason = result.revertReason {
                    revertSection(reason: revertReason)
                }
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Header

    private var headerIcon: String {
        if isLoading {
            return "wand.and.stars"
        } else if !result.success {
            return "xmark.circle.fill"
        } else if result.hasWarnings {
            return "exclamationmark.triangle.fill"
        } else {
            return "checkmark.circle.fill"
        }
    }

    private var headerColor: Color {
        if isLoading {
            return .blue
        } else if !result.success {
            return .red
        } else if result.hasWarnings {
            return .orange
        } else {
            return .green
        }
    }

    private var headerText: String {
        if isLoading {
            return "Simulating transaction..."
        } else if !result.success {
            return "Transaction will fail"
        } else if result.hasWarnings {
            return "Simulation completed with warnings"
        } else {
            return "Simulation successful"
        }
    }

    private var backgroundColor: Color {
        if !result.success {
            return Color.red.opacity(0.08)
        } else if result.hasWarnings {
            return Color.orange.opacity(0.08)
        } else {
            return Color.green.opacity(0.08)
        }
    }

    private var borderColor: Color {
        if !result.success {
            return Color.red.opacity(0.2)
        } else if result.hasWarnings {
            return Color.orange.opacity(0.2)
        } else {
            return Color.green.opacity(0.2)
        }
    }

    // MARK: - Balance Changes

    @ViewBuilder
    private var balanceChangesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance Changes")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(result.balanceChanges) { change in
                HStack {
                    Image(systemName: change.isIncoming ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .foregroundStyle(change.isIncoming ? .green : .orange)

                    Text(change.displayAmount)
                        .font(.body.monospaced())
                        .foregroundStyle(change.isIncoming ? .green : .primary)

                    Spacer()

                    if let usdValue = change.usdValue {
                        Text("$\(String(format: "%.2f", abs(usdValue)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Approval Changes

    @ViewBuilder
    private var approvalChangesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token Approvals")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(result.approvalChanges) { approval in
                HStack {
                    Image(systemName: approval.isRevoke ? "minus.circle.fill" : "checkmark.seal.fill")
                        .foregroundStyle(approval.isRevoke ? .gray : (approval.isUnlimited ? .orange : .blue))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(approval.token) → \(approval.spenderLabel ?? truncateAddress(approval.spender))")
                            .font(.caption)

                        Text(approval.displayAllowance)
                            .font(.caption2)
                            .foregroundStyle(approval.isUnlimited ? .orange : .secondary)
                    }

                    Spacer()

                    if approval.isUnlimited && !approval.isRevoke {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - NFT Transfers

    @ViewBuilder
    private var nftTransfersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NFT Transfers")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(result.nftTransfers) { transfer in
                HStack {
                    Image(systemName: transfer.isOutgoing ? "arrow.up.square.fill" : "arrow.down.square.fill")
                        .foregroundStyle(transfer.isOutgoing ? .orange : .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(transfer.collectionName ?? "NFT")
                            .font(.caption)
                        Text("#\(transfer.tokenId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(transfer.direction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(result.riskWarnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.icon)
                        .foregroundStyle(warningColor(for: warning.severity))
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.title)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(warningColor(for: warning.severity))

                        Text(warning.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Revert Section

    @ViewBuilder
    private func revertSection(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Revert Reason")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reason)
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
        }
    }

    // MARK: - Helpers

    private func warningColor(for severity: SimulationWarningSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .yellow
        }
    }

    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
}

/// Compact simulation indicator for space-constrained UI
struct SimulationIndicator: View {
    let result: SimulationResult?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                Text("Simulating...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let result = result {
                Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.success ? .green : .red)

                if !result.riskWarnings.isEmpty {
                    HStack(spacing: 2) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("\(result.riskWarnings.count)")
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

#Preview("Success") {
    SimulationResultView(
        result: SimulationResult(
            success: true,
            balanceChanges: [
                BalanceChange(
                    asset: .eth,
                    amount: -BigInt(500000000000000000),
                    formattedAmount: "-0.5 ETH",
                    usdValue: 1250.0
                ),
                BalanceChange(
                    asset: .token(symbol: "USDC", address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", decimals: 6),
                    amount: BigInt(1000000000),
                    formattedAmount: "+1,000 USDC",
                    usdValue: 1000.0
                )
            ],
            approvalChanges: [],
            nftTransfers: [],
            riskWarnings: [],
            gasUsed: BigUInt(150000),
            revertReason: nil
        ),
        isLoading: false
    )
    .padding()
}

#Preview("With Warnings") {
    SimulationResultView(
        result: SimulationResult(
            success: true,
            balanceChanges: [],
            approvalChanges: [
                ApprovalChange(
                    token: "USDC",
                    tokenAddress: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
                    spender: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d",
                    spenderLabel: "Uniswap V2 Router",
                    allowance: BigUInt(2).power(256) - 1,
                    isUnlimited: true,
                    isRevoke: false
                )
            ],
            nftTransfers: [],
            riskWarnings: [
                .unlimitedApproval(token: "USDC", spender: "0x7a250d5630b4cf539739df2c5dacb4c659f2488d")
            ],
            gasUsed: BigUInt(50000),
            revertReason: nil
        ),
        isLoading: false
    )
    .padding()
}

#Preview("Failed") {
    SimulationResultView(
        result: SimulationResult(
            success: false,
            balanceChanges: [],
            approvalChanges: [],
            nftTransfers: [],
            riskWarnings: [],
            gasUsed: BigUInt(21000),
            revertReason: "execution reverted: ERC20: transfer amount exceeds balance"
        ),
        isLoading: false
    )
    .padding()
}

#Preview("Loading") {
    SimulationResultView(
        result: SimulationResult(
            success: true,
            balanceChanges: [],
            approvalChanges: [],
            nftTransfers: [],
            riskWarnings: [],
            gasUsed: BigUInt(0),
            revertReason: nil
        ),
        isLoading: true
    )
    .padding()
}
