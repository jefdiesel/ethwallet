import Foundation
import CryptoKit

/// Service for phishing and scam protection
/// Checks domains and addresses against known phishing lists and warns about suspicious activity
final class PhishingProtectionService {
    static let shared = PhishingProtectionService()

    /// MetaMask phishing list URL
    private let phishingListURL = URL(string: "https://raw.githubusercontent.com/MetaMask/eth-phishing-detect/master/src/config.json")!

    /// Etherscan API for contract verification
    private let etherscanAPIKey = "" // Optional: Add API key for higher rate limits

    /// Cache for phishing list (updated daily)
    private var phishingDomains: Set<String> = []
    private var phishingAddresses: Set<String> = []
    private var allowedDomains: Set<String> = []
    private var lastFetchTime: Date?
    private let cacheExpiry: TimeInterval = 24 * 60 * 60 // 24 hours

    /// Known legitimate domains for common DeFi protocols
    private let trustedDomains: Set<String> = [
        "uniswap.org",
        "app.uniswap.org",
        "aave.com",
        "app.aave.com",
        "compound.finance",
        "app.compound.finance",
        "curve.fi",
        "opensea.io",
        "looksrare.org",
        "blur.io",
        "etherscan.io",
        "basescan.org"
    ]

    /// Homoglyph characters that look like ASCII letters
    private let homoglyphs: [Character: [Character]] = [
        "a": ["а", "ɑ", "α", "а"],  // Cyrillic and Greek
        "e": ["е", "ε", "е"],
        "o": ["о", "ο", "о", "0"],
        "c": ["с", "ϲ"],
        "p": ["р", "ρ"],
        "x": ["х", "χ"],
        "y": ["у", "γ"],
        "i": ["і", "ι", "1", "l"],
        "s": ["ѕ"],
        "n": ["η"],
        "u": ["υ", "µ"]
    ]

    private init() {
        // Load cached data if available
        loadCachedData()
    }

    // MARK: - Public API

    /// Check a domain for phishing risks
    func checkDomain(_ domain: String) async -> [SecurityWarning] {
        var warnings: [SecurityWarning] = []

        // Ensure phishing list is loaded
        await refreshPhishingListIfNeeded()

        let normalizedDomain = normalizeDomain(domain)

        // Check against phishing list
        if phishingDomains.contains(normalizedDomain) {
            warnings.append(.knownPhishingDomain(domain: domain))
        }

        // Check for homoglyph attacks
        if let lookalike = detectHomoglyphDomain(domain) {
            warnings.append(.homoglyphDomain(domain: domain, looksLike: lookalike))
        }

        // Check if domain is on allowlist
        if allowedDomains.contains(normalizedDomain) || trustedDomains.contains(normalizedDomain) {
            // Domain is trusted, remove any false positives
            warnings.removeAll { warning in
                if case .homoglyphDomain = warning {
                    return true
                }
                return false
            }
        }

        return warnings
    }

    /// Check an address for known scams and suspicious activity
    func checkAddress(_ address: String) async -> [SecurityWarning] {
        var warnings: [SecurityWarning] = []
        let normalizedAddress = address.lowercased()

        // Ensure phishing list is loaded
        await refreshPhishingListIfNeeded()

        // Check against known scam addresses
        if phishingAddresses.contains(normalizedAddress) {
            warnings.append(.knownScamAddress(address: address))
        }

        return warnings
    }

    /// Check if an address is a contract (has code deployed)
    func isContract(_ address: String, chainId: Int = 1) async -> Bool {
        let explorerAPI: String
        switch chainId {
        case 1:
            explorerAPI = "https://api.etherscan.io/api"
        case 8453:
            explorerAPI = "https://api.basescan.org/api"
        case 11155111:
            explorerAPI = "https://api-sepolia.etherscan.io/api"
        default:
            return false // Can't check for unsupported chains
        }

        guard let url = URL(string: "\(explorerAPI)?module=proxy&action=eth_getCode&address=\(address)&tag=latest") else {
            return false
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? String else {
                return false
            }
            // EOAs return "0x", contracts return actual bytecode starting with "0x"
            // Etherscan may return error messages like "You are using..." on rate limit
            return result.hasPrefix("0x") && result != "0x" && result.count > 2
        } catch {
            return false
        }
    }

