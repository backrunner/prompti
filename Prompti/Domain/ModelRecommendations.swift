import Foundation

struct ModelRecommendation: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    var weeklyRequests: Int64? = nil
}

struct OpenRouterRecommendations: Codable, Sendable {
    let source: String
    let asOf: String
    let models: [ModelRecommendation]

    var sortedModels: [ModelRecommendation] {
        models.sorted {
            switch ($0.weeklyRequests, $1.weeklyRequests) {
            case let (lhs?, rhs?) where lhs != rhs: lhs > rhs
            case (_?, nil): true
            case (nil, _?): false
            default: $0.name < $1.name
            }
        }
    }
}

enum ModelRecommendations {
    static let openRouter: OpenRouterRecommendations = {
        guard let url = Bundle.main.url(forResource: "OpenRouterRecommendations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(OpenRouterRecommendations.self, from: data) else {
            return OpenRouterRecommendations(source: "https://openrouter.ai/rankings", asOf: "",
                models: [.init(id: "openai/gpt-5.6-luna", name: "GPT-5.6 Luna")])
        }
        return OpenRouterRecommendations(source: snapshot.source, asOf: snapshot.asOf, models: snapshot.sortedModels)
    }()

    static let openAI: [ModelRecommendation] = [.init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna")]
    static let gemini: [ModelRecommendation] = [
        .init(id: "gemini-3.8-flash", name: "Gemini 3.8 Flash"),
        .init(id: "gemini-3.5-flash-lite", name: "Gemini 3.5 Flash-Lite")
    ]
    static let deepSeek: [ModelRecommendation] = [.init(id: "deepseek-v4-flash", name: "DeepSeek V4 Flash")]
    static let anthropic: [ModelRecommendation] = [.init(id: "claude-haiku-4-5-20251001", name: "Claude Haiku 4.5")]
}

/// Setup shortcuts use the existing protocol adapters and credential scopes.
/// They are inferred from a saved configuration, never persisted as a new format.
enum ProviderPreset: String, CaseIterable, Identifiable {
    case apple, openRouter, openAI, gemini, deepSeek, anthropic, compatible

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "Apple On-Device"
        case .openRouter: "OpenRouter · Sign in"
        case .openAI: "OpenAI"
        case .gemini: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .anthropic: "Anthropic"
        case .compatible: "OpenAI Chat / Compatible"
        }
    }

    var kind: ProviderKind {
        switch self {
        case .apple: .apple
        case .openRouter: .openRouterOAuth
        case .openAI: .openAIResponses
        case .anthropic: .anthropic
        case .gemini, .deepSeek, .compatible: .openAIChat
        }
    }

    var baseURL: String {
        switch self {
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .deepSeek: "https://api.deepseek.com"
        default: kind.defaultBaseURL
        }
    }

    var models: [ModelRecommendation] {
        switch self {
        case .apple: []
        case .openRouter: ModelRecommendations.openRouter.models
        case .openAI: ModelRecommendations.openAI
        case .gemini: ModelRecommendations.gemini
        case .deepSeek: ModelRecommendations.deepSeek
        case .anthropic: ModelRecommendations.anthropic
        case .compatible: []
        }
    }

    var configuration: ProviderConfiguration {
        ProviderConfiguration(kind: kind, baseURL: baseURL, model: models.first?.id ?? kind.defaultModel,
            structuredOutputSupport: self == .apple ? .supported : .unknown)
    }

    static func matching(_ configuration: ProviderConfiguration) -> Self {
        switch configuration.kind {
        case .apple: return .apple
        case .openRouterOAuth: return .openRouter
        case .openAIResponses: return .openAI
        case .anthropic: return .anthropic
        case .openAIChat:
            // Only show vendor-specific shortcuts for their exact endpoint.
            let endpoint = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            if endpoint == Self.gemini.baseURL { return .gemini }
            if endpoint == Self.deepSeek.baseURL || endpoint == Self.deepSeek.baseURL + "/v1" { return .deepSeek }
            return .compatible
        }
    }

    static func models(for configuration: ProviderConfiguration) -> [ModelRecommendation] {
        let endpoint = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if configuration.kind == .openAIResponses,
           !["https://api.openai.com", "https://api.openai.com/v1", "https://api.openai.com/v1/responses"].contains(endpoint) {
            return []
        }
        if configuration.kind == .anthropic,
           !["https://api.anthropic.com", "https://api.anthropic.com/v1", "https://api.anthropic.com/v1/messages"].contains(endpoint) {
            return []
        }
        if configuration.kind == .openAIChat,
           ["https://api.openai.com", "https://api.openai.com/v1", "https://api.openai.com/v1/chat/completions"].contains(endpoint) {
            return ModelRecommendations.openAI
        }
        return matching(configuration).models
    }
}
