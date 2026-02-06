import SwiftUI

/// View for managing token approvals
struct ApprovalsView: View {
    let account: Account
    let chainId: Int

    @StateObject private var viewModel = ApprovalsViewModel()
    @State private var showingRevokeConfirmation = false
    @State private var approvalToRevoke: TokenApproval?
    @State private var showingRevokeSuccess = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.approvals.isEmpty {
                    loadingView
                } else if let error = viewModel.error, viewModel.approvals.isEmpty {
                    errorView(error: error)
                } else if viewModel.approvals.isEmpty {
                    emptyView
                } else {
                    approvalsList
                }
            }
            .navigationTitle("Token Approvals")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 320)
        .onAppear {
            viewModel.configure(account: account, chainId: chainId)
            Task { await viewModel.loadApprovals() }
        }
        .alert("Revoke Approval", isPresented: $showingRevokeConfirmation) {
            Button("Cancel", role: .cancel) {
                approvalToRevoke = nil
            }
            Button("Revoke", role: .destructive) {
                if let approval = approvalToRevoke {
                    Task {
                        try? await viewModel.revokeApproval(approval)
                        showingRevokeSuccess = true
                    }
                }
            }
        } message: {
            if let approval = approvalToRevoke {
                Text("This will revoke \(approval.spenderDisplayName)'s access to your \(approval.token.symbol) tokens. This requires a transaction and will cost gas.")
            }
        }
        .alert("Approval Revoked", isPresented: $showingRevokeSuccess) {
            Button("OK") {
                approvalToRevoke = nil
            }
        } message: {
            if let approval = viewModel.lastRevokedApproval {
                Text("Successfully revoked \(approval.spenderDisplayName)'s access to \(approval.token.symbol).")
            }
        }
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading approvals...")
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

            Text("Failed to load approvals")
                .font(.headline)

            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.loadApprovals() }
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
            Image(systemName: "checkmark.shield")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("No Active Approvals")
                .font(.headline)

            Text("You haven't granted any token approvals, or all approvals have been revoked.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Approvals List

    @ViewBuilder
    private var approvalsList: some View {
        List {
            // Warning banner for risky approvals
            if viewModel.hasRiskyApprovals {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(viewModel.riskyApprovals.count) Risky Approval\(viewModel.riskyApprovals.count == 1 ? "" : "s")")
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text("Unlimited approvals to unknown contracts. Consider revoking.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Group approvals by token
            ForEach(viewModel.uniqueTokens, id: \.self) { tokenSymbol in
                Section(tokenSymbol) {
                    ForEach(viewModel.approvalsForToken(tokenSymbol)) { approval in
                        approvalRow(approval)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Approval Row

    @ViewBuilder
    private func approvalRow(_ approval: TokenApproval) -> some View {
        HStack(spacing: 12) {
            // Risk indicator
            VStack {
                if approval.isRisky {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if approval.isUnlimited {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .frame(width: 24)

            // Spender info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(approval.spenderDisplayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if approval.spenderLabel == nil {
                        Text("Unknown")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }

                Text(approval.formattedAllowance)
                    .font(.caption)
                    .foregroundStyle(approval.isUnlimited ? .orange : .secondary)

                if approval.spenderLabel == nil {
                    Text(approval.shortSpender)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Revoke button
            Button {
                approvalToRevoke = approval
                showingRevokeConfirmation = true
            } label: {
                if viewModel.isRevoking && approvalToRevoke?.id == approval.id {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Revoke")
                }
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)
            .disabled(viewModel.isRevoking)
        }
        .padding(.vertical, 4)
    }
}

/// Compact approval summary for settings
struct ApprovalSummaryRow: View {
    let account: Account
    let chainId: Int

    @State private var summary: ApprovalSummary?
    @State private var isLoading = false

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Token Approvals")

                if isLoading {
                    Text("Checking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let summary = summary {
                    Text(summaryText(summary))
                        .font(.caption)
                        .foregroundStyle(summary.hasRiskyApprovals ? .orange : .secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .task {
            await loadSummary()
        }
    }

    private var icon: String {
        if let summary = summary, summary.hasRiskyApprovals {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.seal"
    }

    private var iconColor: Color {
        if let summary = summary, summary.hasRiskyApprovals {
            return .orange
        }
        return .secondary
    }

    private func summaryText(_ summary: ApprovalSummary) -> String {
        if summary.totalApprovals == 0 {
            return "No active approvals"
        }

        if summary.riskyApprovals > 0 {
            return "\(summary.riskyApprovals) risky approval\(summary.riskyApprovals == 1 ? "" : "s")"
        }

        if summary.unlimitedApprovals > 0 {
            return "\(summary.totalApprovals) approval\(summary.totalApprovals == 1 ? "" : "s"), \(summary.unlimitedApprovals) unlimited"
        }

        return "\(summary.totalApprovals) approval\(summary.totalApprovals == 1 ? "" : "s")"
    }

    private func loadSummary() async {
        isLoading = true
        summary = await ApprovalService.shared.getApprovalSummary(for: account.address, chainId: chainId)
        isLoading = false
    }
}

#Preview {
    ApprovalsView(
        account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"),
        chainId: 1
    )
}