    /// Check if a contract is verified on Etherscan
    func isContractVerified(_ address: String, chainId: Int = 1) async -> Bool {
        // First check if it's actually a contract
        let hasCode = await isContract(address, chainId: chainId)
        if !hasCode {
            return true // EOAs don't need verification - they're not contracts
        }

        let explorerAPI: String
        switch chainId {
        case 1:
            explorerAPI = "https://api.etherscan.io/api"
        case 8453:
            explorerAPI = "https://api.basescan.org/api"
        case 11155111:
            explorerAPI = "https://api-sepolia.etherscan.io/api"
        default:
            return true // Can't verify for unsupported chains
        }

        guard let url = URL(string: "\(explorerAPI)?module=contract&action=getabi&address=\(address)") else {
            return true
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                return true
            }
            return status == "1" // Status 1 means verified
        } catch {
            #if DEBUG
            print("[PhishingProtection] Failed to check contract verification: \(error)")
            #endif
            return true // Assume verified on error to avoid false positives
        }
    }

    /// Get contract age in days (returns nil if not a contract or error)
    func getContractAge(_ address: String, chainId: Int = 1) async -> Int? {
        let explorerAPI: String
        switch chainId {
        case 1:
            explorerAPI = "https://api.etherscan.io/api"
        case 8453:
            explorerAPI = "https://api.basescan.org/api"
        case 11155111:
            explorerAPI = "https://api-sepolia.etherscan.io/api"
        default:
            return nil
        }

        guard let url = URL(string: "\(explorerAPI)?module=account&action=txlist&address=\(address)&startblock=0&endblock=99999999&page=1&offset=1&sort=asc") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = json["result"] as? [[String: Any]],
                  let firstTx = result.first,
                  let timestampStr = firstTx["timeStamp"] as? String,
                  let timestamp = TimeInterval(timestampStr) else {
                return nil
            }

            let creationDate = Date(timeIntervalSince1970: timestamp)
            let daysSinceCreation = Calendar.current.dateComponents([.day], from: creationDate, to: Date()).day
            return daysSinceCreation
        } catch {
            #if DEBUG
            print("[PhishingProtection] Failed to get contract age: \(error)")
            #endif
            return nil
        }
    }

    /// Comprehensive security check for a transaction recipient
    func checkRecipient(_ address: String, chainId: Int = 1) async -> [SecurityWarning] {
        var warnings: [SecurityWarning] = []

        // Check against known scam addresses
        let addressWarnings = await checkAddress(address)
        warnings.append(contentsOf: addressWarnings)

        // Check if contract is verified (skip for EOAs)
        let isVerified = await isContractVerified(address, chainId: chainId)
        if !isVerified {
            warnings.append(.unverifiedContract(address: address))
        }

        // Check contract age
        if let age = await getContractAge(address, chainId: chainId), age < 7 {
            warnings.append(.newContract(address: address, ageInDays: age))
        }

        return warnings
    }

    // MARK: - Phishing List Management

    private func refreshPhishingListIfNeeded() async {
        // Check if cache is still valid
        if let lastFetch = lastFetchTime,
           Date().timeIntervalSince(lastFetch) < cacheExpiry,
           !phishingDomains.isEmpty {
            return
        }

        await fetchPhishingList()
    }

    private func fetchPhishingList() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: phishingListURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            // Parse blacklisted domains
            if let blacklist = json["blacklist"] as? [String] {
                phishingDomains = Set(blacklist.map { $0.lowercased() })
            }

            // Parse fuzzy list (suspicious patterns)
            if let fuzzy = json["fuzzy"] as? [String] {
                for pattern in fuzzy {
                    phishingDomains.insert(pattern.lowercased())
                }
            }

            // Parse allowlist (whitelisted domains)
            if let whitelist = json["whitelist"] as? [String] {
                allowedDomains = Set(whitelist.map { $0.lowercased() })
            }

            lastFetchTime = Date()
            saveCachedData()

            #if DEBUG
            print("[PhishingProtection] Loaded \(phishingDomains.count) phishing domains, \(allowedDomains.count) allowed domains")
            #endif
        } catch {
            #if DEBUG
            print("[PhishingProtection] Failed to fetch phishing list: \(error)")
            #endif
        }
    }

    // MARK: - Homoglyph Detection

    private func detectHomoglyphDomain(_ domain: String) -> String? {
        let normalizedDomain = normalizeDomain(domain)

        // Convert homoglyphs to ASCII equivalents
        var asciiDomain = ""
        for char in normalizedDomain {
            var found = false
            for (ascii, homoglyphChars) in homoglyphs {
                if homoglyphChars.contains(char) {
                    asciiDomain.append(ascii)
                    found = true
                    break
                }
            }
            if !found {
                asciiDomain.append(char)
            }
        }

        // If the domain changed after homoglyph normalization, check if it matches a trusted domain
        if asciiDomain != normalizedDomain {
            for trusted in trustedDomains {
                if asciiDomain == trusted || asciiDomain.hasSuffix(".\(trusted)") {
                    return trusted
                }
            }

            // Check common DeFi protocol patterns
            let suspiciousPatterns = ["uniswap", "aave", "compound", "opensea", "metamask", "ledger", "trezor"]
            for pattern in suspiciousPatterns {
                if asciiDomain.contains(pattern) && normalizedDomain != asciiDomain {
                    return pattern
                }
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func normalizeDomain(_ domain: String) -> String {
        var normalized = domain.lowercased()

        // Remove protocol prefix
        if normalized.hasPrefix("https://") {
            normalized = String(normalized.dropFirst(8))
        } else if normalized.hasPrefix("http://") {
            normalized = String(normalized.dropFirst(7))
        }

        // Remove www prefix
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }

        // Remove path and query string
        if let slashIndex = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIndex])
        }

        // Remove port
        if let colonIndex = normalized.firstIndex(of: ":") {
            normalized = String(normalized[..<colonIndex])
        }

        return normalized
    }

    // MARK: - Persistence (File-based to avoid UserDefaults 4MB limit)

    private var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    private var phishingCacheURL: URL? {
        cacheDirectory?.appendingPathComponent("phishing_cache.json")
    }

    private func loadCachedData() {
        guard let cacheURL = phishingCacheURL else { return }

        do {
            let data = try Data(contentsOf: cacheURL)
            let cache = try JSONDecoder().decode(PhishingCache.self, from: data)
            phishingDomains = cache.phishingDomains
            allowedDomains = cache.allowedDomains
            lastFetchTime = cache.lastFetchTime
            #if DEBUG
            print("[PhishingProtection] Loaded \(phishingDomains.count) domains from file cache")
            #endif
        } catch {
            // No cache or corrupted - will fetch fresh
            #if DEBUG
            print("[PhishingProtection] No cache found, will fetch fresh")
            #endif
        }

        // Migrate from UserDefaults if exists (one-time migration)
        migrateFromUserDefaults()
    }

    private func migrateFromUserDefaults() {
        if let domains = UserDefaults.standard.stringArray(forKey: "phishingDomains"), !domains.isEmpty {
            if phishingDomains.isEmpty {
                phishingDomains = Set(domains)
                if let allowed = UserDefaults.standard.stringArray(forKey: "allowedDomains") {
                    allowedDomains = Set(allowed)
                }
                lastFetchTime = UserDefaults.standard.object(forKey: "phishingListFetchTime") as? Date
                saveCachedData()
            }
            // Clear UserDefaults after migration
            UserDefaults.standard.removeObject(forKey: "phishingDomains")
            UserDefaults.standard.removeObject(forKey: "allowedDomains")
            UserDefaults.standard.removeObject(forKey: "phishingListFetchTime")
            #if DEBUG
            print("[PhishingProtection] Migrated from UserDefaults to file cache")
            #endif
        }
    }

    private func saveCachedData() {
        guard let cacheURL = phishingCacheURL else { return }

        let cache = PhishingCache(
            phishingDomains: phishingDomains,
            allowedDomains: allowedDomains,
            lastFetchTime: lastFetchTime
        )

        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            #if DEBUG
            print("[PhishingProtection] Saved \(phishingDomains.count) domains to file cache")
            #endif
        } catch {
            #if DEBUG
            print("[PhishingProtection] Failed to save cache: \(error)")
            #endif
        }
    }
}

