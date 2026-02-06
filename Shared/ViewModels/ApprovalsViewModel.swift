import Foundation
import Combine
import web3swift
import Web3Core
import BigInt

/// View model for managing token approvals
@MainActor
final class ApprovalsViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var approvals: [TokenApproval] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    @Published private(set) var isRevoking = false
    @Published private(set) var revokeError: String?
    @Published private(set) var lastRevokedApproval: TokenApproval?

    // MARK: - Dependencies

    private let approvalService: ApprovalService
    private let keychainService: KeychainService

    private var account: Account?
    private var chainId: Int = 1

    // MARK: - Computed Properties

    var unlimitedApprovals: [TokenApproval] {
        approvals.filter { $0.isUnlimited }
    }

    var riskyApprovals: [TokenApproval] {
        approvals.filter { $0.isRisky }
    }

    var hasRiskyApprovals: Bool {
        !riskyApprovals.isEmpty
    }

    var summary: String {
        if approvals.isEmpty {
            return "No active approvals"
        }

        let unlimited = unlimitedApprovals.count
        if unlimited > 0 {
            return "\(approvals.count) approval\(approvals.count == 1 ? "" : "s"), \(unlimited) unlimited"
        }
        return "\(approvals.count) approval\(approvals.count == 1 ? "" : "s")"
    }

    // MARK: - Initialization

    init(
        approvalService: ApprovalService = .shared,
        keychainService: KeychainService = .shared
    ) {
        self.approvalService = approvalService
        self.keychainService = keychainService
    }

    // MARK: - Configuration

    func configure(account: Account, chainId: Int) {
        self.account = account
        self.chainId = chainId
    }

    // MARK: - Loading

    func loadApprovals() async {
        guard let account = account else {
            error = "No account configured"
            return
        }

        isLoading = true
        error = nil

        do {
            approvals = try await approvalService.getApprovals(for: account.address, chainId: chainId)
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func refresh() async {
        await loadApprovals()
    }

    // MARK: - Revoke

    func revokeApproval(_ approval: TokenApproval) async throws {
        guard let account = account else {
            throw ApprovalError.noAccount
        }

        isRevoking = true
        revokeError = nil

        do {
            // Get private key (requires biometric auth)
            let seed = try await keychainService.retrieveSeed()

            guard let keystore = try? BIP32Keystore(
                seed: seed,
                password: "",
                prefixPath: "m/44'/60'/0'/0"
            ) else {
                throw ApprovalError.keyDerivationFailed
            }

            guard let address = EthereumAddress(account.address),
                  let privateKey = try? keystore.UNSAFE_getPrivateKeyData(
                    password: "",
                    account: address
                  ) else {
                throw ApprovalError.keyDerivationFailed
            }

            _ = try await approvalService.revokeApproval(
                token: approval.token.address,
                spender: approval.spender,
                from: account.address,
                privateKey: privateKey
            )

            // Remove from list
            approvals.removeAll { $0.id == approval.id }
            lastRevokedApproval = approval
            isRevoking = false
        } catch {
            revokeError = error.localizedDescription
            isRevoking = false
            throw error
        }
    }

    func estimateRevokeGas(for approval: TokenApproval) async -> GasEstimate? {
        guard let account = account else { return nil }

        do {
            return try await approvalService.estimateRevokeGas(
                token: approval.token.address,
                spender: approval.spender,
                from: account.address
            )
        } catch {
            return nil
        }
    }

    // MARK: - Filtering

    func approvalsForToken(_ symbol: String) -> [TokenApproval] {
        approvals.filter { $0.token.symbol == symbol }
    }

    var uniqueTokens: [String] {
        Array(Set(approvals.map { $0.token.symbol })).sorted()
    }
}

// MARK: - Errors

enum ApprovalError: Error, LocalizedError {
    case noAccount
    case keyDerivationFailed
    case revokeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "No account configured"
        case .keyDerivationFailed:
            return "Failed to access private key"
        case .revokeFailed(let reason):
            return "Failed to revoke: \(reason)"
        }
    }
}
