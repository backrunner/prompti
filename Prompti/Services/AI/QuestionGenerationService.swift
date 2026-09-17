import Foundation

enum QuestionGenerationStage: Sendable {
    case generating
    case reviewing
}

/// Incremental pipeline signals. `.stage` may move backwards internally when a
/// rejected batch is regenerated; callers that display progress should keep the
/// furthest stage shown instead of regressing.
enum QuestionGenerationEvent: Sendable {
    case stage(QuestionGenerationStage)
    case approved([GeneratedQuestion])
}

actor QuestionGenerationService {
    typealias ProviderFactory = @Sendable (ProviderConfiguration, UUID) throws -> any QuestionProvider
    private let secureStore: SecureStore
    private let usageSink: UsageSink?
    private let providerFactory: ProviderFactory?

    init(secureStore: SecureStore, usageSink: UsageSink? = nil, providerFactory: ProviderFactory? = nil) {
        self.secureStore = secureStore
        self.usageSink = usageSink
        self.providerFactory = providerFactory
    }

    private struct BatchResult: Sendable {
        var requested: Int
        var batchID: UUID
        var questions: [GeneratedQuestion]
        var error: Error?
    }

    /// One reservation table per job, shared by parallel batches before review.
    /// Even simultaneous identical output is sent for paid review at most once.
    private actor CandidateFilter {
        var signatures: Set<String>
        var ids = Set<UUID>()
        var duplicates: QuestionDuplicateIndex

        init(signatures: Set<String>, history: [GeneratedQuestion]) {
            self.signatures = signatures
            duplicates = QuestionDuplicateIndex(questions: history)
        }

        func reserve(_ questions: [GeneratedQuestion]) -> [GeneratedQuestion] {
            questions.filter { ids.insert($0.id).inserted
                && signatures.insert($0.contentSignature).inserted && duplicates.insert($0) }
        }
    }

    private func provider(configuration: ProviderConfiguration, jobID: UUID) throws -> any QuestionProvider {
        if let providerFactory { return try providerFactory(configuration, jobID) }
        if configuration.kind == .apple {
            guard #available(iOS 26.0, *) else { throw GenerationError.modelUnavailable }
            return AppleQuestionProvider(usageSink: usageSink, jobID: jobID)
        }
        guard let key = secureStore.readAPIKey(for: configuration), !key.isEmpty else { throw GenerationError.missingAPIKey }
        return RemoteAIClient(configuration: configuration, apiKey: key, usageSink: usageSink, jobID: jobID)
    }

    func reviewScene(_ input: String, configuration: ProviderConfiguration) async throws -> SceneReview {
        let normalized = try ContentSafety.normalizeScene(input)
        let review = try await providerReviewScene(normalized, configuration: configuration)
        guard review.isAllowed else {
            throw GenerationError.unsafeContent(String(localized: "That situation is outside Prompti's travel-learning scope."))
        }
        return SceneReview(isAllowed: true, normalized: try ContentSafety.normalizeScene(review.normalized), reason: review.reason)
    }

    /// Runs generation and per-batch review concurrently: each batch is an
    /// independent generate -> review chain, and a bounded number of chains run
    /// in parallel so one slow call never blocks the whole set.
    func generate(
        _ request: TrainingRequest,
        configuration: ProviderConfiguration,
        jobID: UUID = UUID(),
        excluding signatures: Set<String> = [],
        allowsRegeneration: Bool = true,
        deadline: ContinuousClock.Instant? = nil,
        events: (@Sendable (QuestionGenerationEvent) async -> Void)? = nil
    ) async throws -> [GeneratedQuestion] {
        try Task.checkCancellation()
        guard (1...20).contains(request.count), !request.kinds.isEmpty, !request.scenes.isEmpty else {
            throw GenerationError.invalidScene(String(localized: "Choose at least one scene, one question style and 1–20 questions."))
        }

        await events?(.stage(.generating))

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(4))
            }
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-generation-error") {
                throw GenerationError.providerUnavailable
            }
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-fill-error"), request.count < 3 {
                throw GenerationError.providerUnavailable
            }
            await events?(.stage(.reviewing))
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(1))
            }
            let generated = DemoQuestions.make(request: request)
            let result = ProcessInfo.processInfo.arguments.contains("-prompti-ui-partial-generation")
                ? Array(generated.prefix(max(1, request.count - 2)))
                : generated
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-auto-fill"), result.count > 3 {
                // Deliver an early batch so the session can open while the rest
                // keep generating in the background.
                await events?(.approved(Array(result.prefix(3))))
                try await Task.sleep(for: .seconds(2))
                await events?(.approved(Array(result.dropFirst(3))))
            } else {
                await events?(.approved(result))
            }
            return result
        }
        #endif

        let provider = try provider(configuration: configuration, jobID: jobID)
        let batchSize = configuration.kind == .apple ? 2 : 3
        // Remote providers tolerate a few parallel calls; the on-device model is serialized.
        let concurrency = configuration.kind == .apple ? 1 : 3
        let deadline = deadline ?? ContinuousClock.now.advanced(by: .seconds(180))
        // Forgiving mode deliberately asks for a small candidate cushion. The
        // final set is still capped at the requested count, so extra approved
        // candidates are never shown or persisted.
        let extraCandidates = allowsRegeneration && request.generationMode == .forgiving
            ? min(10, max(2, (request.count + 1) / 2)) : 0
        let generationTarget = request.count + extraCandidates
        let maxAttempts = (generationTarget + batchSize - 1) / batchSize + (allowsRegeneration ? 1 : 0)
        let candidateBudget = generationTarget + (allowsRegeneration ? batchSize : 0)
        let candidateFilter = CandidateFilter(signatures: signatures, history: request.previousQuestions)
        let scenes = request.scenes.shuffled()
        let kinds = request.kinds.sorted { $0.rawValue < $1.rawValue }
        let goals = ["clarify an unfamiliar word", "ask for a recommendation", "state a preference",
                     "confirm a quantity", "correct a misunderstanding", "request an alternative",
                     "check an ingredient or included item", "ask for help with the next step",
                     "arrange takeaway or collection", "settle payment"].shuffled()
        let perspectives = ["an unfamiliar item or service", "a different kind of venue",
                            "a local everyday routine", "a choice between alternatives",
                            "a small mix-up to resolve", "a request with a practical constraint",
                            "local courtesy in the selected situation", "a useful local expression in the learning language"].shuffled()

        // All mutable scheduler state lives inside the group body so nothing is
        // sent across isolation domains while children are running.
        let approved: [GeneratedQuestion] = try await withThrowingTaskGroup(of: BatchResult.self) { group in
            var seen = signatures
            var duplicates = QuestionDuplicateIndex(questions: request.previousQuestions)
            var approved: [GeneratedQuestion] = []
            var approvedIDs = Set<UUID>()
            var attempts = 0
            var inFlight = 0
            var inFlightNeed = 0
            var requestedTotal = 0
            var firstError: Error?
            func schedule() -> Bool {
                let initialRemaining = max(0, generationTarget - requestedTotal)
                let target = initialRemaining > 0 ? generationTarget : request.count
                guard approved.count < request.count, firstError == nil,
                      requestedTotal < candidateBudget,
                      approved.count + inFlightNeed < target,
                      attempts < maxAttempts,
                      ContinuousClock.now < deadline else { return false }
                var batch = request
                batch.count = min(batchSize, candidateBudget - requestedTotal, target - approved.count - inFlightNeed, initialRemaining > 0 ? initialRemaining : batchSize)
                batch.previousPrompts = Array((request.previousPrompts + approved.map(\.prompt)).suffix(30))
                // Disjoint settings and goals reduce collisions before any sibling finishes.
                batch.scenes = (0..<min(batch.count, scenes.count)).map { scenes[(requestedTotal + $0) % scenes.count] }
                batch.diversityHint = (0..<batch.count).map {
                    goals[(requestedTotal + $0) % goals.count] + "; explore "
                        + perspectives[(requestedTotal + $0) % perspectives.count]
                        + " (prefer " + kinds[(requestedTotal + $0) % kinds.count].rawValue + ")"
                }.joined(separator: "; ")
                let active = batch
                let batchID = UUID()
                attempts += 1
                inFlight += 1
                inFlightNeed += batch.count
                requestedTotal += batch.count
                group.addTask {
                    await self.runBatch(active, batchID: batchID, provider: provider, deadline: deadline, candidateFilter: candidateFilter, events: events)
                }
                return true
            }
            while inFlight < concurrency, schedule() { }
            while let result = try await group.next() {
                inFlight -= 1
                inFlightNeed -= result.requested
                try Task.checkCancellation()
                if let error = result.error {
                    if firstError == nil { firstError = error }
                } else {
                    var delivered: [GeneratedQuestion] = []
                    var remaining = max(0, request.count - approved.count)
                    for var question in result.questions where remaining > 0 {
                        guard approvedIDs.insert(question.id).inserted,
                              seen.insert(question.contentSignature).inserted,
                              duplicates.insert(question) else { continue }
                        question.sceneID = question.sceneID ?? request.scenes.first?.id
                        question.generation = GenerationMetadata(jobID: jobID, batchID: result.batchID,
                            provider: configuration.kind.rawValue, model: configuration.model, createdAt: .now,
                            sourceFactIDs: question.sourceFactIDs ?? [], checks: QuestionReview.checks,
                            sourceFacts: zip(PromptBuilder.factIDs(for: request), PromptBuilder.facts(for: request)).compactMap {
                                (question.sourceFactIDs ?? []).contains($0.0) ? GenerationSourceFact(id: $0.0, text: $0.1) : nil
                            })
                        approved.append(question)
                        delivered.append(question)
                        remaining -= 1
                    }
                    if !delivered.isEmpty { await events?(.approved(delivered)) }
                }
                if approved.count == request.count {
                    group.cancelAll()
                    break
                }
                while inFlight < concurrency, schedule() { }
            }
            if approved.isEmpty, let firstError { throw firstError }
            return approved
        }
        try Task.checkCancellation()
        guard !approved.isEmpty else { throw GenerationError.noApprovedQuestions }
        return approved
    }

    /// One batch's generate -> validate -> review chain. Errors are returned so
    /// sibling batches keep running; approved questions merge at the caller.
    private func runBatch(
        _ batch: TrainingRequest,
        batchID: UUID,
        provider: any QuestionProvider,
        deadline: ContinuousClock.Instant,
        candidateFilter: CandidateFilter,
        events: (@Sendable (QuestionGenerationEvent) async -> Void)?
    ) async -> BatchResult {
        do {
            await events?(.stage(.generating))
            let output = try await ProviderDeadline.run(until: min(deadline, .now.advanced(by: .seconds(60)))) {
                try await provider.generate(batch)
            }
            let valid = output.prefix(batch.count).filter {
                ContentSafety.validate($0, request: batch)
                    && $0.sourceFactIDs != nil
                    && ($0.kind != .spoken || $0.rubric != nil)
                    && ($0.kind != .cloze || $0.cloze != nil)
            }.map { question in
                var question = question
                question.sceneID = question.sceneID ?? batch.scenes.first?.id
                return question
            }
            try Task.checkCancellation()
            let candidates = await candidateFilter.reserve(valid)
            guard !candidates.isEmpty else { return BatchResult(requested: batch.count, batchID: batchID, questions: [], error: nil) }
            await events?(.stage(.reviewing))
            let decisions = try await ProviderDeadline.run(until: min(deadline, .now.advanced(by: .seconds(60)))) {
                try await provider.reviewQuestions(candidates, request: batch)
            }
            try Task.checkCancellation()
            let ids = Set(candidates.map(\.id))
            guard Set(decisions.map(\.questionID)).count == decisions.count,
                  decisions.allSatisfy({ ids.contains($0.questionID) }) else {
                return BatchResult(requested: batch.count, batchID: batchID, questions: [], error: GenerationError.malformedResponse)
            }
            let allowed = Set(decisions.filter(\.approved).map(\.questionID))
            return BatchResult(requested: batch.count, batchID: batchID, questions: candidates.filter { allowed.contains($0.id) }, error: nil)
        } catch {
            return BatchResult(requested: batch.count, batchID: batchID, questions: [], error: error)
        }
    }

    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String, confidence: Float?, languageCode: String,
                        explanationLanguage: ExplanationLanguage, configuration: ProviderConfiguration) async throws -> SpeechEvaluation {
        try Task.checkCancellation()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              transcript.count <= 1000, confidence.map({ $0 >= 0.3 }) ?? true else {
            return SpeechAnswerEvaluator.evaluate(transcript: "", reference: question.correctAnswer, confidence: confidence)
        }
        guard ContentSafety.isLocallySafe(transcript) else { return unavailableSpeechFeedback() }
        do {
            let provider = try provider(configuration: configuration, jobID: UUID())
            let verdict = try await ProviderDeadline.run(until: .now.advanced(by: .seconds(45))) {
                try await provider.evaluateSpeech(question, transcript: transcript, languageCode: languageCode,
                                                  explanationLanguage: explanationLanguage)
            }
            try Task.checkCancellation()
            guard verdict.isValid else { return unavailableSpeechFeedback() }
            let title: String = switch verdict.result {
            case .correct: String(localized: "Meaning matched")
            case .incorrect: String(localized: "Check the meaning")
            default: String(localized: "Unable to judge")
            }
            return SpeechEvaluation(result: verdict.result, title: title, message: verdict.feedback)
        } catch is CancellationError { throw CancellationError() }
        catch { return unavailableSpeechFeedback() }
    }

    private func unavailableSpeechFeedback() -> SpeechEvaluation {
        SpeechEvaluation(result: .undetermined, title: String(localized: "Unable to judge"),
            message: String(localized: "Semantic feedback is unavailable. This attempt was not scored. Compare the sample answer or try again."))
    }

    func probe(configuration: ProviderConfiguration, apiKey candidateAPIKey: String? = nil) async throws -> StructuredOutputSupport {
        switch configuration.kind {
        case .apple:
            guard AppleModelCapability.status(for: "en") == .available else { throw GenerationError.modelUnavailable }
            return .supported
        default:
            let apiKey = candidateAPIKey ?? secureStore.readAPIKey(for: configuration)
            guard let apiKey, !apiKey.isEmpty else { throw GenerationError.missingAPIKey }
            return try await RemoteAIClient(configuration: configuration, apiKey: apiKey, usageSink: usageSink).probe()
        }
    }

    private func providerReviewScene(_ scene: String, configuration: ProviderConfiguration) async throws -> SceneReview {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            return SceneReview(isAllowed: true, normalized: scene, reason: "Demo review")
        }
        #endif

        return try await provider(configuration: configuration, jobID: UUID()).reviewScene(scene)
    }
}

