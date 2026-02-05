import SwiftUI

/// Dropdown for switching between networks
struct NetworkSwitcher: View {
    @Binding var selectedNetwork: Network
    @StateObject private var networkManager = NetworkManager.shared

    @State private var showingAddNetwork = false

    var body: some View {
        Menu {
            // Default networks section
            Section("Networks") {
                ForEach(Network.defaults, id: \.id) { network in
                    networkButton(network)
                }
            }

            // Custom networks section (if any)
            let customNetworks = networkManager.networks.filter { network in
                !Network.defaults.contains { $0.id == network.id }
            }

            if !customNetworks.isEmpty {
                Section("Custom Networks") {
                    ForEach(customNetworks, id: \.id) { network in
                        networkButton(network)
                    }
                }
            }

            Divider()

            Button {
                showingAddNetwork = true
            } label: {
                Label("Add Custom Network", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 8) {
                // Network indicator
                Circle()
                    .fill(networkStatusColor)
                    .frame(width: 8, height: 8)

                Text(selectedNetwork.name)
                    .fontWeight(.medium)

                if selectedNetwork.isTestnet {
                    Text("Testnet")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .cornerRadius(4)
                }

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .sheet(isPresented: $showingAddNetwork) {
            AddNetworkSheet()
        }
    }

    @ViewBuilder
    private func networkButton(_ network: Network) -> some View {
        Button {
            selectedNetwork = network
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(network.name)
                        if network.isTestnet {
                            Text("Testnet")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text("Chain ID: \(network.id)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if network.id == selectedNetwork.id {
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var networkStatusColor: Color {
        networkManager.isConnected ? .green : .red
    }
}

// MARK: - Add Network Sheet

struct AddNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var networkManager = NetworkManager.shared

    @State private var name: String = ""
    @State private var chainId: String = ""
    @State private var rpcURL: String = ""
    @State private var currencySymbol: String = "ETH"
    @State private var explorerURL: String = ""
    @State private var isTestnet: Bool = false

    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?
    @State private var error: String?

    enum TestResult {
        case success(blockNumber: UInt64)
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Network Details") {
                    TextField("Network Name", text: $name)
                    TextField("Chain ID", text: $chainId)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    TextField("RPC URL", text: $rpcURL)
                    TextField("Currency Symbol", text: $currencySymbol)
                    TextField("Block Explorer URL (optional)", text: $explorerURL)
                    Toggle("Testnet", isOn: $isTestnet)
                }

                Section {
                    if let result = testResult {
                        switch result {
                        case .success(let blockNumber):
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Connected - Block #\(blockNumber)")
                            }
                        case .failure(let message):
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(message)
                            }
                        }
                    }

                    Button {
                        testConnection()
                    } label: {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(rpcURL.isEmpty || isTesting)
                }

                if let error = error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Network")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addNetwork()
                    }
                    .disabled(!canAdd)
                }
            }
            #endif
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private var canAdd: Bool {
        !name.isEmpty &&
        !chainId.isEmpty &&
        !rpcURL.isEmpty &&
        Int(chainId) != nil &&
        URL(string: rpcURL) != nil
    }

    private func testConnection() {
        guard let url = URL(string: rpcURL) else {
            testResult = .failure("Invalid URL")
            return
        }

        isTesting = true
        testResult = nil

        Task {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "jsonrpc": "2.0",
                    "method": "eth_blockNumber",
                    "params": [],
                    "id": 1
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)

                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let result = json["result"] as? String,
                   let blockNumber = UInt64(result.dropFirst(2), radix: 16) {
                    await MainActor.run {
                        testResult = .success(blockNumber: blockNumber)
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testResult = .failure("Invalid response")
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = .failure(error.localizedDescription)
                    isTesting = false
                }
            }
        }
    }

    private func addNetwork() {
        guard let chainIdInt = Int(chainId),
              let url = URL(string: rpcURL) else {
            error = "Invalid network configuration"
            return
        }

        let network = Network(
            chainId: chainIdInt,
            name: name,
            rpcURLString: url.absoluteString,
            currencySymbol: currencySymbol,
            explorerURLString: explorerURL.isEmpty ? nil : explorerURL,
            isTestnet: isTestnet
        )

        networkManager.addCustomNetwork(network)
        dismiss()
    }
}

// MARK: - Network Status View

struct NetworkStatusView: View {
    @StateObject private var networkManager = NetworkManager.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(networkManager.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(networkManager.selectedNetwork.name)
                    .font(.caption)
                    .fontWeight(.medium)

                if networkManager.isConnected {
                    Text("Block #\(networkManager.blockNumber)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Disconnected")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            if networkManager.latency > 0 {
                Text("\(Int(networkManager.latency * 1000))ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NetworkSwitcher(selectedNetwork: .constant(.ethereum))
}
