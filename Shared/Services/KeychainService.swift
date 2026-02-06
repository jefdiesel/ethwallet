import Foundation
import Security
import LocalAuthentication

/// Service for secure storage of wallet seeds and keys using the macOS/iOS Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let serviceName = "com.ethwallet.seed"

    private init() {}

    // MARK: - Seed Storage

    /// Store the wallet seed securely with biometric protection
    /// - Parameters:
    ///   - seed: The seed data to store
    ///   - walletId: Unique identifier for the wallet
    func storeSeed(_ seed: Data, for walletId: String) throws {
        // Delete any existing item first
        try? deleteSeed(for: walletId)

        // Create access control with user presence (biometric or password)
        let accessControl = try createAccessControl()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: walletId,
            kSecAttrService as String: serviceName,
            kSecValueData as String: seed,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve the wallet seed (requires biometric authentication)
    /// - Parameter walletId: Unique identifier for the wallet
    /// - Returns: The seed data
    func retrieveSeed(for walletId: String = "default") async throws -> Data {
        // Create LAContext for authentication
        let context = LAContext()
        context.localizedReason = "Access wallet seed"
        context.localizedCancelTitle = "Cancel"

        // Let the keychain handle the single biometric/password prompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: walletId,
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: data)
                } else if status == errSecItemNotFound {
                    continuation.resume(throwing: KeychainError.itemNotFound)
                } else if status == errSecUserCanceled || status == errSecAuthFailed {
                    continuation.resume(throwing: KeychainError.userCanceled)
                } else {
                    continuation.resume(throwing: KeychainError.retrieveFailed(status))
                }
            }
        }
    }

    /// Delete the stored seed for a wallet
    /// - Parameter walletId: Unique identifier for the wallet
    func deleteSeed(for walletId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: walletId,
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// Check if a seed exists for the given wallet
    /// - Parameter walletId: Unique identifier for the wallet
    /// - Returns: True if seed exists
    func seedExists(for walletId: String = "default") -> Bool {
        // Query for attributes only (not data) to check existence without triggering auth
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: walletId,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #if DEBUG
        print("[Keychain] seedExists check for '\(walletId)': status=\(status)")
        #endif

        // errSecInteractionNotAllowed (-25308) means item exists but needs auth
        // errSecSuccess (0) means item exists
        // errSecItemNotFound (-25300) means no item
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    // MARK: - Private Key Storage (for imported keys)

    /// Store a private key securely
    /// - Parameters:
    ///   - privateKey: The private key data
    ///   - accountId: Unique identifier for the account
    func storePrivateKey(_ privateKey: Data, for accountId: String) throws {
        try? deletePrivateKey(for: accountId)

        let accessControl = try createAccessControl()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pk_\(accountId)",
            kSecAttrService as String: serviceName,
            kSecValueData as String: privateKey,
            kSecAttrAccessControl as String: accessControl
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve a private key (requires biometric authentication)
    /// - Parameter accountId: Unique identifier for the account
    /// - Returns: The private key data
    func retrievePrivateKey(for accountId: String) async throws -> Data {
        let context = LAContext()
        context.localizedReason = "Sign transaction"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pk_\(accountId)",
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &result)

                if status == errSecSuccess, let data = result as? Data {
                    continuation.resume(returning: data)
                } else if status == errSecItemNotFound {
                    continuation.resume(throwing: KeychainError.itemNotFound)
                } else {
                    continuation.resume(throwing: KeychainError.retrieveFailed(status))
                }
            }
        }
    }

    /// Delete a stored private key
    /// - Parameter accountId: Unique identifier for the account
    func deletePrivateKey(for accountId: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "pk_\(accountId)",
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - API Key Storage (for third-party service keys)

    /// Store an API key securely (no biometric required, just device unlock)
    /// - Parameters:
    ///   - key: The API key to store
    ///   - identifier: Unique identifier for the key (e.g., "tenderly", "etherscan")
    func storeAPIKey(_ key: String, for identifier: String) throws {
        try? deleteAPIKey(for: identifier)

        guard let keyData = key.data(using: .utf8) else {
            throw KeychainError.unknownError
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "apikey_\(identifier)",
            kSecAttrService as String: serviceName,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve an API key
    /// - Parameter identifier: Unique identifier for the key
    /// - Returns: The API key, or nil if not found
    func retrieveAPIKey(for identifier: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "apikey_\(identifier)",
            kSecAttrService as String: serviceName,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }

    /// Delete an API key
    /// - Parameter identifier: Unique identifier for the key
    func deleteAPIKey(for identifier: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "apikey_\(identifier)",
            kSecAttrService as String: serviceName
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Access Control

    private func createAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?

        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,  // Allows biometric OR password
            &error
        ) else {
            if let cfError = error?.takeRetainedValue() {
                throw KeychainError.accessControlCreationFailed(cfError as Error)
            }
            throw KeychainError.unknownError
        }

        return accessControl
    }

    // MARK: - Biometric Check

    /// Check if biometric authentication is available
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    /// Get the type of biometric available
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        default:
            return .none
        }
    }
}

// MARK: - Error Types

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case itemNotFound
    case userCanceled
    case biometricsUnavailable
    case accessControlCreationFailed(Error)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .retrieveFailed(let status):
            return "Failed to retrieve from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .userCanceled:
            return "Authentication was canceled"
        case .biometricsUnavailable:
            return "Biometric authentication is not available"
        case .accessControlCreationFailed(let error):
            return "Failed to create access control: \(error.localizedDescription)"
        case .unknownError:
            return "An unknown Keychain error occurred"
        }
    }
}

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
}

// MARK: - Smart Account Storage Extension

extension KeychainService {
    /// Save smart accounts to UserDefaults (non-sensitive data)
    func saveSmartAccounts(_ accounts: [SmartAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        UserDefaults.standard.set(data, forKey: "smartAccounts")
    }

    /// Load smart accounts from UserDefaults
    func loadSmartAccounts() throws -> [SmartAccount] {
        guard let data = UserDefaults.standard.data(forKey: "smartAccounts") else {
            return []
        }
        return try JSONDecoder().decode([SmartAccount].self, from: data)
    }

    /// Delete all smart accounts
    func deleteSmartAccounts() {
        UserDefaults.standard.removeObject(forKey: "smartAccounts")
    }
}
