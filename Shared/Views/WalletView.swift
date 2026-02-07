import SwiftUI
import BigInt
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif
#if os(macOS)
import AppKit

/// Manages the browser window
@MainActor
class BrowserWindowManager {
    static let shared = BrowserWindowManager()
    private var browserWindow: NSWindow?
    private weak var walletViewModel: WalletViewModel?

    private init() {}

    func configure(walletViewModel: WalletViewModel) {
        self.walletViewModel = walletViewModel
    }

    private var browserViewModel: BrowserViewModel?

    func openBrowser(url: URL? = nil) {
        guard let walletVM = walletViewModel else { return }

        if let window = browserWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            // Navigate to URL if provided
            if let url = url {
                browserViewModel?.navigate(to: url.absoluteString)
            }
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Web Browser"
        window.center()

        // Create BrowserViewModel so we can navigate programmatically
        let browserVM = BrowserViewModel()
        self.browserViewModel = browserVM

        let contentView = HStack(spacing: 0) {
            BrowserView(viewModel: browserVM)
                .environmentObject(walletVM)
                .frame(minWidth: 600)
            Divider()
            WalletView()
                .environmentObject(walletVM)
                .frame(width: 440)
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.765, green: 1.0, blue: 0.0))

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        browserWindow = window

        // Navigate to URL after window is open
        if let url = url {
            browserVM.navigate(to: url.absoluteString)
        }
    }

    func openURL(_ url: URL) {
        openBrowser(url: url)
    }
}
#endif

/// Main wallet dashboard view
struct WalletView: View {
    @EnvironmentObject var viewModel: WalletViewModel
    @State private var showingCreateWallet = false
    @State private var showingImportWallet = false
    @State private var showingSendInline = false
    @State private var showingSendSheet = false
    @State private var showingReceive = false
    @State private var showingSettings = false
    @State private var selectedTab: WalletTab = .tokens
    @State private var showingAPIKeyWarning = false

    @AppStorage("dismissedAlchemyWarning") private var dismissedAlchemyWarning = false

    enum WalletTab: Hashable {
        case tokens, nfts, ethscriptions, connect, history
    }

    @State private var showingBrowser = false

    var body: some View {
        Group {
            if viewModel.isLoading {
                loadingView
            } else if showingSendInline {
                sendPanel
            } else if showingReceive {
                receivePanel
            } else if viewModel.wallet != nil {
                walletContent
            } else if viewModel.hasWallet && viewModel.wallet == nil {
                authRetryView
            } else {
                onboardingView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingCreateWallet) {
            CreateWalletSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingImportWallet) {
            ImportWalletSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(viewModel)
        }
        .sheet(isPresented: $showingSendSheet) {
            SendView(
                account: viewModel.selectedAccount,
                smartAccount: viewModel.smartAccountViewModel.getSmartAccount(for: viewModel.selectedAccount ?? Account(index: 0, address: "")),
                isSmartAccountEnabled: viewModel.smartAccountViewModel.isSmartAccountEnabled
            )
        }
        .alert("RPC Configuration Recommended", isPresented: $showingAPIKeyWarning) {
            Button("Open Settings") {
                showingSettings = true
            }
            Button("Remind Me Later", role: .cancel) {}
            Button("Don't Show Again") {
                dismissedAlchemyWarning = true
            }
        } message: {
            Text("Add a free Alchemy API key for reliable network access. Without it, you may experience slow or failed requests.")
        }
        .onAppear {
            checkAlchemyKey()
        }
    }

    private func checkAlchemyKey() {
        // Only show warning if wallet exists, key not configured, and not dismissed
        guard viewModel.wallet != nil,
              !dismissedAlchemyWarning,
              KeychainService.shared.retrieveAPIKey(for: "alchemy") == nil else {
            return
        }
        // Delay slightly so the view is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showingAPIKeyWarning = true
        }
    }

    // MARK: - Wallet Content

