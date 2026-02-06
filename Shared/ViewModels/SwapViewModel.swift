import Foundation
import Combine
import web3swift
import Web3Core
import BigInt

/// View model for token swaps
@MainActor
final class SwapViewModel: ObservableObject {
    // MARK: - Published State

    @Published var sellToken: SwapToken = .eth
    @Published var buyToken: SwapToken = .usdc
    @Published var sellAmount: String = ""

    @Published private(set) var quote: SwapQuote?
    @Published private(set) var isLoadingQuote = false
    @Published private(set) var quoteError: String?

    @Published var slippage: SlippageTolerance = .medium

    @Published private(set) var isApproving = false
    @Published private(set) var isSwapping = false
    @Published private(set) var swapError: String?
    @Published private(set) var lastSwapHash: String?

    @Published private(set) var sellTokenBalance: BigUInt = 0
    @Published private(set) var buyTokenBalance: BigUInt = 0
    @Published private(set) var needsApproval = false

    // MARK: - Dependencies

    private let swapService: SwapService
    private let tokenService: TokenService
    private let keychainService: KeychainService

    private var account: Account?
    private var chainId: Int = 1
    private var cancellables = Set<AnyCancellable>()
    private var quoteTask: Task<Void, Never>?

    // MARK: - Computed Properties

    var availableTokens: [SwapToken] {
        swapService.getAvailableTokens(chainId: chainId)
    }

    var isSwapSupported: Bool {
        swapService.isSupported(chainId: chainId)
    }

    var canSwap: Bool {
        quote != nil &&
        !isSwapping &&
        !isApproving &&
        !sellAmount.isEmpty &&
        parsedSellAmount > 0 &&
        parsedSellAmount <= sellTokenBalance
    }

    var formattedSellBalance: String {
        formatBalance(sellTokenBalance, decimals: sellToken.decimals, symbol: sellToken.symbol)
    }

    var formattedBuyBalance: String {
        formatBalance(buyTokenBalance, decimals: buyToken.decimals, symbol: buyToken.symbol)
    }

    private var parsedSellAmount: BigUInt {
        parseAmount(sellAmount, decimals: sellToken.decimals) ?? BigUInt(0)
    }

    // MARK: - Initialization

    init(
        swapService: SwapService = .shared,
        tokenService: TokenService = .shared,
        keychainService: KeychainService = .shared
    ) {
        self.swapService = swapService
        self.tokenService = tokenService
        self.keychainService = keychainService

        setupBindings()
    }

