import Foundation

enum GenerationError: LocalizedError, Sendable {
    case insufficientCredit
    case permissionDenied
    case modelNotFound
    case timedOut
    case networkUnavailable
    case refused
    case truncatedOutput
    case missingAPIKey
    case invalidEndpoint
    case invalidCredential
    case rateLimited
    case providerUnavailable
    case modelUnavailable
    case malformedResponse
    case invalidScene(String)
    case unsafeContent(String)
    case noApprovedQuestions
    case unsupportedProvider

    var errorDescription: String? {
        switch self {
        case .permissionDenied: String(localized: "Your account does not have access to this model. Check provider permissions or choose another model.")
        case .modelNotFound: String(localized: "The model or API endpoint was not found. Check your model settings.")
        case .timedOut: String(localized: "The model request timed out. Retry with fewer questions.")
        case .networkUnavailable: String(localized: "The provider could not be reached. Check your connection and try again.")
        case .refused: String(localized: "The model declined this request. Choose another travel scene and try again.")
        case .truncatedOutput: String(localized: "The model stopped before finishing. Try a smaller practice set.")
        case .insufficientCredit: String(localized: "Add credits to your model account, or choose another model in Settings.")
        case .missingAPIKey: String(localized: "Connect a model in Settings to continue.")
        case .invalidEndpoint: String(localized: "Use a valid public HTTPS endpoint.")
        case .invalidCredential: String(localized: "Your API key is invalid or has been revoked. Update it in Settings.")
        case .rateLimited: String(localized: "The model is busy or rate-limited. Try again shortly.")
        case .providerUnavailable: String(localized: "The model provider is temporarily unavailable.")
        case .modelUnavailable: String(localized: "This model is not available for the selected language.")
        case .malformedResponse: String(localized: "The model returned an unexpected response.")
        case .invalidScene(let message), .unsafeContent(let message): message
        case .noApprovedQuestions: String(localized: "No questions passed Prompti's safety and quality checks.")
        case .unsupportedProvider: String(localized: "This provider configuration is not supported.")
        }
    }
}
