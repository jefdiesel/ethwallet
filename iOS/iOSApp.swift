import SwiftUI

/// Main entry point for the iOS application
@main
struct EthWalletApp: App {
    @StateObject private var walletViewModel = WalletViewModel()
    @StateObject private var networkManager = NetworkManager.shared
    @StateObject private var priceService = PriceService.shared

    var body: some Scene {
        WindowGroup {
            iOSRootView()
                .environmentObject(walletViewModel)
                .environmentObject(networkManager)
                .environmentObject(priceService)
        }
    }
}

/// iOS-specific root view with tab navigation
struct iOSRootView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel

    @State private var selectedTab: Tab = .wallet

    enum Tab {
        case wallet
        case tokens
        case nfts
        case ethscriptions
        case settings
    }

    var body: some View {
        Group {
            if walletViewModel.hasWallet {
                mainTabView
            } else {
                iOSOnboardingView()
            }
        }
    }

    @ViewBuilder
    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            iOSWalletTab()
                .tabItem {
                    Label("Wallet", systemImage: "wallet.pass")
                }
                .tag(Tab.wallet)

            TokensView(account: walletViewModel.selectedAccount)
                .tabItem {
                    Label("Tokens", systemImage: "dollarsign.circle")
                }
                .tag(Tab.tokens)

            NFTsView(account: walletViewModel.selectedAccount)
                .tabItem {
                    Label("NFTs", systemImage: "square.stack.3d.up")
                }
                .tag(Tab.nfts)

            EthscriptionsView(account: walletViewModel.selectedAccount)
                .tabItem {
                    Label("Ethscriptions", systemImage: "photo.on.rectangle")
                }
                .tag(Tab.ethscriptions)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
    }
}

/// iOS wallet tab view
struct iOSWalletTab: View {
    @EnvironmentObject var walletViewModel: WalletViewModel
    @EnvironmentObject var networkManager: NetworkManager

    @State private var showingSend = false
    @State private var showingReceive = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Account card
                    accountCard

                    // Balance
                    balanceCard

                    // Quick actions
                    quickActions

                    // Recent transactions placeholder
                    recentTransactionsSection
                }
                .padding()
            }
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    networkPicker
                }
                ToolbarItem(placement: .topBarTrailing) {
                    accountPicker
                }
            }
        }
        .sheet(isPresented: $showingSend) {
            SendView(account: walletViewModel.selectedAccount)
        }
        .sheet(isPresented: $showingReceive) {
            ReceiveView(account: walletViewModel.selectedAccount)
        }
    }

    @ViewBuilder
    private var accountCard: some View {
        if let account = walletViewModel.selectedAccount {
            VStack(spacing: 8) {
                Text(account.label)
                    .font(.headline)

                Text(account.shortAddress)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(16)
        }
    }

    @ViewBuilder
    private var balanceCard: some View {
        VStack(spacing: 8) {
            Text(walletViewModel.balance)
                .font(.system(size: 40, weight: .semibold, design: .rounded))

            Text(walletViewModel.selectedNetwork.currencySymbol)
                .font(.title3)
                .foregroundStyle(.secondary)

            Text(walletViewModel.balanceUSD)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 32)
    }

    @ViewBuilder
    private var quickActions: some View {
        HStack(spacing: 16) {
            Button {
                showingSend = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                    Text("Send")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            Button {
                showingReceive = true
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title)
                    Text("Receive")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
            }

            Button {
                Task { await walletViewModel.refreshBalance() }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title)
                    Text("Refresh")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(12)
            }
        }
    }

    @ViewBuilder
    private var recentTransactionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            Text("No recent transactions")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
        }
    }

    @ViewBuilder
    private var networkPicker: some View {
        Menu {
            ForEach(Network.defaults, id: \.id) { network in
                Button {
                    walletViewModel.selectedNetwork = network
                } label: {
                    HStack {
                        Text(network.name)
                        if network.id == walletViewModel.selectedNetwork.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(networkManager.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(walletViewModel.selectedNetwork.name)
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var accountPicker: some View {
        if let accounts = walletViewModel.wallet?.accounts {
            Menu {
                ForEach(accounts) { account in
                    Button {
                        walletViewModel.selectedAccount = account
                    } label: {
                        HStack {
                            Text(account.label)
                            if account.id == walletViewModel.selectedAccount?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    Task { try? await walletViewModel.addAccount() }
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
            } label: {
                Image(systemName: "person.circle")
            }
        }
    }
}

/// iOS onboarding view
struct iOSOnboardingView: View {
    @EnvironmentObject var walletViewModel: WalletViewModel

    @State private var showingCreate = false
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // Logo
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)

                // Title
                VStack(spacing: 8) {
                    Text("EthWallet")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Your Ethereum & Ethscriptions Wallet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Buttons
                VStack(spacing: 16) {
                    Button {
                        showingCreate = true
                    } label: {
                        Text("Create New Wallet")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showingImport = true
                    } label: {
                        Text("Import Wallet")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingCreate) {
            CreateWalletSheet(viewModel: walletViewModel)
        }
        .sheet(isPresented: $showingImport) {
            ImportWalletSheet(viewModel: walletViewModel)
        }
    }
}