    private func setupBindings() {
        // Debounce sell amount changes to avoid too many API calls
        $sellAmount
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.fetchQuote() }
            }
            .store(in: &cancellables)

        // Refresh quote when tokens change
        $sellToken
            .combineLatest($buyToken)
            .dropFirst()
            .sink { [weak self] _, _ in
                Task {
                    await self?.refreshBalances()
                    await self?.fetchQuote()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Configuration

    func configure(account: Account, chainId: Int) {
        self.account = account
        self.chainId = chainId

        // Set default tokens for chain
        let tokens = availableTokens
        if let eth = tokens.first(where: { $0.isNativeETH }) {
            sellToken = eth
        }
        if let stable = tokens.first(where: { $0.symbol == "USDC" }) {
            buyToken = stable
        }

        Task {
            await refreshBalances()
        }
    }

    // MARK: - Balances

    func refreshBalances() async {
        guard let account = account else { return }

        // Get sell token balance
        if sellToken.isNativeETH {
            if let balance = try? await Web3Service().getBalance(for: account.address) {
                sellTokenBalance = balance
            }
        } else {
            let token = Token(
                address: sellToken.address,
                symbol: sellToken.symbol,
                name: sellToken.name,
                decimals: sellToken.decimals,
                logoURL: nil,
                chainId: chainId
            )
            if let balance = try? await tokenService.getBalance(of: token, for: account.address) {
                sellTokenBalance = BigUInt(balance.rawBalance) ?? BigUInt(0)
            }
        }

        // Get buy token balance
        if buyToken.isNativeETH {
            if let balance = try? await Web3Service().getBalance(for: account.address) {
                buyTokenBalance = balance
            }
        } else {
            let token = Token(
                address: buyToken.address,
                symbol: buyToken.symbol,
                name: buyToken.name,
                decimals: buyToken.decimals,
                logoURL: nil,
                chainId: chainId
            )
            if let balance = try? await tokenService.getBalance(of: token, for: account.address) {
                buyTokenBalance = BigUInt(balance.rawBalance) ?? BigUInt(0)
            }
        }
    }

    // MARK: - Quote

    func fetchQuote() async {
        quoteTask?.cancel()

        guard let account = account,
              !sellAmount.isEmpty,
              let amount = parseAmount(sellAmount, decimals: sellToken.decimals),
              amount > 0 else {
            quote = nil
            quoteError = nil
            needsApproval = false
            return
        }

        isLoadingQuote = true
        quoteError = nil

        quoteTask = Task {
            do {
                let newQuote = try await swapService.getQuote(
                    sellToken: sellToken,
                    buyToken: buyToken,
                    sellAmount: amount,
                    takerAddress: account.address,
                    slippage: slippage,
                    chainId: chainId
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.quote = newQuote
                    self.isLoadingQuote = false
                }

                // Check if approval is needed
                if let allowanceTarget = newQuote.allowanceTarget {
                    let needs = try await swapService.needsApproval(
                        token: sellToken,
                        owner: account.address,
                        spender: allowanceTarget,
                        amount: amount
                    )

                    await MainActor.run {
                        self.needsApproval = needs
                    }
                } else {
                    await MainActor.run {
                        self.needsApproval = false
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.quote = nil
                    self.quoteError = error.localizedDescription
                    self.isLoadingQuote = false
                }
            }
        }
    }

    // MARK: - Swap Tokens

    func swapTokens() {
        let temp = sellToken
        sellToken = buyToken
        buyToken = temp
        sellAmount = ""
        quote = nil
    }

    // MARK: - Set Max

    func setMaxAmount() {
        guard sellTokenBalance > 0 else { return }

        // Leave some ETH for gas if selling ETH
        var maxAmount = sellTokenBalance
        if sellToken.isNativeETH {
            let gasBuffer = BigUInt(50000) * BigUInt(50_000_000_000) // 50k gas * 50 gwei
            if maxAmount > gasBuffer {
                maxAmount -= gasBuffer
            } else {
                maxAmount = 0
            }
        }

        sellAmount = formatAmountForInput(maxAmount, decimals: sellToken.decimals)
    }

    // MARK: - Approval

    func approve() async throws {
        guard let account = account,
              let quote = quote,
              let allowanceTarget = quote.allowanceTarget else {
            throw SwapError.invalidRequest
        }

        isApproving = true
        swapError = nil

        do {
            let privateKey = try await getPrivateKey(for: account)

            // Approve only the exact amount needed (safer than unlimited approval)
            let approvalAmount = parsedSellAmount
            let (to, data, value) = try await swapService.buildApprovalTransaction(
                token: sellToken.address,
                spender: allowanceTarget,
                amount: approvalAmount,
                from: account.address
            )

            let web3Service = Web3Service()
            let transaction = try await web3Service.buildTransaction(
                from: account.address,
                to: to,
                value: value,
                data: data
            )

            _ = try await web3Service.sendTransaction(transaction, privateKey: privateKey)

            await MainActor.run {
                self.needsApproval = false
                self.isApproving = false
            }
        } catch {
            await MainActor.run {
                self.swapError = error.localizedDescription
                self.isApproving = false
            }
            throw error
        }
    }

    // MARK: - Execute Swap

    func executeSwap() async throws -> String {
        guard let account = account,
              let quote = quote else {
            throw SwapError.invalidRequest
        }

        isSwapping = true
        swapError = nil
        lastSwapHash = nil

        do {
            let privateKey = try await getPrivateKey(for: account)

            let txHash = try await swapService.executeSwap(
                quote: quote,
                from: account.address,
                privateKey: privateKey
            )

            await MainActor.run {
                self.lastSwapHash = txHash
                self.isSwapping = false
                self.sellAmount = ""
                self.quote = nil
            }

            // Refresh balances after swap
            await refreshBalances()

            return txHash
        } catch {
            await MainActor.run {
                self.swapError = error.localizedDescription
                self.isSwapping = false
            }
            throw error
        }
    }

    // MARK: - Helpers

    private func getPrivateKey(for account: Account) async throws -> Data {
        let seed = try await keychainService.retrieveSeed()

        guard let keystore = try? BIP32Keystore(
            seed: seed,
            password: "",
            prefixPath: "m/44'/60'/0'/0"
        ) else {
            throw SwapError.swapFailed("Failed to derive keystore")
        }

        guard let address = EthereumAddress(account.address),
              let privateKey = try? keystore.UNSAFE_getPrivateKeyData(
                password: "",
                account: address
              ) else {
            throw SwapError.swapFailed("Failed to get private key")
        }

        return privateKey
    }

    private func parseAmount(_ amount: String, decimals: Int) -> BigUInt? {
        let trimmed = amount.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let components = trimmed.split(separator: ".")
        guard components.count <= 2 else { return nil }

        let wholePart = BigUInt(String(components[0])) ?? BigUInt(0)

        let fractionalPart: BigUInt
        if components.count == 2 {
            var fractionalString = String(components[1])
            if fractionalString.count > decimals {
                fractionalString = String(fractionalString.prefix(decimals))
            } else {
                fractionalString += String(repeating: "0", count: decimals - fractionalString.count)
            }
            fractionalPart = BigUInt(fractionalString) ?? BigUInt(0)
        } else {
            fractionalPart = BigUInt(0)
        }

        let multiplier = BigUInt(10).power(decimals)
        return wholePart * multiplier + fractionalPart
    }

    private func formatBalance(_ balance: BigUInt, decimals: Int, symbol: String) -> String {
        let divisor = BigUInt(10).power(decimals)
        let whole = balance / divisor
        let frac = balance % divisor

        if frac == 0 {
            return "\(whole) \(symbol)"
        }

        let fracStr = String(frac).prefix(4)
        return "\(whole).\(fracStr) \(symbol)"
    }

    private func formatAmountForInput(_ amount: BigUInt, decimals: Int) -> String {
        let divisor = BigUInt(10).power(decimals)
        let whole = amount / divisor
        let frac = amount % divisor

        if frac == 0 {
            return whole.description
        }

        let fracStr = String(frac).prefix(decimals)
        return "\(whole).\(fracStr)"
    }
}
