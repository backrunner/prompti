import Foundation
import Testing
@testable import Prompti

@Suite("Remote AI provider contracts")
struct RemoteAIClientTests {
    @Test("Structured requests send schema once; JSON fallback still includes the full contract")
    func schemaIsNotDuplicated() throws {
        let client = makeClient(.openAIChat)
        let schema = RemoteAIClient.questionSchema(for: [.multipleChoice])
        let structured = try client.chatBody(system: "rules", user: "question", schemaName: "test", schema: schema, usesStructuredOutputs: true)
        let json = try client.chatBody(system: "rules", user: "question", schemaName: "test", schema: schema, usesStructuredOutputs: false)
        let structuredMessages = try #require(structured["messages"] as? [[String: String]])
        let jsonMessages = try #require(json["messages"] as? [[String: String]])
        #expect(structuredMessages.last?["content"] == "question")
        #expect(jsonMessages.last?["content"]?.contains("sourceFactIDs") == true)
        let response = try client.responsesBody(system: "rules", user: "question", schemaName: "test", schema: schema, usesStructuredOutputs: true)
        #expect(response["input"] as? String == "question")
        let responseJSON = try client.responsesBody(system: "rules", user: "question", schemaName: "test", schema: schema, usesStructuredOutputs: false)
        #expect((responseJSON["input"] as? String)?.contains("sourceFactIDs") == true)
    }

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

        let structured = try client.chatBody(
            system: "system",
            user: "user",
            schemaName: "test",
            schema: schema,
            usesStructuredOutputs: true
        )
        let structuredFormat = try #require(structured["response_format"] as? [String: Any])
        #expect(structuredFormat["type"] as? String == "json_schema")
        #expect(structured["store"] as? Bool == false)

        let json = try client.chatBody(
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
        let compatibleBody = try compatible.chatBody(
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

    @Test("Legacy non-thinking OpenAI models keep working without unsupported reasoning fields", arguments: ["gpt-4o", "gpt-4.1-mini", "gpt-3.5-turbo"])
    func legacyNonThinkingModels(_ model: String) throws {
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat, model: model), apiKey: "fixture-only")
        let chat = try client.chatBody(system: "system", user: "user", schemaName: "test", schema: ["type": "object"], usesStructuredOutputs: true)
        let responses = try client.responsesBody(system: "system", user: "user", schemaName: "test", schema: ["type": "object"], usesStructuredOutputs: true)
        #expect(chat["reasoning_effort"] == nil)
        #expect(responses["reasoning"] == nil)
    }

    @Test("Mandatory reasoning models use the lowest supported effort")
    func mandatoryReasoningUsesLowEffort() throws {
        let schema: [String: Any] = ["type": "object"]
        let openRouter = RemoteAIClient(configuration: ProviderConfiguration(
            kind: .openRouter, baseURL: ProviderKind.openRouter.defaultBaseURL, model: "google/gemini-3.8-flash"), apiKey: "fixture-only")
        let routerReasoning = try #require((try openRouter.chatBody(
            system: "system", user: "user", schemaName: "test", schema: schema, usesStructuredOutputs: true))["reasoning"] as? [String: Any])
        #expect(routerReasoning["effort"] as? String == "low")

        let responses = RemoteAIClient(configuration: ProviderConfiguration(
            kind: .openAIResponses, baseURL: "https://api.openai.com", model: "gpt-5-mini"), apiKey: "fixture-only")
        let responseReasoning = try #require((try responses.responsesBody(
            system: "system", user: "user", schemaName: "test", schema: schema, usesStructuredOutputs: true))["reasoning"] as? [String: String])
        #expect(responseReasoning["effort"] == "low")

        let deepSeek = RemoteAIClient(configuration: ProviderConfiguration(
            kind: .openAIChat, baseURL: "https://api.deepseek.com", model: "deepseek-r1"), apiKey: "fixture-only")
        let deepSeekBody = try deepSeek.chatBody(
            system: "system", user: "user", schemaName: "test", schema: schema, usesStructuredOutputs: true)
        #expect((deepSeekBody["thinking"] as? [String: String])?["type"] == "enabled")
        #expect(deepSeekBody["reasoning_effort"] as? String == "low")
    }
}
