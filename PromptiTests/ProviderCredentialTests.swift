import Foundation
import Testing
@testable import Prompti

@Suite("Provider credentials and compatibility")
struct ProviderCredentialTests {
    @Test("Credentials are isolated by protocol, server, port and tenant path")
    func credentialIsolation() {
        let source = ProviderConfiguration(kind: .openAIChat, baseURL: "https://gateway.example.com/team-a", model: "a")
        var same = source
        same.model = "b"
        #expect(source.credentialScope == same.credentialScope)
        same.baseURL = "https://GATEWAY.example.com/team-a/"
        #expect(source.credentialScope == same.credentialScope)
        for url in ["https://elsewhere.example.com/team-a", "https://gateway.example.com/team-b", "https://gateway.example.com:8443/team-a"] {
            same.baseURL = url
            #expect(source.credentialScope != same.credentialScope)
        }
        same = source
        same.kind = .openRouter
        #expect(source.credentialScope != same.credentialScope)
    }

    @Test("OpenRouter uses Chat Completions and rejects an altered preset destination")
    func routerEndpoint() throws {
        var configuration = ProviderConfiguration(kind: .openRouter, baseURL: ProviderKind.openRouter.defaultBaseURL, model: "openai/gpt-5-mini")
        let client = RemoteAIClient(configuration: configuration, apiKey: "fixture")
        #expect(try client.endpointURL().absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        let response = Data(#"{"choices":[{"message":{"content":"{\"allowed\":true}"}}]}"#.utf8)
        #expect(try client.extractText(from: response) == #"{"allowed":true}"#)
        configuration.baseURL = "https://elsewhere.example.com"
        #expect(throws: GenerationError.self) { try RemoteAIClient(configuration: configuration, apiKey: "fixture").endpointURL() }
    }

    @Test("Existing OpenRouter settings retain their model, verification and Keychain scope")
    func existingOpenRouterSettings() throws {
        let data = Data(#"{"kind":"openRouterOAuth","baseURL":"https://openrouter.ai/api","model":"my-existing-model","structuredOutputSupport":"supported"}"#.utf8)
        let configuration = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
        #expect(configuration.kind == .openRouter)
        #expect(configuration.model == "my-existing-model")
        #expect(configuration.structuredOutputSupport == .supported)
        #expect(configuration.credentialScope == "openRouterOAuth|https://openrouter.ai/api")
        #expect(ProviderPreset.matching(configuration) == .openRouter)
        #expect(try JSONDecoder().decode(ProviderConfiguration.self, from: JSONEncoder().encode(configuration)) == configuration)
    }
}
