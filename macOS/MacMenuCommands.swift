import SwiftUI

/// Custom menu commands for the macOS app
struct MacMenuCommands: Commands {
    @ObservedObject var walletViewModel: WalletViewModel

    var body: some Commands {
        // Replace the default New menu
        CommandGroup(replacing: .newItem) {
            Button("New Account") {
                Task {
                    try? await walletViewModel.addAccount()
                }
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(!walletViewModel.hasWallet)
        }

        // Wallet menu
        CommandMenu("Wallet") {
            Button("Refresh Balance") {
                Task {
                    await walletViewModel.refreshBalance()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!walletViewModel.hasWallet)

            Divider()

            // Account submenu
            if let accounts = walletViewModel.wallet?.accounts, !accounts.isEmpty {
                Menu("Switch Account") {
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
                }
            }

            // Network submenu
            Menu("Switch Network") {
                ForEach(Network.defaults, id: \.id) { network in
                    Button {
                        walletViewModel.selectedNetwork = network
                    } label: {
                        HStack {
                            Text(network.name)
                            if network.isTestnet {
                                Text("(Testnet)")
                            }
                            if network.id == walletViewModel.selectedNetwork.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Copy Address") {
                if let address = walletViewModel.selectedAccount?.address {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(walletViewModel.selectedAccount == nil)
        }

        // Transaction menu
        CommandMenu("Transaction") {
            Button("Send...") {
                // Would open send sheet
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!walletViewModel.hasWallet)

            Button("Receive...") {
                // Would open receive sheet
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .disabled(!walletViewModel.hasWallet)

            Divider()

            Button("Create Ethscription...") {
                // Would open create sheet
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(!walletViewModel.hasWallet)
        }

        // Help menu additions
        CommandGroup(after: .help) {
            Divider()

            Link("Ethscriptions Documentation", destination: URL(string: "https://docs.ethscriptions.com")!)

            Link("View on GitHub", destination: URL(string: "https://github.com/ethscriptions-protocol")!)
        }
    }
}