// MARK: - Cache Model

private struct PhishingCache: Codable {
    let phishingDomains: Set<String>
    let allowedDomains: Set<String>
    let lastFetchTime: Date?
}

// MARK: - Security Warning Types

enum SecurityWarning: Identifiable, Equatable {
    case knownPhishingDomain(domain: String)
    case homoglyphDomain(domain: String, looksLike: String)
    case knownScamAddress(address: String)
    case unverifiedContract(address: String)
    case newContract(address: String, ageInDays: Int)
    case unlimitedApproval(token: String, spender: String)
    case highValueTransaction(usdValue: Double)

    var id: String {
        switch self {
        case .knownPhishingDomain(let domain):
            return "phishing_\(domain)"
        case .homoglyphDomain(let domain, _):
            return "homoglyph_\(domain)"
        case .knownScamAddress(let address):
            return "scam_\(address)"
        case .unverifiedContract(let address):
            return "unverified_\(address)"
        case .newContract(let address, _):
            return "new_\(address)"
        case .unlimitedApproval(let token, let spender):
            return "approval_\(token)_\(spender)"
        case .highValueTransaction(let value):
            return "highvalue_\(value)"
        }
    }

    var severity: WarningSeverity {
        switch self {
        case .knownPhishingDomain, .knownScamAddress:
            return .critical
        case .homoglyphDomain, .unlimitedApproval:
            return .high
        case .unverifiedContract, .newContract, .highValueTransaction:
            return .medium
        }
    }

