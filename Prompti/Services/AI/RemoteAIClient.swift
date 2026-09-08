import Foundation
import Darwin

struct QuestionBatchPayload: Codable, Sendable {
    var questions: [QuestionPayload]
}

struct QuestionPayload: Codable, Sendable {
    var type: String
    var prompt: String
    var options: [String]
    var correctAnswer: String
    var translation: String
    var explanation: String
    var sampleAnswer: String?
    var sceneID: String? = nil
    var cloze: ClozeContent? = nil
    var rubric: SpeechRubric? = nil
    var sourceFactIDs: [String]? = nil

    var question: GeneratedQuestion? {
        guard let kind = QuestionKind(rawValue: type) else { return nil }
        return GeneratedQuestion(
            kind: kind,
            prompt: prompt,
            options: options.map { QuestionOption(text: $0) },
            correctAnswer: correctAnswer,
            translation: translation,
            explanation: explanation,
            sampleAnswer: sampleAnswer,
            sceneID: sceneID, cloze: cloze, rubric: rubric, sourceFactIDs: sourceFactIDs
        )
    }
}

struct ReviewPayload: Codable, Sendable {
    var allowed: Bool
    var normalized: String?
    var reason: String
}

private struct StructuredJSONResult: Sendable {
    let data: Data
    let support: StructuredOutputSupport
}

struct RemoteAIClient: QuestionProvider {
    let configuration: ProviderConfiguration
    let apiKey: String
    var transport: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil

