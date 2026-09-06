import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    case openRouterOAuth
    case openAIResponses
    case openAIChat
    case anthropic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: "Apple On-Device"
        case .openRouterOAuth: "OpenRouter · Sign in"
        case .openAIResponses: "OpenAI Responses"
        case .openAIChat: "OpenAI Chat / Compatible"
        case .anthropic: "Anthropic Messages"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .apple: ""
        case .openRouterOAuth: "https://openrouter.ai/api"
        case .openAIResponses, .openAIChat: "https://api.openai.com"
        case .anthropic: "https://api.anthropic.com"
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: "system"
        case .openRouterOAuth: "openai/gpt-5-mini"
        case .openAIResponses: "gpt-5-mini"
        case .openAIChat: "gpt-4o-mini"
        case .anthropic: "claude-sonnet-4-5"
        }
    }
}

enum StructuredOutputSupport: String, Codable, Equatable, Sendable {
    case unknown
    case supported
    case unsupported
}

struct ProviderConfiguration: Codable, Equatable, Sendable {
    var credentialScope: String {
        let url = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))
        let host = url?.host?.lowercased() ?? baseURL
        let port = url?.port.map { ":\($0)" } ?? ""
        // Path is significant for custom gateways serving multiple tenants.
        let path = (url?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(kind.rawValue)|\(url?.scheme?.lowercased() ?? "")://\(host)\(port)/\(path)"
    }

    var kind: ProviderKind = .openAIResponses
    var baseURL: String = ProviderKind.openAIResponses.defaultBaseURL
    var model: String = ProviderKind.openAIResponses.defaultModel
    var structuredOutputSupport: StructuredOutputSupport = .unknown

    init(
        kind: ProviderKind = .openAIResponses,
        baseURL: String = ProviderKind.openAIResponses.defaultBaseURL,
        model: String = ProviderKind.openAIResponses.defaultModel,
        structuredOutputSupport: StructuredOutputSupport = .unknown
    ) {
        self.kind = kind
        self.baseURL = baseURL
        self.model = model
        self.structuredOutputSupport = structuredOutputSupport
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case baseURL
        case model
        case structuredOutputSupport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedKind = try container.decodeIfPresent(String.self, forKey: .kind)
        kind = storedKind == "openAICompatible"
            ? .openAIChat
            : ProviderKind(rawValue: storedKind ?? "") ?? .openAIResponses
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? kind.defaultBaseURL
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? kind.defaultModel
        structuredOutputSupport = try container.decodeIfPresent(
            StructuredOutputSupport.self,
            forKey: .structuredOutputSupport
        ) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(model, forKey: .model)
        try container.encode(structuredOutputSupport, forKey: .structuredOutputSupport)
    }
}

enum AppleModelStatus: Equatable, Sendable {
    case available
    case hidden
    case notReady
    case unsupportedLanguage
    case unavailable

    var canGenerate: Bool { self == .available }
}
