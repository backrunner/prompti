import Foundation
import Testing
@testable import Prompti

@Suite("Remote AI provider contracts")
struct RemoteAIClientTests {
    @Test("Responses API extracts typed output text")
    func responsesOutput() throws {
        let client = makeClient(.openAIResponses)
        let data = Data(#"{"output":[{"content":[{"type":"output_text","text":"{\"allowed\":true}"}]}]}"#.utf8)
        #expect(try client.extractText(from: data) == #"{"allowed":true}"#)
    }

    @Test("Chat API extracts assistant content")
    func chatOutput() throws {
        let client = makeClient(.openAIChat)
        let data = Data(#"{"choices":[{"message":{"content":"{\"questions\":[]}"}}]}"#.utf8)
        #expect(try client.extractText(from: data) == #"{"questions":[]}"#)
    }

    @Test("Merged Chat provider can request either structured or JSON mode")
    func chatResponseFormatModes() throws {
        let client = makeClient(.openAIChat)
        let schema: [String: Any] = ["type": "object"]

        let structured = client.chatBody(
            system: "system",
            user: "user",
            schemaName: "test",
            schema: schema,
            usesStructuredOutputs: true
        )
        let structuredFormat = try #require(structured["response_format"] as? [String: Any])
        #expect(structuredFormat["type"] as? String == "json_schema")
        #expect(structured["store"] as? Bool == false)

        let json = client.chatBody(
            system: "system",
            user: "user",
            schemaName: "test",
            schema: schema,
            usesStructuredOutputs: false
        )
        let jsonFormat = try #require(json["response_format"] as? [String: Any])
        #expect(jsonFormat["type"] as? String == "json_object")

        let compatible = RemoteAIClient(
            configuration: ProviderConfiguration(
                kind: .openAIChat,
                baseURL: "https://gateway.example.com",
                model: "local-model"
            ),
            apiKey: "test-key"
        )
        let compatibleBody = compatible.chatBody(
            system: "system",
            user: "user",
            schemaName: "test",
            schema: schema,
            usesStructuredOutputs: true
        )
        #expect(compatibleBody["store"] == nil)
    }

    @Test("Anthropic API extracts text content block")
    func anthropicOutput() throws {
        let client = makeClient(.anthropic)
        let data = Data(#"{"content":[{"type":"text","text":"{\"allowed\":false}"}]}"#.utf8)
        #expect(try client.extractText(from: data) == #"{"allowed":false}"#)
    }

    @Test("Full endpoint URLs are not duplicated")
    func fullEndpoint() throws {
        let configuration = ProviderConfiguration(
            kind: .openAIResponses,
            baseURL: "https://api.openai.com/v1/responses",
            model: "gpt-5-mini"
        )
        let client = RemoteAIClient(configuration: configuration, apiKey: "test-key")
        #expect(try client.endpointURL().absoluteString == "https://api.openai.com/v1/responses")
    }

    private func makeClient(_ kind: ProviderKind) -> RemoteAIClient {
        RemoteAIClient(
            configuration: ProviderConfiguration(kind: kind, baseURL: kind.defaultBaseURL, model: kind.defaultModel),
            apiKey: "test-key"
        )
    }
}
