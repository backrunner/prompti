import Foundation
import Testing
@testable import Prompti

// Restates URLProtocol's inherited Sendable conformance; this fixture adds no
// stored state and relies on URLSession to serialize its protocol callbacks.
private final class StalledResponseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.lastPathComponent == "body" {
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{\"choices\":".utf8))
        }
        // Intentionally never finish, like a provider that stops responding.
    }
    override func stopLoading() { }
}

private actor FixtureTransport {
    private(set) var requests: [URLRequest] = []
    let statuses: [Int]
    let payloads: [Data]

    init(statuses: [Int], payload: Data) { self.statuses = statuses; self.payloads = [payload] }
    init(statuses: [Int], payloads: [Data]) { self.statuses = statuses; self.payloads = payloads }

    func send(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        let status = statuses[min(requests.count, statuses.count - 1)]
        let payload = payloads[min(requests.count, payloads.count - 1)]
        requests.append(request)
        return (payload, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@Suite("Remote transport regressions")
struct RemoteTransportTests {
    @Test("A successful schema fallback is reused only within the same client and schema")
    func remembersSuccessfulFallback() async throws {
        let payload = Data(#"{"choices":[{"message":{"content":"{\"questions\":[]}"}}]}"#.utf8)
        let fixture = FixtureTransport(statuses: [400, 200, 200, 200, 200], payload: payload)
        let configuration = ProviderConfiguration(kind: .openAIChat)
        let client = RemoteAIClient(configuration: configuration, apiKey: "fixture-only", transport: { try await fixture.send($0) })
        var request = GenerationCapabilityTests.request(count: 1)
        _ = try await client.generate(request)
        _ = try await client.generate(request)
        request.kinds = [.spoken]
        _ = try await client.generate(request)
        let freshClient = RemoteAIClient(configuration: configuration, apiKey: "fixture-only", transport: { try await fixture.send($0) })
        _ = try await freshClient.generate(GenerationCapabilityTests.request(count: 1))
        let requests = await fixture.requests
        let formats = try requests.map { request -> String in
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            return try #require((body["response_format"] as? [String: Any])?["type"] as? String)
        }
        #expect(formats == ["json_schema", "json_object", "json_object", "json_schema", "json_schema"])
    }

    @Test("Failed fallback does not disable structured output on a later retry")
    func failedFallbackIsNotRemembered() async throws {
        let payload = Data(#"{"choices":[{"message":{"content":"{\"questions\":[]}"}}]}"#.utf8)
        let fixture = FixtureTransport(statuses: [400, 503, 200], payload: payload)
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        await #expect(throws: GenerationError.self) { try await client.generate(GenerationCapabilityTests.request(count: 1)) }
        _ = try await client.generate(GenerationCapabilityTests.request(count: 1))
        let last = try #require(await fixture.requests.last)
        let body = try #require(JSONSerialization.jsonObject(with: last.httpBody!) as? [String: Any])
        #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_schema")
    }

    static let policyConfigurations: [ProviderConfiguration] = [
        ProviderPreset.openAI.configuration,
        ProviderPreset.anthropic.configuration,
        ProviderPreset.deepSeek.configuration,
        ProviderPreset.gemini.configuration,
        ProviderConfiguration(kind: .openAIChat, model: "gpt-5.6-luna"),
        ProviderConfiguration(kind: .openAIChat, baseURL: "https://gateway.example.com", model: "custom-model"),
        ProviderConfiguration(kind: .openAIResponses, baseURL: "https://gateway.example.com", model: "custom-model")
    ] + ModelRecommendations.openRouter.models.map {
        ProviderConfiguration(kind: .openRouter, baseURL: ProviderKind.openRouter.defaultBaseURL, model: $0.id)
    }

    @Test("Every remote operation applies the reasoning policy, including schema fallback", arguments: policyConfigurations, [true, false])
    func reasoningPolicyRequests(_ configuration: ProviderConfiguration, _ structured: Bool) async throws {
        actor Requests {
            var count = 0
            func record() { count += 1 }
        }
        let requests = Requests()
        let client = RemoteAIClient(configuration: configuration, apiKey: "fixture-only", transport: { request in
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            if configuration.kind == .openRouter {
                let reasoning = try #require(body["reasoning"] as? [String: Any])
                if ModelReasoningPolicy.requiresReasoning(configuration.model) {
                    #expect(reasoning["effort"] as? String == "low")
                    #expect(reasoning["enabled"] == nil)
                } else {
                    #expect(reasoning["enabled"] as? Bool == false)
                    #expect(reasoning["effort"] == nil)
                }
                #expect(body["reasoning_effort"] == nil)
                let routing = try #require(body["provider"] as? [String: Any])
                #expect(routing["require_parameters"] as? Bool == true)
                #expect(routing["sort"] as? String == "latency")
            } else if configuration.kind == .anthropic {
                #expect((body["thinking"] as? [String: String])?["type"] == "disabled")
                #expect(body["reasoning"] == nil)
                #expect(body["reasoning_effort"] == nil)
            } else if request.url?.host == "api.deepseek.com" {
                let expectedThinking = ModelReasoningPolicy.requiresReasoning(configuration.model) ? "enabled" : "disabled"
                #expect((body["thinking"] as? [String: String])?["type"] == expectedThinking)
                #expect(body["reasoning_effort"] as? String == (ModelReasoningPolicy.requiresReasoning(configuration.model) ? "low" : nil))
            } else if configuration.kind == .openAIResponses {
                #expect((body["reasoning"] as? [String: String])?["effort"] == ModelReasoningPolicy.effort(configuration.model))
            } else {
                if ModelReasoningPolicy.isLegacyNonReasoningOpenAI(configuration.model) {
                    #expect(body["reasoning_effort"] == nil)
                } else {
                    #expect(body["reasoning_effort"] as? String == ModelReasoningPolicy.effort(configuration.model))
                }
                #expect(body["reasoning"] == nil)
            }
            await requests.record()
            let format = configuration.kind == .openAIResponses
                ? (body["text"] as? [String: Any])?["format"] as? [String: Any]
                : body["response_format"] as? [String: Any]
            let status = !structured && format?["type"] as? String == "json_schema" ? 400 : 200
            let prompt = configuration.kind == .openAIResponses
                ? try #require(body["input"] as? String)
                : try #require((body["messages"] as? [[String: String]])?.last?["content"])
            #expect(request.timeoutInterval == (prompt.hasPrefix("Generate exactly") || prompt.hasPrefix("Independently review") ? 120 : 45))
            let tokenLimit = body["max_tokens"] ?? body["max_completion_tokens"] ?? body["max_output_tokens"]
            #expect(tokenLimit as? Int == (prompt.hasPrefix("Generate exactly") ? 4_000 : 2_000))
            let content = prompt.hasPrefix("Generate exactly") ? #"{"questions":[]}"#
                : prompt.hasPrefix("Independently review") ? #"{"decisions":[]}"#
                : prompt.hasPrefix("Judge the meaning") ? #"{"result":"correct","feedback":"Meaning matched"}"#
                : #"{"allowed":true,"normalized":"hotel check-in","reason":"travel"}"#
            let object: [String: Any]
            switch configuration.kind {
            case .openAIResponses: object = ["output": [["content": [["type": "output_text", "text": content]]]]]
            case .anthropic: object = ["content": [["type": "text", "text": content]]]
            default: object = ["choices": [["message": ["content": content]]]]
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        let request = GenerationCapabilityTests.request()
        _ = try await client.generate(request)
        _ = try await client.reviewQuestions([], request: request)
        _ = try await client.reviewScene("hotel check-in")
        let question = GeneratedQuestion(kind: .spoken, prompt: "Ask for directions", options: [],
            correctAnswer: "Where is the station?", translation: "At a hotel", explanation: "Ask politely")
        _ = try await client.evaluateSpeech(question, transcript: "Where is the station?", languageCode: "en", explanationLanguage: .english)
        #expect(try await client.probe() == (structured && configuration.kind != .anthropic ? .supported : .unsupported))
        #expect(await requests.count == (!structured && configuration.kind != .anthropic ? 10 : 5))
    }

    @Test("Known mandatory-thinking models stay available at low effort", arguments: [
        "google/gemini-3.8-flash", "google/gemini-3.5-flash-lite", "z-ai/glm-5.3-flash",
        "deepseek/deepseek-r1:free", "openai/gpt-5-mini"
    ])
    func mandatoryThinkingUsesLowEffort(_ model: String) async throws {
        actor Requests {
            var count = 0
            var effort: String?
            func record(_ value: String?) { count += 1; effort = value }
        }
        let requests = Requests()
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openRouter,
            baseURL: ProviderKind.openRouter.defaultBaseURL, model: model), apiKey: "fixture-only", transport: { request in
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            let reasoning = try #require(body["reasoning"] as? [String: Any])
            await requests.record(reasoning["effort"] as? String)
            let payload = #"{"choices":[{"message":{"content":"{\"allowed\":true,\"normalized\":\"hotel check-in\",\"reason\":\"fixture\"}"}}]}"#
            return (Data(payload.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        #expect(try await client.probe() == .supported)
        #expect(await requests.count == 1)
        #expect(await requests.effort == "low")
    }

    @Test("An unsupported off parameter is never removed on retry")
    func offParameterRejected() async {
        let fixture = FixtureTransport(statuses: [400], payload: Data())
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat,
            baseURL: "https://gateway.example.com", model: "custom"), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        await #expect(throws: GenerationError.self) { try await client.probe() }
        let requests = await fixture.requests
        #expect(requests.count == 2)
        for request in requests {
            let body = (try? JSONSerialization.jsonObject(with: request.httpBody!)) as? [String: Any]
            #expect(body?["reasoning_effort"] as? String == "none")
        }
    }

    @Test("Deadlines cancel HTTP requests even after response headers arrive", arguments: ["headers", "body"])
    func stalledResponseDeadline(_ phase: String) async {
        let start = ContinuousClock.now
        do {
            _ = try await ProviderDeadline.run(until: .now.advanced(by: .milliseconds(150))) {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [StalledResponseProtocol.self]
                configuration.timeoutIntervalForResource = 2
                return try await RemoteAIClient.response(for: URLRequest(url: URL(string: "https://fixture.example/\(phase)")!), configuration: configuration)
            }
            Issue.record("A stalled response must time out")
        } catch GenerationError.timedOut { }
        catch { Issue.record("Unexpected error: \(error)") }
        #expect(start.duration(to: .now) < .seconds(1))
    }

    @Test("OpenRouter uses the entered API key and chosen model without an authorization exchange", arguments: [200, 401])
    func openRouterAPIKey(_ status: Int) async throws {
        let fixture = FixtureTransport(statuses: [status], payload: try response(for: .openRouter))
        var selected = ProviderPreset.openRouter.configuration
        selected.model = "example/custom-model"
        let client = RemoteAIClient(configuration: selected, apiKey: "fixture-only", transport: { try await fixture.send($0) })
        if status == 200 {
            #expect(try await client.probe() == .supported)
        } else {
            do {
                _ = try await client.probe()
                Issue.record("An invalid API key must fail the connection test")
            } catch GenerationError.invalidCredential { }
        }
        let requests = await fixture.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["model"] as? String == "example/custom-model")
    }

    @Test("Schema fallback sends an explicit JSON schema and keeps store disabled", arguments: [ProviderKind.openAIChat, .openAIResponses])
    func fallback(_ kind: ProviderKind) async throws {
        let fixture = FixtureTransport(statuses: [400, 200], payload: try response(for: kind))
        let client = RemoteAIClient(configuration: configuration(kind), apiKey: "fixture-only", transport: { try await fixture.send($0) })
        #expect(try await client.probe() == .unsupported)
        let requests = await fixture.requests
        #expect(requests.count == 2)
        for (index, request) in requests.enumerated() {
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(body["store"] as? Bool == false)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
            let prompt: String
            if kind == .openAIResponses { prompt = try #require(body["input"] as? String) }
            else { prompt = try #require((body["messages"] as? [[String: String]])?.last?["content"]) }
            let parsed: [String: Any]
            if index == 0 {
                #expect(!prompt.contains("JSON Schema:"))
                if kind == .openAIResponses {
                    let text = try #require(body["text"] as? [String: Any])
                    parsed = try #require((text["format"] as? [String: Any])?["schema"] as? [String: Any])
                } else {
                    let format = try #require(body["response_format"] as? [String: Any])
                    parsed = try #require((format["json_schema"] as? [String: Any])?["schema"] as? [String: Any])
                }
            } else {
                #expect(prompt.contains("JSON Schema:"))
                let schema = try #require(prompt.components(separatedBy: "JSON Schema:\n").last)
                parsed = try #require(JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
            }
            #expect((parsed["required"] as? [String])?.contains("allowed") == true)
            #expect(!prompt.contains("fixture-only"))
        }
    }

    @Test("OpenRouter falls back for unsupported schema routing but never for a missing model", arguments: [true, false])
    func routingFallback(_ unsupportedParameters: Bool) async throws {
        let message = unsupportedParameters ? "No endpoints found that support the provided parameters." : "Model not found."
        let error = try JSONSerialization.data(withJSONObject: ["error": ["code": 404, "message": message]])
        let fixture = FixtureTransport(statuses: [404, 200], payloads: [error, try response(for: .openRouter)])
        let client = RemoteAIClient(configuration: ProviderPreset.openRouter.configuration, apiKey: "fixture-only",
            transport: { try await fixture.send($0) })
        if unsupportedParameters {
            #expect(try await client.probe() == .unsupported)
            #expect(await fixture.requests.count == 2)
            let fallback = try #require(await fixture.requests.last?.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: fallback) as? [String: Any])
            #expect((body["response_format"] as? [String: Any])?["type"] as? String == "json_object")
            #expect((body["provider"] as? [String: Any])?["require_parameters"] as? Bool == true)
        } else {
            do { _ = try await client.probe(); Issue.record("A missing model must fail") }
            catch GenerationError.modelNotFound { }
            #expect(await fixture.requests.count == 1)
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
