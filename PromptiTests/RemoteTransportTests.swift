import Foundation
import Testing
@testable import Prompti

private actor FixtureTransport {
    private(set) var requests: [URLRequest] = []
    let statuses: [Int]
    let payload: Data

    init(statuses: [Int], payload: Data) { self.statuses = statuses; self.payload = payload }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let status = statuses[min(requests.count, statuses.count - 1)]
        requests.append(request)
        return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Remote transport regressions")
struct RemoteTransportTests {
    @Test("Schema fallback sends an explicit JSON schema and keeps store disabled", arguments: [ProviderKind.openAIChat, .openAIResponses])
    func fallback(_ kind: ProviderKind) async throws {
        let fixture = FixtureTransport(statuses: [400, 200], payload: try response(for: kind))
        let client = RemoteAIClient(configuration: configuration(kind), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        #expect(try await client.probe() == .unsupported)
        let requests = await fixture.requests
        #expect(requests.count == 2)
        for request in requests {
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["store"] as? Bool == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
            let prompt: String
            if kind == .openAIResponses { prompt = try #require(body["input"] as? String) }
            else { prompt = try #require((body["messages"] as? [[String: String]])?.last?["content"]) }
            let schema = try #require(prompt.components(separatedBy: "JSON Schema:\n").last)
            let parsed = try #require(JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
            #expect((parsed["required"] as? [String])?.contains("allowed") == true)
            #expect(!prompt.contains("fixture-only"))
        }
    }

    @Test("Anthropic receives JSON syntax, its own authentication and an output cap")
    func anthropicRequest() async throws {
        let fixture = FixtureTransport(statuses: [200], payload: try response(for: .anthropic))
        let client = RemoteAIClient(configuration: configuration(.anthropic), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        #expect(try await client.probe() == .unsupported)
        let request = try #require(await fixture.requests.first)
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-only")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let prompt = try #require((body["messages"] as? [[String: String]])?.last?["content"])
        let schema = try #require(prompt.components(separatedBy: "JSON Schema:\n").last)
        #expect(throws: Never.self) { _ = try JSONSerialization.jsonObject(with: Data(schema.utf8)) }
        #expect((body["max_tokens"] as? Int ?? 0) > 0)
    }

    @Test("Authentication failures and redirects never retry", arguments: [401, 403, 307])
    func noRetry(_ status: Int) async throws {
        let fixture = FixtureTransport(statuses: [status], payload: Data())
        let client = RemoteAIClient(configuration: configuration(.anthropic), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        await #expect(throws: GenerationError.self) { try await client.probe() }
        #expect(await fixture.requests.count == 1)
    }

    @Test("Oversized responses are rejected")
    func oversized() async throws {
        let fixture = FixtureTransport(statuses: [200], payload: Data(repeating: 32, count: 2_000_001))
        let client = RemoteAIClient(configuration: configuration(.openAIChat), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        await #expect(throws: GenerationError.self) { try await client.probe() }
    }

    @Test("URLSession cancellation stays cancellation")
    func cancellation() async {
        let client = RemoteAIClient(configuration: configuration(.openAIChat), apiKey: "fixture-only", transport: { _ in throw URLError(.cancelled) })
        await #expect(throws: CancellationError.self) { try await client.probe() }
    }

    @Test("Private IP forms and URL credentials cannot bypass endpoint validation", arguments: [
        "http://api.example.com", "https://127.1", "https://2130706433", "https://0x7f000001", "https://169.254.1.1",
        "https://[::1]", "https://[::ffff:127.0.0.1]", "https://[fc00::1]", "https://[fe80::1]",
        "https://localhost.", "https://test.local", "https://user:password@api.example.com", "https://api.example.com?key=secret"
    ])
    func endpoints(_ url: String) {
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat, baseURL: url, model: "fixture"), apiKey: "fixture-only")
        #expect(throws: GenerationError.self) { try client.endpointURL() }
    }

    @Test("Trailing slashes do not duplicate API routes", arguments: ["https://api.openai.com/v1/", "https://api.openai.com/v1/chat/completions/"])
    func trailingSlash(_ url: String) throws {
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat, baseURL: url, model: "fixture"), apiKey: "fixture-only")
        #expect(try client.endpointURL().absoluteString == "https://api.openai.com/v1/chat/completions")
    }

    @Test("Refusal and incomplete output are recoverable errors")
    func refusals() throws {
        for (kind, payload) in [
            (ProviderKind.openAIResponses, #"{"output":[{"content":[{"type":"refusal","refusal":"declined"}]}]}"#),
            (.openAIResponses, #"{"status":"incomplete","output_text":"{}"}"#),
            (.openAIChat, #"{"choices":[{"finish_reason":"length","message":{"content":"{}"}}]}"#),
            (.openAIChat, #"{"choices":[{"message":{"refusal":"declined"}}]}"#),
            (.anthropic, #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"{}"}]}"#)
        ] {
            let client = RemoteAIClient(configuration: configuration(kind), apiKey: "fixture-only")
            #expect(throws: GenerationError.self) { try client.extractText(from: Data(payload.utf8)) }
        }
    }

    private func configuration(_ kind: ProviderKind) -> ProviderConfiguration {
        ProviderConfiguration(kind: kind, baseURL: kind.defaultBaseURL, model: kind.defaultModel)
    }

    private func response(for kind: ProviderKind) throws -> Data {
        let text = #"{"allowed":true,"normalized":"hotel check-in","reason":"travel"}"#
        let object: [String: Any]
        switch kind {
        case .openAIResponses: object = ["output": [["content": [["type": "output_text", "text": text]]]]]
        case .anthropic: object = ["content": [["type": "text", "text": text]]]
        default: object = ["choices": [["message": ["content": text]]]]
        }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
