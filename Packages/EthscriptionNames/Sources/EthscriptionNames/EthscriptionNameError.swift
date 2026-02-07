import Foundation

// MARK: - EthscriptionNameError

/// Errors that can occur when working with Ethscription names
public enum EthscriptionNameError: Error, LocalizedError, Sendable {

    /// The name string is empty
    case emptyName

    /// The name format is invalid
    case invalidFormat(String)

    /// The name has not been claimed (no ethscription exists)
    case nameNotFound(String)

    /// Network error during resolution
    case networkError(String)

    /// Invalid API response
    case invalidResponse

    /// The request was rate limited
    case rateLimited

    /// The API endpoint is not available
    case apiUnavailable

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Name cannot be empty"
        case .invalidFormat(let reason):
            return "Invalid name format: \(reason)"
        case .nameNotFound(let name):
            return "Name '\(name)' has not been claimed"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from API"
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .apiUnavailable:
            return "Ethscriptions API is currently unavailable"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .emptyName:
            return "Provide a non-empty name string"
        case .invalidFormat:
            return "Names can only contain letters, numbers, hyphens, underscores, and dots"
        case .nameNotFound:
            return "This name is available to claim"
        case .networkError:
            return "Check your internet connection and try again"
        case .invalidResponse:
            return "Try again or contact support if the issue persists"
        case .rateLimited:
            return "Wait a few seconds before making another request"
        case .apiUnavailable:
            return "The service may be temporarily down. Try again later."
        }
    }
}
