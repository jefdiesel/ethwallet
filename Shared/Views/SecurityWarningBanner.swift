import SwiftUI

/// A banner view that displays security warnings
struct SecurityWarningBanner: View {
    let warnings: [SecurityWarning]
    var onDismiss: (() -> Void)?

    var body: some View {
        if !warnings.isEmpty {
            VStack(spacing: 0) {
                ForEach(warnings) { warning in
                    warningRow(warning)
                    if warning.id != warnings.last?.id {
                        Divider()
                    }
                }
            }
            .background(backgroundColor)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func warningRow(_ warning: SecurityWarning) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: warning.icon)
                .font(.title3)
                .foregroundStyle(iconColor(for: warning.severity))

            VStack(alignment: .leading, spacing: 4) {
                Text(warning.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(textColor(for: warning.severity))

                Text(warning.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let onDismiss = onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }

    private var backgroundColor: Color {
        guard let maxSeverity = warnings.map(\.severity).max() else {
            return Color.orange.opacity(0.1)
        }

        switch maxSeverity {
        case .critical:
            return Color.red.opacity(0.12)
        case .high:
            return Color.orange.opacity(0.12)
        case .medium:
            return Color.yellow.opacity(0.12)
        }
    }

    private var borderColor: Color {
        guard let maxSeverity = warnings.map(\.severity).max() else {
            return Color.orange.opacity(0.3)
        }

        switch maxSeverity {
        case .critical:
            return Color.red.opacity(0.3)
        case .high:
            return Color.orange.opacity(0.3)
        case .medium:
            return Color.yellow.opacity(0.3)
        }
    }

    private func iconColor(for severity: WarningSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .yellow
        }
    }

    private func textColor(for severity: WarningSeverity) -> Color {
        switch severity {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .primary
        }
    }
}

/// A compact warning indicator that shows a count badge
struct SecurityWarningIndicator: View {
    let warnings: [SecurityWarning]

    var body: some View {
        if !warnings.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: highestSeverityIcon)
                    .font(.caption)

                if warnings.count > 1 {
                    Text("\(warnings.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            .foregroundStyle(highestSeverityColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(highestSeverityColor.opacity(0.15))
            .cornerRadius(6)
        }
    }

    private var highestSeverity: WarningSeverity {
        warnings.map(\.severity).max() ?? .medium
    }

    private var highestSeverityIcon: String {
        switch highestSeverity {
        case .critical:
            return "exclamationmark.octagon.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        case .medium:
            return "info.circle.fill"
        }
    }

    private var highestSeverityColor: Color {
        switch highestSeverity {
        case .critical:
            return .red
        case .high:
            return .orange
        case .medium:
            return .yellow
        }
    }
}

/// A blocking overlay for critical security warnings
struct SecurityBlockingOverlay: View {
    let warning: SecurityWarning
    var onProceedAnyway: (() -> Void)?
    var onGoBack: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: warning.icon)
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text(warning.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.red)

            Text(warning.message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button(action: onGoBack) {
                    Text("Go Back to Safety")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let proceedAnyway = onProceedAnyway {
                    Button(action: proceedAnyway) {
                        Text("I understand the risks, proceed anyway")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top)
        }
        .padding(32)
        .background(.regularMaterial)
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding(32)
    }
}

#Preview("Warning Banner") {
    VStack(spacing: 20) {
        SecurityWarningBanner(warnings: [
            .knownPhishingDomain(domain: "uniswаp.com")
        ])

        SecurityWarningBanner(warnings: [
            .unverifiedContract(address: "0x1234567890abcdef"),
            .newContract(address: "0x1234567890abcdef", ageInDays: 2)
        ])

        SecurityWarningBanner(warnings: [
            .unlimitedApproval(token: "USDC", spender: "0xabcd...")
        ])
    }
    .padding()
}

#Preview("Warning Indicator") {
    HStack(spacing: 20) {
        SecurityWarningIndicator(warnings: [])

        SecurityWarningIndicator(warnings: [
            .unverifiedContract(address: "0x123")
        ])

        SecurityWarningIndicator(warnings: [
            .knownPhishingDomain(domain: "test.com"),
            .unverifiedContract(address: "0x123")
        ])
    }
    .padding()
}

#Preview("Blocking Overlay") {
    ZStack {
        Color.gray.opacity(0.3)
            .ignoresSafeArea()

        SecurityBlockingOverlay(
            warning: .knownPhishingDomain(domain: "uniswаp.com"),
            onProceedAnyway: {},
            onGoBack: {}
        )
    }
}
