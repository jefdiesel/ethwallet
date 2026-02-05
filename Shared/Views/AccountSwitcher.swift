import SwiftUI

/// Dropdown for switching between accounts
struct AccountSwitcher: View {
    let accounts: [Account]
    @Binding var selectedAccount: Account?

    @State private var showingAccountList = false
    @State private var showingAddAccount = false

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    selectedAccount = account
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.label)
                            Text(account.shortAddress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if account.id == selectedAccount?.id {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                showingAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedAccount?.label ?? "No Account")
                        .font(.headline)
                    Text(selectedAccount?.shortAddress ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountSheet()
        }
    }
}

// MARK: - Add Account Sheet

struct AddAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = WalletViewModel()

    @State private var isAdding = false
    @State private var error: String?
    @State private var newAccount: Account?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let account = newAccount {
                    successView(account: account)
                } else {
                    addAccountView
                }
            }
            .padding()
            .navigationTitle("Add Account")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 350, minHeight: 250)
    }

    @ViewBuilder
    private var addAccountView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Derive a new account from your wallet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button {
                addAccount()
            } label: {
                if isAdding {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAdding)
        }
    }

    @ViewBuilder
    private func successView(account: Account) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Account Added")
                .font(.headline)

            VStack(spacing: 4) {
                Text(account.label)
                    .fontWeight(.medium)
                Text(account.address)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func addAccount() {
        isAdding = true
        error = nil

        Task {
            do {
                try await viewModel.addAccount()
                await MainActor.run {
                    self.newAccount = viewModel.wallet?.accounts.last
                    self.isAdding = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isAdding = false
                }
            }
        }
    }
}

// MARK: - Account List View

struct AccountListView: View {
    let accounts: [Account]
    @Binding var selectedAccount: Account?
    var onAddAccount: () -> Void

    var body: some View {
        List(selection: $selectedAccount) {
            ForEach(accounts) { account in
                AccountRow(account: account, isSelected: account.id == selectedAccount?.id)
                    .tag(account)
            }

            Button {
                onAddAccount()
            } label: {
                Label("Add Account", systemImage: "plus")
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: Account
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Account icon with index
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Text("\(account.index + 1)")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(account.label)
                    .fontWeight(.medium)

                Text(account.shortAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account Detail View

struct AccountDetailView: View {
    let account: Account
    @State private var isEditingLabel = false
    @State private var editedLabel: String = ""
    var onRename: (String) -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Account icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)

                Text("\(account.index + 1)")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
            }

            // Label (editable)
            if isEditingLabel {
                HStack {
                    TextField("Account Name", text: $editedLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)

                    Button("Save") {
                        onRename(editedLabel)
                        isEditingLabel = false
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Cancel") {
                        isEditingLabel = false
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack {
                    Text(account.label)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Button {
                        editedLabel = account.label
                        isEditingLabel = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                }
            }

            // Address
            VStack(spacing: 4) {
                Text("Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(account.address)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // Derivation path
            VStack(spacing: 4) {
                Text("Derivation Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(account.derivationPath)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

#Preview {
    AccountSwitcher(
        accounts: [
            Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"),
            Account(index: 1, address: "0xabcdef1234567890abcdef1234567890abcdef12")
        ],
        selectedAccount: .constant(Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678"))
    )
}
