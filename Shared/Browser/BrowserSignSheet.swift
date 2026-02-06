import SwiftUI
import BigInt

/// Sheet for signing requests from the dApp browser
struct BrowserSignSheet: View {
    let request: Web3Request
    @ObservedObject var walletViewModel: WalletViewModel
    let onApprove: (Any) -> Void
    let onReject: () -> Void

    @State private var isSigning = false
    @State private var error: String?

    // Gas estimation state (for transactions)
    @State private var estimatedGasLimit: BigUInt?
    @State private var gasPrice: BigUInt?
    @State private var isEstimatingGas = true
    @State private var gasError: String?

    // Security warnings
    @State private var securityWarnings: [SecurityWarning] = []
    @State private var isCheckingSecurity = false

    // Transaction simulation
    @State private var simulationResult: SimulationResult?
    @State private var isSimulating = false

    private var priceService: PriceService { PriceService.shared }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Icon
                Image(systemName: requestIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                // Title
                Text(requestTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Method info
                VStack(alignment: .leading, spacing: 4) {
                    Text("Method")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(request.method)
                        .font(.body.monospaced())
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                // Message preview (for sign methods)
                if let message = extractMessage() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(message)
                                .font(.body.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                // Transaction details with gas/fees
                if let txDetails = extractTransactionDetails() {
                    transactionSection(txDetails)
                }

                // Simulation result
                if isTransaction {
                    SimulationResultView(
                        result: simulationResult ?? SimulationResult(
                            success: true,
                            balanceChanges: [],
                            approvalChanges: [],
                            nftTransfers: [],
                            riskWarnings: [],
                            gasUsed: BigUInt(0),
                            revertReason: nil
                        ),
                        isLoading: isSimulating
                    )
                }

                // Security warnings
                if !securityWarnings.isEmpty {
                    SecurityWarningBanner(warnings: securityWarnings)
                }

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()

                // Actions
                HStack(spacing: 16) {
                    Button("Reject") {
                        onReject()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        sign()
                    } label: {
                        if isSigning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(request.method == "eth_sendTransaction" ? "Send" : "Sign")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigning || (isTransaction && isEstimatingGas))
                }
            }
            .padding()
            .navigationTitle("Signature Request")
        }
        .frame(minWidth: 360, minHeight: isTransaction ? 480 : 380)
        .task {
            if isTransaction {
                await estimateGas()
                await checkSecurity()
                await simulateTransaction()
            }
        }
    }

    private var isTransaction: Bool {
        request.method == "eth_sendTransaction"
    }

    // MARK: - Transaction Section

    @ViewBuilder
    private func transactionSection(_ txDetails: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // To address
            if let to = txDetails["to"] as? String {
                row(label: "To", value: truncateAddress(to), mono: true)
            }

            // Data indicator
            if let data = txDetails["data"] as? String, data != "0x", data.count > 2 {
                row(label: "Data", value: "\(data.count / 2 - 1) bytes", mono: false)
            }

            Divider()

            // Value
            let txValue = txValueInETH(txDetails)
            row(label: "Value", value: formatETHAndUSD(txValue))

            // Gas / Fee
            if isEstimatingGas {
                HStack {
                    Text("Network Fee")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Estimating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let gasError = gasError {
                row(label: "Network Fee", value: "Error: \(gasError)")
            } else if let gasLimit = estimatedGasLimit, let gp = gasPrice {
                let gasCostWei = gasLimit * gp
                let gasCostETH = weiToETH(gasCostWei)
                let gasPriceGwei = weiToGwei(gp)

                row(label: "Gas Limit", value: gasLimit.description)
                row(label: "Max Fee", value: String(format: "%.2f Gwei", gasPriceGwei))
                row(label: "Network Fee", value: formatETHAndUSD(gasCostETH))

                Divider()

                // Total
                let totalETH = txValue + gasCostETH
                HStack {
                    Text("Total")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(formatETHAndUSD(totalETH))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func row(label: String, value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .caption.monospaced() : .caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Transaction Simulation

    private func simulateTransaction() async {
        guard let txDetails = extractTransactionDetails(),
              let from = walletViewModel.selectedAccount?.address,
              let to = txDetails["to"] as? String else {
            return
        }

        await MainActor.run {
            isSimulating = true
        }

        let valueHex = txDetails["value"] as? String ?? "0x0"
        let valueClean = valueHex.hasPrefix("0x") ? String(valueHex.dropFirst(2)) : valueHex
        let value = BigUInt(valueClean, radix: 16) ?? BigUInt(0)

        var txData: Data?
        if let dataHex = txDetails["data"] as? String, dataHex != "0x" {
            let clean = dataHex.hasPrefix("0x") ? String(dataHex.dropFirst(2)) : dataHex
            txData = Data(hexString: clean)
        }

        let chainId = NetworkManager.shared.selectedNetwork.id

        do {
            let result = try await TransactionSimulationService.shared.simulate(
                from: from,
                to: to,
                value: value,
                data: txData,
                chainId: chainId
            )

            await MainActor.run {
                self.simulationResult = result
                self.isSimulating = false
            }
        } catch {
            await MainActor.run {
                self.simulationResult = SimulationResult(
                    success: true,
                    balanceChanges: [],
                    approvalChanges: [],
                    nftTransfers: [],
                    riskWarnings: [.simulationFailed(reason: error.localizedDescription)],
                    gasUsed: BigUInt(0),
                    revertReason: nil
                )
                self.isSimulating = false
            }
        }
    }

    // MARK: - Security Check

    private func checkSecurity() async {
        guard let txDetails = extractTransactionDetails(),
              let to = txDetails["to"] as? String else {
            return
        }

        isCheckingSecurity = true
        let chainId = NetworkManager.shared.selectedNetwork.id
        let warnings = await PhishingProtectionService.shared.checkRecipient(to, chainId: chainId)

        // Check for unlimited approval
        if let data = txDetails["data"] as? String, data.count > 10 {
            // Check if this is an approve() call (function selector: 0x095ea7b3)
            if data.lowercased().hasPrefix("0x095ea7b3") {
                // Check if amount is max uint256 (unlimited)
                let amountHex = String(data.dropFirst(74)) // Skip selector + address
                if amountHex.contains("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff") {
                    let tokenAddress = txDetails["to"] as? String ?? "Unknown"
                    securityWarnings.append(.unlimitedApproval(token: tokenAddress, spender: to))
                }
            }
        }

        await MainActor.run {
            self.securityWarnings.append(contentsOf: warnings)
            self.isCheckingSecurity = false
        }
    }

    // MARK: - Gas Estimation

    private func estimateGas() async {
        guard let txDetails = extractTransactionDetails() else {
            isEstimatingGas = false
            return
        }

        do {
            let network = NetworkManager.shared.selectedNetwork
            let web3Service = Web3Service(network: network)

            let to = txDetails["to"] as? String ?? ""
            let valueHex = txDetails["value"] as? String ?? "0x0"
            let dataHex = txDetails["data"] as? String

            let valueClean = valueHex.hasPrefix("0x") ? String(valueHex.dropFirst(2)) : valueHex
            let valueBigUInt = BigUInt(valueClean, radix: 16) ?? BigUInt(0)

            var txData: Data?
            if let dataHex = dataHex, dataHex != "0x" {
                let clean = dataHex.hasPrefix("0x") ? String(dataHex.dropFirst(2)) : dataHex
                txData = Data(hexString: clean)
            }

            let txRequest = TransactionRequest(
                from: walletViewModel.selectedAccount?.address ?? "",
                to: to,
                value: valueBigUInt,
                data: txData,
                chainId: network.id
            )

            async let gasEst = web3Service.estimateGas(for: txRequest)
            async let baseFeeEst = web3Service.getGasPrice()

            let (rawGasLimit, baseFee) = try await (gasEst, baseFeeEst)

            // 30% gas buffer (matches sendTransactionFromDict)
            let bufferedGasLimit = rawGasLimit * 130 / 100
            // EIP-1559: maxFee = baseFee*2 + 1.5 Gwei tip
            let tip = BigUInt(1_500_000_000)
            let maxFee = baseFee * 2 + tip

            await MainActor.run {
                estimatedGasLimit = bufferedGasLimit
                gasPrice = maxFee
                isEstimatingGas = false
            }
        } catch {
            await MainActor.run {
                gasError = error.localizedDescription
                isEstimatingGas = false
            }
        }
    }

    // MARK: - Helpers

    private var requestIcon: String {
        switch request.method {
        case "personal_sign", "eth_sign":
            return "signature"
        case "eth_sendTransaction":
            return "arrow.up.circle"
        case "eth_signTypedData", "eth_signTypedData_v4":
            return "doc.text"
        default:
            return "questionmark.circle"
        }
    }

    private var requestTitle: String {
        switch request.method {
        case "personal_sign":
            return "Sign Message"
        case "eth_sign":
            return "Sign Data"
        case "eth_signTypedData", "eth_signTypedData_v4":
            return "Sign Typed Data"
        case "eth_sendTransaction":
            return "Send Transaction"
        default:
            return "Sign Request"
        }
    }

    private func extractMessage() -> String? {
        switch request.method {
        case "personal_sign":
            guard let hexMessage = request.params.first as? String else { return nil }
            return hexToString(hexMessage) ?? hexMessage

        case "eth_sign":
            guard request.params.count >= 2,
                  let hexMessage = request.params[1] as? String else { return nil }
            return hexToString(hexMessage) ?? hexMessage

        default:
            return nil
        }
    }

    private func extractTransactionDetails() -> [String: Any]? {
        guard request.method == "eth_sendTransaction",
              let txDict = request.params.first as? [String: Any] else {
            return nil
        }
        return txDict
    }

    private func hexToString(_ hex: String) -> String? {
        let clean = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard let data = Data(hexString: clean) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func txValueInETH(_ txDetails: [String: Any]) -> Double {
        guard let valueHex = txDetails["value"] as? String else { return 0 }
        let clean = valueHex.hasPrefix("0x") ? String(valueHex.dropFirst(2)) : valueHex
        guard let value = BigUInt(clean, radix: 16) else { return 0 }
        return weiToETH(value)
    }

    private func weiToETH(_ wei: BigUInt) -> Double {
        let divisor = BigUInt(10).power(18)
        let wholePart = wei / divisor
        let remainder = wei % divisor
        let wholeDouble = Double(wholePart.description) ?? 0
        let remainderDouble = (Double(remainder.description) ?? 0) / 1e18
        return wholeDouble + remainderDouble
    }

    private func weiToGwei(_ wei: BigUInt) -> Double {
        let divisor = BigUInt(10).power(9)
        let wholePart = wei / divisor
        let remainder = wei % divisor
        let wholeDouble = Double(wholePart.description) ?? 0
        let remainderDouble = (Double(remainder.description) ?? 0) / 1e9
        return wholeDouble + remainderDouble
    }

    private func formatETHAndUSD(_ ethAmount: Double) -> String {
        let ethStr: String
        if ethAmount == 0 {
            ethStr = "0 ETH"
        } else if ethAmount < 0.000001 {
            ethStr = String(format: "%.10f ETH", ethAmount)
        } else {
            ethStr = String(format: "%.6f ETH", ethAmount)
        }

        let ethPrice = priceService.ethPrice
        if ethPrice > 0 {
            let usd = priceService.formatUSD(priceService.ethToUSD(ethAmount))
            return "\(ethStr) (\(usd))"
        }
        return ethStr
    }

    private func truncateAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Signing

    private func sign() {
        guard let account = walletViewModel.selectedAccount else {
            error = "No account selected"
            return
        }

        isSigning = true
        error = nil

        Task {
            do {
                let privateKey = try await walletViewModel.getPrivateKey(for: account)
                let web3Service = Web3Service()

                let result: String

                switch request.method {
                case "personal_sign":
                    guard let message = request.params.first as? String else {
                        throw Web3ServiceError.transactionFailed("Invalid message")
                    }
                    result = try await web3Service.signPersonalMessage(message: message, privateKey: privateKey)

                case "eth_sign":
                    guard request.params.count >= 2,
                          let message = request.params[1] as? String else {
                        throw Web3ServiceError.transactionFailed("Invalid message")
                    }
                    result = try await web3Service.signMessage(message: message, privateKey: privateKey)

                case "eth_sendTransaction":
                    guard let txDict = request.params.first as? [String: Any] else {
                        throw Web3ServiceError.transactionFailed("Invalid transaction")
                    }
                    result = try await web3Service.sendTransactionFromDict(txDict, from: account.address, privateKey: privateKey)

                case "eth_signTypedData", "eth_signTypedData_v4":
                    guard request.params.count >= 2,
                          let typedData = request.params[1] as? String else {
                        throw Web3ServiceError.transactionFailed("Invalid typed data")
                    }
                    result = try await web3Service.signPersonalMessage(message: typedData, privateKey: privateKey)

                default:
                    throw Web3ServiceError.transactionFailed("Unsupported method: \(request.method)")
                }

                await MainActor.run {
                    onApprove(result)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isSigning = false
                }
            }
        }
    }
}

// MARK: - Data Extension

private extension Data {
    init?(hexString: String) {
        let hex = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard hex.count % 2 == 0 else { return nil }

        var data = Data()
        var index = hex.startIndex

        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else { return nil }
            data.append(byte)
            index = nextIndex
        }

        self = data
    }
}