#if DEBUG
enum DemoQuestions {
    static func make(request: TrainingRequest) -> [GeneratedQuestion] {
        if ProcessInfo.processInfo.arguments.contains("-prompti-ui-multiple-blanks") {
            let cloze = ClozeContent(segments: ["東京までの切符を", "枚", "。"], blanks: [
                ClozeBlank(id: "quantity", options: ["二", "雨", "駅"], correctAnswer: "二"),
                ClozeBlank(id: "request", options: ["お願いします", "晴れです", "おいしいです"], correctAnswer: "お願いします")
            ])
            return (0..<request.count).map { _ in
                GeneratedQuestion(kind: .cloze, prompt: cloze.prompt, options: [], correctAnswer: cloze.answer,
                    translation: "Two tickets to Tokyo, please.", explanation: "Give the quantity, then make a polite request.",
                    sceneID: request.scenes[0].id, cloze: cloze)
            }
        }
        let examples = [
            GeneratedQuestion(
                kind: .multipleChoice,
                prompt: request.language.code == "ja" ? "ご案内しましょうか？" : "Can I help you find something?",
                options: request.language.code == "ja" ? ["切符売り場はどこですか？", "三人です", "晴れです", "おいしいです"].map { QuestionOption(text: $0) } : ["Where is the ticket office?", "Three people", "It's sunny", "Very tasty"].map { QuestionOption(text: $0) },
                correctAnswer: request.language.code == "ja" ? "切符売り場はどこですか？" : "Where is the ticket office?",
                translation: "Station staff are offering help. Tell them what you need.",
                explanation: "A short, polite direction question you can reuse at stations.",
                sampleAnswer: nil
            ),
            GeneratedQuestion(
                kind: .cloze,
                prompt: request.language.code == "ja" ? "すみません、ICカードに ___ したいです。" : "Excuse me, I'd like to ___ my travel card.",
                options: request.language.code == "ja" ? ["チャージ", "予約", "交換", "案内"].map { QuestionOption(text: $0) } : ["top up", "close", "print", "lose"].map { QuestionOption(text: $0) },
                correctAnswer: request.language.code == "ja" ? "チャージ" : "top up",
                translation: "At a ticket machine or counter, you want to add value to your card.",
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
            question.sceneID = request.scenes[$0 % request.scenes.count].id
            return question
        }
    }
}
#endif