    @ViewBuilder
    private var walletContent: some View {
        VStack(spacing: 0) {
            // Header row 1: Account and Network
            HStack(spacing: 6) {
                AccountSwitcher(
                    accounts: viewModel.wallet?.accounts ?? [],
                    selectedAccount: $viewModel.selectedAccount
                )
                Spacer()
                NetworkSwitcher(selectedNetwork: $viewModel.selectedNetwork)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            // Header row 2: Total Holdings + Actions
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Total Holdings")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.balanceUSD)
                        .font(.title2.bold().monospacedDigit())
                        .foregroundColor(AppColors.accent)
                }

                Spacer()

                Button { showingSendSheet = true } label: {
                    Label("Send", systemImage: "arrow.up")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AccentButtonStyle())

                Button { showingReceive = true } label: {
                    Label("Receive", systemImage: "arrow.down")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(AccentButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            // Tab picker + Web button
            HStack(spacing: 4) {
                Picker("", selection: $selectedTab) {
                    Text("Tokens").tag(WalletTab.tokens)
                    Text("NFTs").tag(WalletTab.nfts)
                    Text("Inscribed").tag(WalletTab.ethscriptions)
                    Text("Connect").tag(WalletTab.connect)
                    Text("Tx").tag(WalletTab.history)
                }
                .pickerStyle(.segmented)
                .controlSize(.mini)

                Button { openBrowserWindow() } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(IconButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)

            Divider()

            // Content based on selection
            switch selectedTab {
            case .tokens:
                TokensView(account: viewModel.selectedAccount, ethBalance: viewModel.balance, ethBalanceUSD: viewModel.balanceUSD)
            case .nfts:
                NFTsView(account: viewModel.selectedAccount)
            case .ethscriptions:
                EthscriptionsView(account: viewModel.selectedAccount)
                    .environmentObject(viewModel)
            case .connect:
                WalletConnectView()
                    .environmentObject(viewModel)
            case .history:
                if let account = viewModel.selectedAccount {
                    TransactionHistoryView(
                        address: account.address,
                        chainId: viewModel.selectedNetwork.id
                    )
                }
            }
        }
    }

    // MARK: - Balance Section

    @ViewBuilder
    private var balanceSection: some View {
        VStack(spacing: 2) {
            Text("Total Balance")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(viewModel.balanceUSD)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                showingSendSheet = true
            } label: {
                Label("Send", systemImage: "arrow.up")
            }
            .buttonStyle(.primary)

            Button {
                showingReceive = true
            } label: {
                Label("Receive", systemImage: "arrow.down")
            }
            .buttonStyle(.secondary)

            Button {
                Task { await viewModel.refreshBalance() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    // MARK: - Toolbar Items

    @ViewBuilder
    private var toolbarItems: some View {
        Button {
            showingSettings = true
        } label: {
            Image(systemName: "gear")
        }
    }

    // MARK: - Send Panel (Inline)

    @State private var sendRecipient = ""
    @State private var sendAmount = ""
    @State private var sendSelectedAsset: SendAsset = .eth
    @State private var isSending = false
    @State private var sendError: String?
    @State private var sendSuccess: String?

    @ViewBuilder
    private var sendPanel: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) {
                    showingSendInline = false
                    sendRecipient = ""
                    sendAmount = ""
                    sendError = nil
                    sendSuccess = nil
                } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Send")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            if let success = sendSuccess {
                // Success view
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text("Sent!")
                        .font(.headline)

                    Text(success)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)

                    Button("Done") {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingSendInline = false
                            sendRecipient = ""
                            sendAmount = ""
                            sendError = nil
                            sendSuccess = nil
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        // Asset type
                        Picker("", selection: $sendSelectedAsset) {
                            ForEach(SendAsset.allCases) { asset in
                                Text(asset.displayName).tag(asset)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .padding(.horizontal, 10)

                        // Recipient
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recipient")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            TextField("Address", text: $sendRecipient)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                        }
                        .padding(.horizontal, 10)

                        // Amount (for ETH/Token)
                        if sendSelectedAsset == .eth || sendSelectedAsset == .token {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Amount")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    TextField("0.0", text: $sendAmount)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption.monospaced())
                                    Text(sendSelectedAsset == .eth ? "ETH" : "Token")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                        }

                        // Balance info
                        HStack {
                            Text("Balance")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(viewModel.balance)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(AppColors.accent)
                            Text("ETH")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)

                        if let error = sendError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 10)
                        }

                        // Send button
                        Button {
                            performSend()
                        } label: {
                            if isSending {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Send", systemImage: "arrow.up")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(sendRecipient.isEmpty || sendAmount.isEmpty || isSending)
                        .padding(.horizontal, 10)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func performSend() {
        guard let account = viewModel.selectedAccount else { return }
        isSending = true
        sendError = nil

        Task {
            do {
                let privateKey = try await viewModel.getPrivateKey(for: account)
                let web3 = Web3Service()

                // Parse ETH amount to Wei
                guard let weiAmount = parseEthAmount(sendAmount) else {
                    await MainActor.run {
                        isSending = false
                        sendError = "Invalid amount"
                    }
                    return
                }

                let transaction = try await web3.buildTransaction(
                    from: account.address,
                    to: sendRecipient,
                    value: weiAmount
                )
                let txHash = try await web3.sendTransaction(transaction, privateKey: privateKey)

                await MainActor.run {
                    isSending = false
                    sendSuccess = txHash
                    Task { await viewModel.refreshBalance() }
                }
            } catch {
                await MainActor.run {
                    isSending = false
                    sendError = error.localizedDescription
                }
            }
        }
    }

    private func parseEthAmount(_ amount: String) -> BigUInt? {
        let parts = amount.split(separator: ".")
        let integerPart = String(parts.first ?? "0")
        let fractionalPart = parts.count > 1 ? String(parts[1]) : ""

        // ETH has 18 decimals
        let decimals = 18
        let paddedFractional = fractionalPart.padding(toLength: decimals, withPad: "0", startingAt: 0)
        let fullString = integerPart + paddedFractional.prefix(decimals)

        return BigUInt(fullString)
    }

    // MARK: - Receive Panel (Inline)

    @State private var addressCopied = false

    @ViewBuilder
    private var receivePanel: some View {
        VStack(spacing: 0) {
            // Header with back button
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.15)) { showingReceive = false } } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                Text("Receive")
                    .font(.caption.bold())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // QR Code
                    if let account = viewModel.selectedAccount {
                        qrCodeImage(for: account.address)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .padding(12)
                            .background(Color.white)
                            .cornerRadius(12)
                    }

                    // Address
                    VStack(spacing: 4) {
                        Text("Your Address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let address = viewModel.selectedAccount?.address {
                            Text(address)
                                .font(.caption2.monospaced())
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 10)

                    // Copy button
                    Button {
                        copyAddress()
                    } label: {
                        Label(addressCopied ? "Copied!" : "Copy Address", systemImage: addressCopied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    // Warning
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption2)
                        Text("Only send ETH or EVM tokens to this address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func copyAddress() {
        guard let address = viewModel.selectedAccount?.address else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #else
        UIPasteboard.general.string = address
        #endif

        withAnimation { addressCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { addressCopied = false }
        }
    }

    #if canImport(CoreImage)
    private func qrCodeImage(for address: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(address.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return Image(systemName: "qrcode")
        }

        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
            return Image(systemName: "qrcode")
        }

        return Image(cgImage, scale: 1, label: Text("QR Code"))
    }
    #else
    private func qrCodeImage(for address: String) -> Image {
        return Image(systemName: "qrcode")
    }
    #endif

    // MARK: - Browser Window

    private func openBrowserWindow() {
        #if os(macOS)
        BrowserWindowManager.shared.configure(walletViewModel: viewModel)
        BrowserWindowManager.shared.openBrowser()
        #endif
    }

    // MARK: - Loading View

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()

            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Auth Retry View

    @ViewBuilder
    private var authRetryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "faceid")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Authentication Required")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Unlock your wallet to continue")
                .font(.body)
                .foregroundStyle(.secondary)

            if let error = viewModel.loadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }

            Button {
                Task { await viewModel.loadWallet() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: 160)
            }
            .buttonStyle(.primary)
        }
        .padding()
    }

    // MARK: - Onboarding View

    @ViewBuilder
    private var onboardingView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Welcome to PixelWallet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a new wallet or import an existing one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    showingCreateWallet = true
                } label: {
                    Text("Create New Wallet")
                        .frame(width: 160)
                }
                .buttonStyle(.primary)
                .disabled(viewModel.isLoading)

                Button {
                    showingImportWallet = true
                } label: {
                    Text("Import Wallet")
                        .frame(width: 160)
                }
                .buttonStyle(.secondary)
                .disabled(viewModel.isLoading)
            }

