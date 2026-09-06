import Foundation

enum ProviderDetector {
    static func suggest(baseURL: String, model: String) -> ProviderKind {
        guard let url = URL(string: baseURL), let host = url.host?.lowercased() else {
            return .openAIChat
        }
        let path = url.path.lowercased()
        let model = model.lowercased()
        if host.contains("anthropic") || model.hasPrefix("claude") { return .anthropic }
        if path.contains("responses") { return .openAIResponses }
        if path.contains("chat/completions") { return .openAIChat }
        if host == "api.openai.com" {
            return model.hasPrefix("gpt-4") ? .openAIChat : .openAIResponses
        }
        return .openAIChat
    }
}
