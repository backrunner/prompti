import Foundation

enum GenerationError: LocalizedError, Sendable {
    case insufficientCredit
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
        case .insufficientCredit: String(localized: "Add credits to your model account, or choose another model in Settings.")
        case .missingAPIKey: String(localized: "Connect a model in Settings to continue.")
        case .invalidEndpoint: String(localized: "Use a valid public HTTPS endpoint.")
        case .invalidCredential: String(localized: "Your model connection has expired or was revoked. Reconnect in Settings.")
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