            Spacer()
        }
        .padding()
    }
}

// MARK: - Create Wallet Sheet

struct CreateWalletSheet: View {
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var wordCount: MnemonicWordCount = .twelve
    @State private var generatedMnemonic: String?
    @State private var hasConfirmedBackup = false
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let mnemonic = generatedMnemonic {
                    backupView(mnemonic: mnemonic)
                } else {
                    createOptionsView
                }
            }
            .padding()
            .navigationTitle("Create Wallet")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 320, minHeight: 380)
    }

    @ViewBuilder
    private var createOptionsView: some View {
        VStack(spacing: 24) {
            Text("Choose the security level for your wallet")
                .font(.headline)

            Picker("Word Count", selection: $wordCount) {
                Text("12 Words (Standard)").tag(MnemonicWordCount.twelve)
                Text("24 Words (Enhanced)").tag(MnemonicWordCount.twentyFour)
            }
            .pickerStyle(.segmented)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                createWallet()
            } label: {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Generate Wallet")
                }
            }
            .buttonStyle(.primary)
            .disabled(isCreating)
        }
    }

    @ViewBuilder
    private func backupView(mnemonic: String) -> some View {
        VStack(spacing: 16) {
            Text("Backup Your Recovery Phrase")
                .font(.headline)

            Text("Write down these words in order and store them safely. You will need them to recover your wallet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Display mnemonic words in grid
            let words = mnemonic.split(separator: " ").map(String.init)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    HStack {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(word)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Toggle("I have safely backed up my recovery phrase", isOn: $hasConfirmedBackup)

            Button("Continue") {
                dismiss()
            }
            .buttonStyle(.primary)
            .disabled(!hasConfirmedBackup)
        }
    }

    private func createWallet() {
        isCreating = true
        error = nil

        Task {
            do {
                let mnemonic = try await viewModel.createWallet(wordCount: wordCount)
                await MainActor.run {
                    self.generatedMnemonic = mnemonic
                    self.isCreating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isCreating = false
                }
            }
        }
    }
}

// MARK: - Import Wallet Sheet

struct ImportWalletSheet: View {
    @ObservedObject var viewModel: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var importMethod: ImportMethod = .mnemonic
    @State private var mnemonicInput: String = ""
    @State private var privateKeyInput: String = ""
    @State private var isImporting = false
    @State private var error: String?

    enum ImportMethod: String, CaseIterable {
        case mnemonic = "Recovery Phrase"
        case privateKey = "Private Key"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Import Method", selection: $importMethod) {
                    ForEach(ImportMethod.allCases, id: \.self) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                switch importMethod {
                case .mnemonic:
                    mnemonicImportView
                case .privateKey:
                    privateKeyImportView
                }

                if let error = error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Import Wallet")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 320, minHeight: 320)
    }

    @ViewBuilder
    private var mnemonicImportView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter your 12 or 24 word recovery phrase")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $mnemonicInput)
                .font(.body.monospaced())
                .frame(height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )

            Button {
                importMnemonic()
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Import Wallet")
                }
            }
            .buttonStyle(.primary)
            .disabled(mnemonicInput.isEmpty || isImporting)
        }
    }

    @ViewBuilder
    private var privateKeyImportView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your private key (with or without 0x prefix)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("Private Key", text: $privateKeyInput)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())

            Button {
                importPrivateKey()
            } label: {
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Import Account")
                }
            }
            .buttonStyle(.primary)
            .disabled(privateKeyInput.isEmpty || isImporting)
        }
    }

    private func importMnemonic() {
        isImporting = true
        error = nil

        Task {
            do {
                try await viewModel.importWallet(mnemonic: mnemonicInput.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isImporting = false
                }
            }
        }
    }

    private func importPrivateKey() {
        isImporting = true
        error = nil

        Task {
            do {
                try await viewModel.importFromPrivateKey(privateKeyInput.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isImporting = false
                }
            }
        }
    }
}

#Preview {
    WalletView()
        .environmentObject(WalletViewModel())
}
