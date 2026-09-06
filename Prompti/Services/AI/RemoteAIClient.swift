import Foundation

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

    var question: GeneratedQuestion? {
        guard let kind = QuestionKind(rawValue: type) else { return nil }
        return GeneratedQuestion(
            kind: kind,
            prompt: prompt,
            options: options.map { QuestionOption(text: $0) },
            correctAnswer: correctAnswer,
            translation: translation,
            explanation: explanation,
            sampleAnswer: sampleAnswer
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

struct RemoteAIClient: Sendable {
    let configuration: ProviderConfiguration
    let apiKey: String

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

    func reviewQuestions(_ questions: [GeneratedQuestion]) async throws -> Bool {
        let result = try await requestJSON(
            system: PromptBuilder.systemInstructions,
            user: try PromptBuilder.batchReviewPrompt(questions),
            schemaName: "prompti_batch_review",
            schema: Self.reviewSchema
        )
        return try JSONDecoder().decode(ReviewPayload.self, from: result.data).allowed
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
            primaryBody = responsesBody(
                system: system,
                user: user,
                schemaName: schemaName,
                schema: schema,
                usesStructuredOutputs: primaryUsesStructuredOutputs
            )
            fallbackBody = primaryUsesStructuredOutputs
                ? responsesBody(system: system, user: user, schemaName: schemaName, schema: schema, usesStructuredOutputs: false)
                : nil
        case .openAIChat, .openRouterOAuth:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            primaryUsesStructuredOutputs = configuration.structuredOutputSupport != .unsupported
            primaryBody = chatBody(
                system: system,
                user: user,
                schemaName: schemaName,
                schema: schema,
                usesStructuredOutputs: primaryUsesStructuredOutputs
            )
            fallbackBody = primaryUsesStructuredOutputs
                ? chatBody(system: system, user: user, schemaName: schemaName, schema: schema, usesStructuredOutputs: false)
                : nil
        case .anthropic:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            primaryUsesStructuredOutputs = false
            primaryBody = [
                "model": configuration.model,
                "max_tokens": 3000,
                "system": system,
                "messages": [["role": "user", "content": user + "\nReturn only valid JSON matching this JSON Schema: \(schema)"]]
            ]
            fallbackBody = nil
        case .apple:
            throw GenerationError.unsupportedProvider
        }

        let primaryResponse = try await perform(request, body: primaryBody)
        if (200..<300).contains(primaryResponse.statusCode) {
            return StructuredJSONResult(
                data: try outputData(from: primaryResponse.data),
                support: primaryUsesStructuredOutputs ? .supported : .unsupported
            )
        }

        if primaryUsesStructuredOutputs,
           [400, 422].contains(primaryResponse.statusCode),
           let fallbackBody {
            let fallbackResponse = try await perform(request, body: fallbackBody)
            try validateStatus(fallbackResponse.statusCode)
            return StructuredJSONResult(
                data: try outputData(from: fallbackResponse.data),
                support: .unsupported
            )
        }

        try validateStatus(primaryResponse.statusCode)
        throw GenerationError.malformedResponse
    }

    private func perform(_ request: URLRequest, body: [String: Any]) async throws -> (data: Data, statusCode: Int) {
        var request = request
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard data.count <= 2_000_000, let http = response as? HTTPURLResponse else {
            throw GenerationError.malformedResponse
        }
        return (data, http.statusCode)
    }

    private func validateStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200..<300: return
        case 402: throw GenerationError.insufficientCredit
        case 401, 403: throw GenerationError.invalidCredential
        case 429: throw GenerationError.rateLimited
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
              let base = URL(string: configuration.baseURL),
              base.scheme?.lowercased() == "https",
              let host = base.host?.lowercased(),
              !isPrivateHost(host) else { throw GenerationError.invalidEndpoint }

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
        if normalizedPath.hasSuffix("v1/\(route)") {
            return base
        }
        return base.appending(path: "v1").appending(path: route)
    }

    private func isPrivateHost(_ host: String) -> Bool {
        host == "localhost" || host.hasSuffix(".local") || host == "0.0.0.0" || host == "::1" ||
            host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") ||
            (host.hasPrefix("172.") && (16...31).contains(Int(host.split(separator: ".").dropFirst().first ?? "0") ?? 0))
    }

    func chatBody(
        system: String,
        user: String,
        schemaName: String,
        schema: [String: Any],
        usesStructuredOutputs: Bool
    ) -> [String: Any] {
        var result: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if usesStructuredOutputs {
            if URL(string: configuration.baseURL)?.host?.lowercased() == "api.openai.com" {
                result["store"] = false
            }
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
    ) -> [String: Any] {
        [
            "model": configuration.model,
            "store": false,
            "instructions": system,
            "input": user,
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
            if let direct = object["output_text"] as? String { return direct }
            guard let output = object["output"] as? [[String: Any]] else { throw GenerationError.malformedResponse }
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                if let text = content.first(where: { ($0["type"] as? String) == "output_text" })?["text"] as? String {
                    return text
                }
            }
        case .openAIChat, .openRouterOAuth:
            if let choices = object["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String { return content }
        case .anthropic:
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
                            "sampleAnswer": ["type": ["string", "null"]]
                        ],
                        "required": ["type", "prompt", "options", "correctAnswer", "translation", "explanation", "sampleAnswer"]
                    ]
                ]
            ],
            "required": ["questions"]
        ]
    }
}