    var usageSink: UsageSink? = nil
    var jobID: UUID? = nil

    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        let prompt = try PromptBuilder.questionPrompt(request)
        let result = try await requestJSON(
            system: PromptBuilder.systemInstructions,
            user: prompt,
            schemaName: "prompti_question_batch",
            schema: Self.questionSchema
        )
        let payload = try JSONDecoder().decode(QuestionBatchPayload.self, from: result.data)
        return payload.questions.compactMap(\.question)
    }

    func reviewScene(_ scene: String) async throws -> SceneReview {
        let result = try await requestJSON(
            system: PromptBuilder.systemInstructions,
            user: PromptBuilder.sceneReviewPrompt(scene),
            schemaName: "prompti_scene_review",
            schema: Self.reviewSchema
        )
        let payload = try JSONDecoder().decode(ReviewPayload.self, from: result.data)
        return SceneReview(
            isAllowed: payload.allowed,
            normalized: payload.normalized ?? scene,
            reason: payload.reason
        )
    }

    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        let result = try await requestJSON(system: PromptBuilder.systemInstructions,
            user: PromptBuilder.qualityReviewPrompt(questions, request: request),
            schemaName: "prompti_question_review", schema: Self.qualityReviewSchema)
        return try JSONDecoder().decode(QuestionReviews.self, from: result.data).decisions
    }

    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String, languageCode: String,
                        explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict {
        let result = try await requestJSON(system: PromptBuilder.systemInstructions,
            user: PromptBuilder.speechEvaluationPrompt(question, transcript: transcript, languageCode: languageCode,
                                                       explanationLanguage: explanationLanguage),
            schemaName: "prompti_speech_evaluation", schema: Self.semanticSchema)
        return try JSONDecoder().decode(SemanticVerdict.self, from: result.data)
    }

    func probe() async throws -> StructuredOutputSupport {
        let result = try await requestJSON(
            system: PromptBuilder.systemInstructions,
            user: PromptBuilder.sceneReviewPrompt("hotel check-in"),
            schemaName: "prompti_capability_probe",
            schema: Self.reviewSchema
        )
        let payload = try JSONDecoder().decode(ReviewPayload.self, from: result.data)
        guard payload.allowed else { throw GenerationError.malformedResponse }
        return result.support
    }

    private func requestJSON(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> StructuredJSONResult {
        let endpoint = try endpointURL()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let primaryBody: [String: Any]
        let fallbackBody: [String: Any]?
        let primaryUsesStructuredOutputs: Bool
        switch configuration.kind {
        case .openAIResponses:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            primaryUsesStructuredOutputs = configuration.structuredOutputSupport != .unsupported
            primaryBody = try responsesBody(
                system: system,
                user: user,
                schemaName: schemaName,
                schema: schema,
                usesStructuredOutputs: primaryUsesStructuredOutputs
            )
            fallbackBody = primaryUsesStructuredOutputs
                ? try responsesBody(system: system, user: user, schemaName: schemaName, schema: schema, usesStructuredOutputs: false)
                : nil
        case .openAIChat, .openRouterOAuth:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            primaryUsesStructuredOutputs = configuration.structuredOutputSupport != .unsupported
            primaryBody = try chatBody(
                system: system,
                user: user,
                schemaName: schemaName,
                schema: schema,
                usesStructuredOutputs: primaryUsesStructuredOutputs
            )
            fallbackBody = primaryUsesStructuredOutputs
                ? try chatBody(system: system, user: user, schemaName: schemaName, schema: schema, usesStructuredOutputs: false)
                : nil
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            primaryUsesStructuredOutputs = false
            primaryBody = [
                "model": configuration.model,
                "max_tokens": Self.outputLimit(for: schemaName),
                "system": system,
                "messages": [["role": "user", "content": try Self.schemaPrompt(user, schema: schema)]]
            ]
            fallbackBody = nil
        case .apple:
            throw GenerationError.unsupportedProvider
        }

        let primaryResponse = try await perform(request, body: primaryBody, operation: schemaName)
        if (200..<300).contains(primaryResponse.statusCode) {
            return StructuredJSONResult(
                data: try outputData(from: primaryResponse.data),
                support: primaryUsesStructuredOutputs ? .supported : .unsupported
            )
        }

        if primaryUsesStructuredOutputs,
           [400, 422].contains(primaryResponse.statusCode),
           let fallbackBody {
            let fallbackResponse = try await perform(request, body: fallbackBody, operation: schemaName + ".fallback")
            try validateStatus(fallbackResponse.statusCode, data: fallbackResponse.data)
            return StructuredJSONResult(
                data: try outputData(from: fallbackResponse.data),
                support: .unsupported
            )
        }

        try validateStatus(primaryResponse.statusCode, data: primaryResponse.data)
        throw GenerationError.malformedResponse
    }

    private func perform(_ request: URLRequest, body: [String: Any], operation: String) async throws -> (data: Data, statusCode: Int) {
        var request = request
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        var usage = ModelUsage(jobID: jobID, provider: configuration.kind.rawValue, model: configuration.model, operation: operation)
        await usageSink?(usage)
        do {
            let data: Data
            let http: HTTPURLResponse
            if let transport {
                (data, http) = try await transport(request)
            } else {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpCookieStorage = nil
                configuration.urlCache = nil
                configuration.timeoutIntervalForResource = 90
                let session = URLSession(configuration: configuration, delegate: ProviderRedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse,
                      response.expectedContentLength <= 2_000_000 else { throw GenerationError.malformedResponse }
                http = response
                var buffer = Data()
                for try await byte in bytes {
                    guard buffer.count < 2_000_000 else { throw GenerationError.malformedResponse }
                    buffer.append(byte)
                }
                data = buffer
            }
            usage.complete(data: data, statusCode: http.statusCode)
            await usageSink?(usage)
            try Task.checkCancellation()
            guard data.count <= 2_000_000 else { throw GenerationError.malformedResponse }
            return (data, http.statusCode)
        } catch {
            usage.status = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled ? "cancelled" : "failed"
            await usageSink?(usage)
            guard let error = error as? URLError else { throw error }
            if Task.isCancelled || error.code == .cancelled { throw CancellationError() }
            if error.code == .timedOut { throw GenerationError.timedOut }
            throw GenerationError.networkUnavailable
        }
    }

    func validateStatus(_ statusCode: Int, data: Data = Data()) throws {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? error?["type"] as? String
        switch statusCode {
        case 200..<300: return
        case 300..<400: throw GenerationError.invalidEndpoint
        case 402: throw GenerationError.insufficientCredit
        case 401: throw GenerationError.invalidCredential
        case 403: throw GenerationError.permissionDenied
        case 404: throw GenerationError.modelNotFound
        case 408, 504: throw GenerationError.timedOut
        case 429:
            if code == "insufficient_quota" || code == "quota_exceeded" { throw GenerationError.insufficientCredit }
            throw GenerationError.rateLimited
        case 500...599: throw GenerationError.providerUnavailable
        default: throw GenerationError.malformedResponse
        }
    }

    private func outputData(from data: Data) throws -> Data {
        let text = try extractText(from: data)
        guard let output = stripCodeFence(text).data(using: .utf8) else { throw GenerationError.malformedResponse }
        return output
    }

    func endpointURL() throws -> URL {
        guard configuration.kind != .openRouterOAuth || configuration.baseURL == ProviderKind.openRouterOAuth.defaultBaseURL,
              var base = URL(string: configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme?.lowercased() == "https",
              let host = base.host?.lowercased(),
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              !Self.isPrivateHost(host) else { throw GenerationError.invalidEndpoint }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.path = base.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let normalizedBase = components.url else { throw GenerationError.invalidEndpoint }
        base = normalizedBase
        let route: String
        switch configuration.kind {
        case .openAIResponses: route = "responses"
        case .openAIChat, .openRouterOAuth: route = "chat/completions"
        case .anthropic: route = "messages"
        case .apple: throw GenerationError.unsupportedProvider
        }
        if base.path.hasSuffix("/v1") {
            return base.appending(path: route)
        }
        let normalizedPath = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath.hasSuffix("/\(route)") {
            return base
        }
        return base.appending(path: "v1").appending(path: route)
    }

    static func isPrivateHost(_ input: String) -> Bool {
        let host = input.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local")
            || !host.contains(".") && !host.contains(":") || host.contains("%") { return true }
        var ipv4 = in_addr()
        if inet_aton(host, &ipv4) == 1 {
            let address = UInt32(bigEndian: ipv4.s_addr)
            let first = address >> 24
            let second = (address >> 16) & 255
            return first == 0 || first == 10 || first == 127 || first >= 224
                || (first == 100 && (64...127).contains(second))
                || (first == 169 && second == 254)
                || (first == 172 && (16...31).contains(second))
                || (first == 192 && (second == 168 || second == 0))
                || (first == 198 && (18...19).contains(second))
        }
        if host.contains(":") {
            var ipv6 = in6_addr()
            guard inet_pton(AF_INET6, host, &ipv6) == 1 else { return true }
            let bytes = withUnsafeBytes(of: ipv6) { Array($0) }
            // Permit ordinary global unicast only; this also excludes mapped
            // IPv4, ULA, loopback, link-local and multicast addresses.
            return bytes[0] & 0xe0 != 0x20
        }
        return false
    }

    private static func outputLimit(for schemaName: String) -> Int {
        schemaName == "prompti_question_batch" ? 12_000 : 4_000
    }

    private static func schemaPrompt(_ user: String, schema: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw GenerationError.malformedResponse }
        return user + "\nReturn only a JSON object matching this JSON Schema:\n" + json
    }

    func chatBody(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        usesStructuredOutputs: Bool
    ) throws -> [String: Any] {
        var result: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": try Self.schemaPrompt(user, schema: schema)]
            ]
        ]
        if URL(string: configuration.baseURL)?.host?.lowercased() == "api.openai.com" {
            result["store"] = false
            result["max_completion_tokens"] = Self.outputLimit(for: schemaName)
        } else {
            result["max_tokens"] = Self.outputLimit(for: schemaName)
        }
        if usesStructuredOutputs {
            result["response_format"] = [
                "type": "json_schema",
                "json_schema": ["name": schemaName, "strict": true, "schema": schema]
            ]
        } else {
            result["response_format"] = ["type": "json_object"]
        }
        return result
    }

    func responsesBody(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        usesStructuredOutputs: Bool
    ) throws -> [String: Any] {
        [
            "model": configuration.model,
            "store": false,
            "instructions": system,
            "input": try Self.schemaPrompt(user, schema: schema),
            "max_output_tokens": Self.outputLimit(for: schemaName),
            "text": [
                "format": usesStructuredOutputs
                    ? ["type": "json_schema", "name": schemaName, "strict": true, "schema": schema]
                    : ["type": "json_object"]
            ]
        ]
    }

    func extractText(from data: Data) throws -> String {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenerationError.malformedResponse
        }
        switch configuration.kind {
        case .openAIResponses:
            if object["status"] as? String == "incomplete" { throw GenerationError.truncatedOutput }
            if object["status"] as? String == "failed" { throw GenerationError.providerUnavailable }
            if let direct = object["output_text"] as? String { return direct }
            guard let output = object["output"] as? [[String: Any]] else { throw GenerationError.malformedResponse }
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                if content.contains(where: { $0["type"] as? String == "refusal" }) { throw GenerationError.refused }
                if let text = content.first(where: { ($0["type"] as? String) == "output_text" })?["text"] as? String {
                    return text
                }
            }
        case .openAIChat, .openRouterOAuth:
            if let choices = object["choices"] as? [[String: Any]] {
                if choices.first?["finish_reason"] as? String == "length" { throw GenerationError.truncatedOutput }
                if choices.first?["finish_reason"] as? String == "content_filter" { throw GenerationError.refused }
                if let message = choices.first?["message"] as? [String: Any],
                   let refusal = message["refusal"] as? String, !refusal.isEmpty { throw GenerationError.refused }
            }
            if let choices = object["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String { return content }
        case .anthropic:
            if object["stop_reason"] as? String == "max_tokens" { throw GenerationError.truncatedOutput }
            if object["stop_reason"] as? String == "refusal" { throw GenerationError.refused }
            if let content = object["content"] as? [[String: Any]],
               let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String { return text }
        case .apple: break
        }
        throw GenerationError.malformedResponse
    }

    private func stripCodeFence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("```") {
            result = result.replacingOccurrences(of: "```json", with: "")
            result = result.replacingOccurrences(of: "```", with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var stringArray: [String: Any] { ["type": "array", "items": ["type": "string"]] }
    private static func object(_ properties: [String: Any]) -> [String: Any] {
        ["type": "object", "additionalProperties": false, "properties": properties, "required": properties.keys.sorted()]
    }
    private static func nullable(_ schema: [String: Any]) -> [String: Any] {
        ["anyOf": [schema, ["type": "null"]]]
    }
    private static var clozeSchema: [String: Any] {
        object(["segments": stringArray, "blanks": ["type": "array", "items": object([
            "id": ["type": "string"], "options": stringArray, "correctAnswer": ["type": "string"]])]])
    }
    private static var rubricSchema: [String: Any] {
        object(["intent": ["type": "string"], "requiredDetails": stringArray, "acceptableVariations": stringArray])
    }
    private static var qualityReviewSchema: [String: Any] {
        var fields: [String: Any] = ["questionID": ["type": "string"], "reason": ["type": "string"]]
        for key in ["safe", "language", "scene", "natural", "answer", "difficulty"] { fields[key] = ["type": "boolean"] }
        return object(["decisions": ["type": "array", "items": object(fields)]])
    }
    private static var semanticSchema: [String: Any] {
        object(["result": ["type": "string", "enum": ["correct", "incorrect", "undetermined"]], "feedback": ["type": "string"]])
    }

    private static var reviewSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "allowed": ["type": "boolean"],
                "normalized": ["type": ["string", "null"]],
                "reason": ["type": "string"]
            ],
            "required": ["allowed", "normalized", "reason"]
        ]
    }

    private static var questionSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "questions": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "properties": [
                            "type": ["type": "string", "enum": ["cloze", "multipleChoice", "spoken"]],
                            "prompt": ["type": "string"],
                            "options": ["type": "array", "items": ["type": "string"]],
                            "correctAnswer": ["type": "string"],
                            "translation": ["type": "string"],
                            "explanation": ["type": "string"],
                            "sampleAnswer": ["type": ["string", "null"]],
                            "sceneID": ["type": "string"],
                            "cloze": Self.nullable(Self.clozeSchema),
                            "rubric": Self.nullable(Self.rubricSchema),
                            "sourceFactIDs": Self.stringArray
                        ],
                        "required": ["type", "prompt", "options", "correctAnswer", "translation", "explanation", "sampleAnswer", "sceneID", "cloze", "rubric", "sourceFactIDs"]
                    ]
                ]
            ],
            "required": ["questions"]
        ]
    }
}

/// Provider credentials must never follow an HTTP redirect to another endpoint.
final class ProviderRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
