import SwiftUI

/// Sheet view for upgrading an EOA to a smart account
struct AccountUpgradeView: View {
    @ObservedObject var viewModel: SmartAccountViewModel
    let account: Account
    let onUpgrade: (SmartAccount) -> Void
    let onCancel: () -> Void

    @State private var isUpgrading = false
    @State private var error: String?
    @State private var computedAddress: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header illustration
                    headerSection

                    // Current account
                    currentAccountSection

                    // Benefits
                    benefitsSection

                    // Important info
                    infoSection

                    // Computed address preview
                    if let address = computedAddress {
                        addressPreviewSection(address)
                    }

                    // Error
                    if let error = error {
                        errorSection(error)
                    }
                }
                .padding()
            }
            .navigationTitle("Upgrade to Smart Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .disabled(isUpgrading)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Upgrade") {
                        upgrade()
                    }
                    .disabled(isUpgrading)
                }
            }
            .task {
                await computeAddress()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "shield.checkered")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
            }

            Text("Unlock Advanced Features")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Upgrade your wallet to an ERC-4337 smart account")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Current Account Section

    private var currentAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your EOA")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "person.circle")
                    .foregroundStyle(.secondary)

                Text(account.shortAddress)
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Text("Standard")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .padding()
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Smart Account Benefits")
                .font(.headline)

            ForEach(SmartAccountFeature.allCases, id: \.rawValue) { feature in
                benefitRow(feature)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func benefitRow(_ feature: SmartAccountFeature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.iconName)
                .font(.title3)
                .foregroundStyle(feature.isAvailable ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(feature.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if !feature.isAvailable {
                        Text("Coming Soon")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }

                Text(feature.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Important", systemImage: "info.circle.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 6) {
                infoPoint("Your EOA remains the owner and can always recover funds")
                infoPoint("Smart account is deployed on first transaction")
                infoPoint("No additional fees for account creation")
                infoPoint("You can still use your EOA normally")
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func infoPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Address Preview Section

    private func addressPreviewSection(_ address: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Account Address")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.blue)

                Text(formatAddress(address))
                    .font(.system(.body, design: .monospaced))

                Spacer()

                Button {
                    copyToClipboard(address)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text("This address is deterministic and computed before deployment")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Error Section

    private func errorSection(_ error: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(error)
                .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func computeAddress() async {
        // The address will be computed when creating the smart account
        // For now, we can show a placeholder
    }

    private func upgrade() {
        isUpgrading = true
        error = nil

        Task {
            do {
                let smartAccount = try await viewModel.createSmartAccount(for: account)
                await MainActor.run {
                    isUpgrading = false
                    onUpgrade(smartAccount)
                }
            } catch {
                await MainActor.run {
                    isUpgrading = false
                    self.error = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatAddress(_ address: String) -> String {
        guard address.count >= 10 else { return address }
        let start = address.prefix(6)
        let end = address.suffix(4)
        return "\(start)...\(end)"
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Upgrade Prompt Banner

/// A banner prompting users to upgrade to a smart account
struct SmartAccountUpgradeBanner: View {
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Upgrade Available")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Get batch transactions & gasless transfers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Upgrade") {
                onUpgrade()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    AccountUpgradeView(
        viewModel: SmartAccountViewModel(),
        account: Account(index: 0, address: "0x1234567890123456789012345678901234567890"),
        onUpgrade: { _ in },
        onCancel: {}
    )
}