    var title: String {
        switch self {
        case .knownPhishingDomain:
            return "Known Phishing Site"
        case .homoglyphDomain:
            return "Suspicious Domain"
        case .knownScamAddress:
            return "Known Scam Address"
        case .unverifiedContract:
            return "Unverified Contract"
        case .newContract:
            return "New Contract"
        case .unlimitedApproval:
            return "Unlimited Approval"
        case .highValueTransaction:
            return "High Value Transaction"
        }
    }

    var message: String {
        switch self {
        case .knownPhishingDomain(let domain):
            return "'\(domain)' is a known phishing site. Do not enter any sensitive information."
        case .homoglyphDomain(let domain, let looksLike):
            return "'\(domain)' uses characters that look like '\(looksLike)' but are different. This may be an impersonation attempt."
        case .knownScamAddress(let address):
            return "Address \(address.prefix(10))... has been reported as a scam. Do not send funds to this address."
        case .unverifiedContract(let address):
            return "Contract \(address.prefix(10))... is not verified on block explorer. Proceed with caution."
        case .newContract(_, let age):
            return "This contract was created \(age) day\(age == 1 ? "" : "s") ago. New contracts may be riskier."
        case .unlimitedApproval(let token, _):
            return "This will grant unlimited access to your \(token) tokens. Consider setting a specific amount instead."
        case .highValueTransaction(let value):
            return "This transaction involves $\(String(format: "%.2f", value)). Please verify all details carefully."
        }
    }

    var icon: String {
        switch severity {
        case .critical:
            return "exclamationmark.octagon.fill"
        case .high:
            return "exclamationmark.triangle.fill"
        case .medium:
            return "info.circle.fill"
        }
    }
}

enum WarningSeverity: Int, Comparable {
    case medium = 1
    case high = 2
    case critical = 3

    static func < (lhs: WarningSeverity, rhs: WarningSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
