import Foundation

enum QuestionGenerationStage: Sendable {
    case generating
    case reviewing
}

actor QuestionGenerationService {
    private let secureStore: SecureStore

    init(secureStore: SecureStore) {
        self.secureStore = secureStore
    }

    func reviewScene(_ input: String, configuration: ProviderConfiguration) async throws -> SceneReview {
        let normalized = try ContentSafety.normalizeScene(input)
        let review = try await providerReviewScene(normalized, configuration: configuration)
        guard review.isAllowed, ContentSafety.isLocallySafe(review.normalized) else {
            throw GenerationError.unsafeContent(String(localized: "That situation is outside Prompti's travel-learning scope."))
        }
        return review
    }

    func generate(
        _ request: TrainingRequest,
        configuration: ProviderConfiguration,
        progress: (@Sendable (QuestionGenerationStage) async -> Void)? = nil
    ) async throws -> [GeneratedQuestion] {
        try Task.checkCancellation()
        let candidates: [GeneratedQuestion]
        let isProviderApproved: Bool

        await progress?(.generating)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(4))
            }
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-generation-error") {
                throw GenerationError.providerUnavailable
            }
            await progress?(.reviewing)
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(1))
            }
            let generated = DemoQuestions.make(request: request)
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-partial-generation") {
                return Array(generated.prefix(max(1, request.count - 2)))
            }
            return generated
        }
        #endif

        switch configuration.kind {
        case .apple:
            guard #available(iOS 26.0, *) else { throw GenerationError.modelUnavailable }
            let provider = AppleQuestionProvider()
            candidates = try await provider.generate(request)
            try Task.checkCancellation()
            await progress?(.reviewing)
            isProviderApproved = try await provider.reviewQuestions(candidates)
        default:
            guard let apiKey = secureStore.readAPIKey(for: configuration), !apiKey.isEmpty else { throw GenerationError.missingAPIKey }
            let provider = RemoteAIClient(configuration: configuration, apiKey: apiKey)
            candidates = try await provider.generate(request)
            try Task.checkCancellation()
            await progress?(.reviewing)
            isProviderApproved = try await provider.reviewQuestions(candidates)
        }

        guard isProviderApproved else {
            throw GenerationError.unsafeContent(String(localized: "The generated batch did not pass safety review."))
        }
        let approved = candidates.filter { ContentSafety.validate($0, request: request) }
        guard !approved.isEmpty else { throw GenerationError.noApprovedQuestions }
        return Array(approved.prefix(request.count))
    }

    func probe(configuration: ProviderConfiguration, apiKey candidateAPIKey: String? = nil) async throws -> StructuredOutputSupport {
        switch configuration.kind {
        case .apple:
            guard AppleModelCapability.status(for: "en") == .available else { throw GenerationError.modelUnavailable }
            return .supported
        default:
            let apiKey = candidateAPIKey ?? secureStore.readAPIKey(for: configuration)
            guard let apiKey, !apiKey.isEmpty else { throw GenerationError.missingAPIKey }
            return try await RemoteAIClient(configuration: configuration, apiKey: apiKey).probe()
        }
    }

    private func providerReviewScene(_ scene: String, configuration: ProviderConfiguration) async throws -> SceneReview {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            return SceneReview(isAllowed: true, normalized: scene, reason: "Demo review")
        }
        #endif

        switch configuration.kind {
        case .apple:
            guard #available(iOS 26.0, *) else { throw GenerationError.modelUnavailable }
            return try await AppleQuestionProvider().reviewScene(scene)
        default:
            guard let apiKey = secureStore.readAPIKey(for: configuration), !apiKey.isEmpty else { throw GenerationError.missingAPIKey }
            return try await RemoteAIClient(configuration: configuration, apiKey: apiKey).reviewScene(scene)
        }
    }
}

#if DEBUG
enum DemoQuestions {
    static func make(request: TrainingRequest) -> [GeneratedQuestion] {
        let examples = [
            GeneratedQuestion(
                kind: .multipleChoice,
                prompt: request.language.code == "ja" ? "切符売り場はどこですか？" : "Where is the ticket office?",
                options: request.language.code == "ja" ? ["あちらです", "おいしいです", "三人です", "晴れです"].map { QuestionOption(text: $0) } : ["Over there", "Very tasty", "Three people", "Sunny"].map { QuestionOption(text: $0) },
                correctAnswer: request.language.code == "ja" ? "あちらです" : "Over there",
                translation: "Where is the ticket office?",
                explanation: "A short, polite direction question you can reuse at stations.",
                sampleAnswer: nil
            ),
            GeneratedQuestion(
                kind: .cloze,
                prompt: request.language.code == "ja" ? "ICカードに ___ したいです。" : "I'd like to ___ my travel card.",
                options: request.language.code == "ja" ? ["チャージ", "予約", "交換", "案内"].map { QuestionOption(text: $0) } : ["top up", "close", "print", "lose"].map { QuestionOption(text: $0) },
                correctAnswer: request.language.code == "ja" ? "チャージ" : "top up",
                translation: "I'd like to top up my IC card.",
                explanation: "Use this when adding value to a transit card.",
                sampleAnswer: nil
            ),
            GeneratedQuestion(
                kind: .spoken,
                prompt: request.language.code == "ja" ? "駅員に新宿への行き方を聞いてください。" : "Ask how to get to the city centre.",
                options: [],
                correctAnswer: request.language.code == "ja" ? "新宿へはどう行けばいいですか？" : "How do I get to the city centre?",
                translation: "Ask how to reach your destination.",
                explanation: "A polite open question works even when several routes are possible.",
                sampleAnswer: request.language.code == "ja" ? "新宿へはどう行けばいいですか？" : "How do I get to the city centre?"
            )
        ]
        let activeExamples = ProcessInfo.processInfo.arguments.contains("-prompti-ui-spoken-question")
            ? examples.filter { $0.kind == .spoken }
            : examples
        return (0..<request.count).map {
            var question = activeExamples[$0 % activeExamples.count]
            question.id = UUID()
            return question
        }
    }
}
#endif
