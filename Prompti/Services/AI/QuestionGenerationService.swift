import Foundation

enum QuestionGenerationStage: Sendable {
    case generating
    case reviewing
}

/// Incremental pipeline signals. `.stage` may move backwards internally when a
/// rejected question is regenerated; callers that display progress should keep the
/// furthest stage shown instead of regressing.
enum QuestionGenerationEvent: Sendable {
    case stage(QuestionGenerationStage)
    case approved([GeneratedQuestion])
    /// Active work keyed by attempt; nil removes a finished attempt.
    case activity(UUID, QuestionGenerationStage?)
}

actor QuestionGenerationService {
    typealias ProviderFactory = @Sendable (ProviderConfiguration, UUID) throws -> any QuestionProvider
    private let secureStore: SecureStore
    private let usageSink: UsageSink?
    private let providerFactory: ProviderFactory?
    private let reviewMode: @Sendable () async -> QuestionReviewMode
    private let fastReviewerFactory: (@Sendable (UUID) throws -> any FastQuestionReviewer)?

    init(secureStore: SecureStore, usageSink: UsageSink? = nil, providerFactory: ProviderFactory? = nil,
         reviewMode: @escaping @Sendable () async -> QuestionReviewMode = { .generationModel },
         fastReviewerFactory: (@Sendable (UUID) throws -> any FastQuestionReviewer)? = nil) {
        self.secureStore = secureStore
        self.usageSink = usageSink
        self.providerFactory = providerFactory
        self.reviewMode = reviewMode
        self.fastReviewerFactory = fastReviewerFactory
    }

    private struct BatchResult: Sendable {
        var slot: Int
        var batchID: UUID
        var questions: [GeneratedQuestion]
        var error: Error?
        var budgetExhausted = false
        var review: QuestionReviewProvenance? = nil
    }

    /// One reservation table per job, shared by parallel questions before review.
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

    /// Each slot generates and reviews one question independently. A rejected
    /// slot gets at most two fresh attempts, within the same bounded job.
    func generate(
        _ request: TrainingRequest,
        configuration: ProviderConfiguration,
        jobID: UUID = UUID(),
        excluding signatures: Set<String> = [],
        allowsRegeneration: Bool = true,
        reserveAdditionalAttempt: (@Sendable () async -> Bool)? = nil,
        deadline: ContinuousClock.Instant? = nil,
        events: (@Sendable (QuestionGenerationEvent) async throws -> Void)? = nil
    ) async throws -> [GeneratedQuestion] {
        try Task.checkCancellation()
        guard (1...20).contains(request.count), !request.kinds.isEmpty, !request.scenes.isEmpty else {
            throw GenerationError.invalidScene(String(localized: "Choose at least one scene, one question style and 1–20 questions."))
        }

        try await events?(.stage(.generating))

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-demo") {
            let activityID = UUID()
            try await events?(.activity(activityID, .generating))
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(4))
            }
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-generation-error") {
                throw GenerationError.providerUnavailable
            }
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-fill-error"), request.count < 3 {
                throw GenerationError.providerUnavailable
            }
            try await events?(.activity(activityID, .reviewing))
            try await events?(.stage(.reviewing))
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-slow-generation") {
                try await Task.sleep(for: .seconds(1))
            }
            let generated = DemoQuestions.make(request: request)
            let result = ProcessInfo.processInfo.arguments.contains("-prompti-ui-partial-generation")
                ? Array(generated.prefix(max(1, request.count - 2)))
                : generated
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-auto-fill"), result.count > 1 {
                // Deliver an early batch so the session can open while the rest
                // keep generating in the background.
                try await events?(.approved(Array(result.prefix(1))))
                try await events?(.activity(activityID, .generating))
                try await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("-prompti-ui-waiting") ? 30 : 6))
                try await events?(.approved(Array(result.dropFirst(1))))
            } else {
                try await events?(.approved(result))
            }
            try await events?(.activity(activityID, nil))
            return result
        }
        #endif

        let selectedReviewMode = await reviewMode()
        try Task.checkCancellation()
        let reviewer: (any FastQuestionReviewer)?
        if selectedReviewMode == .typeSafeJev {
            if let fastReviewerFactory { reviewer = try fastReviewerFactory(jobID) }
            else {
                guard let key = secureStore.readReviewKey(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw TypeSafeReviewError.missingKey
                }
                reviewer = TypeSafeReviewClient(apiKey: key, usageSink: usageSink, jobID: jobID)
            }
        } else { reviewer = nil }
        let provider = try provider(configuration: configuration, jobID: jobID)
        // Remote providers tolerate a few parallel calls; the on-device model is serialized.
        let concurrency = configuration.kind == .apple ? 1 : 3
        let deadline = deadline ?? ContinuousClock.now.advanced(by: Self.jobDuration(for: request.count))
        // Forgiving mode deliberately asks for a small candidate cushion. The
        // final set is still capped at the requested count, so extra approved
        // candidates are never shown or persisted.
        let extraCandidates = allowsRegeneration && request.generationMode == .forgiving
            ? min(10, max(2, (request.count + 1) / 2)) : 0
        let generationTarget = request.count + extraCandidates
        let maxAttemptsPerQuestion = allowsRegeneration ? 3 : 1
        let candidateFilter = CandidateFilter(signatures: signatures, history: request.previousQuestions)
        let sceneSlots = SceneGenerationPlan.slots(for: request)
        let kinds: [QuestionKind] = [.multipleChoice, .cloze, .spoken].filter { request.kinds.contains($0) }
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
            var pending = Array(0..<generationTarget)
            var attempts = Array(repeating: 0, count: generationTarget)
            var slotScenes: [TravelScene?] = sceneSlots.map { $0 } + Array(repeating: nil, count: extraCandidates)
            var remainingByScene = Dictionary(grouping: sceneSlots, by: \.id).mapValues(\.count)
            var activeByScene: [String: Int] = [:]
            var inFlight = 0
            var firstError: Error?
            var terminalError = false
            func schedule() -> Bool {
                guard !Task.isCancelled, approved.count < request.count, !terminalError, !pending.isEmpty,
                      approved.count + inFlight < generationTarget,
                      ContinuousClock.now < deadline else { return false }
                // Successful peers may have filled a retry's scene already.
                pending.removeAll { slot in
                    guard let scene = slotScenes[slot] else { return false }
                    return remainingByScene[scene.id, default: 0] == 0
                }
                guard !pending.isEmpty else { return false }
                let slot = pending.removeFirst()
                // Flexible candidates compete only for unfilled scene quotas;
                // fast/easy scenes must never consume another scene's places.
                guard let scene = slotScenes[slot] ?? sceneSlots.filter({ remainingByScene[$0.id, default: 0] > 0 }).max(by: {
                    remainingByScene[$0.id, default: 0] - activeByScene[$0.id, default: 0]
                        < remainingByScene[$1.id, default: 0] - activeByScene[$1.id, default: 0]
                }) else { return false }
                slotScenes[slot] = scene
                let needsReservation = slot >= request.count || attempts[slot] > 0
                var batch = request
                batch.count = 1
                batch.kinds = [kinds[slot % kinds.count]]
                batch.previousPrompts = Array((request.previousPrompts + approved.map(\.prompt)).suffix(30))
                batch.scenes = [scene]
                let variation = slot + attempts[slot] * generationTarget
                var diversityHint = goals[variation % goals.count] + "; explore "
                    + perspectives[variation % perspectives.count]
                    + " (prefer " + kinds[slot % kinds.count].rawValue + ")"
                if attempts[slot] > 0 {
                    diversityHint += "; Fresh replacement: the previous attempt was unusable. Recheck tourist role, structure, unique answer and all quality rules."
                }
                batch.diversityHint = diversityHint
                let active = batch
                let batchID = UUID()
                attempts[slot] += 1
                inFlight += 1
                activeByScene[scene.id, default: 0] += 1
                group.addTask {
                    if needsReservation, let reserveAdditionalAttempt, !(await reserveAdditionalAttempt()) {
                        return BatchResult(slot: slot, batchID: batchID, questions: [], error: nil, budgetExhausted: true)
                    }
                    return await self.runBatch(active, slot: slot, batchID: batchID, provider: provider,
                        deadline: deadline, candidateFilter: candidateFilter, reviewer: reviewer,
                        configuration: configuration, events: events)
                }
                return true
            }
            while inFlight < concurrency, schedule() { }
            while let result = try await group.next() {
                inFlight -= 1
                guard let assignedScene = slotScenes[result.slot] else { throw GenerationError.malformedResponse }
                activeByScene[assignedScene.id, default: 0] -= 1
                try Task.checkCancellation()
                try await events?(.activity(result.batchID, nil))
                if let error = result.error {
                    if let error = error as? TypeSafeReviewError {
                        group.cancelAll()
                        throw error
                    }
                    if firstError == nil { firstError = error }
                    if error is CancellationError { throw CancellationError() }
                    if !Self.canRegenerate(after: error) { terminalError = true }
                } else {
                    var delivered: [GeneratedQuestion] = []
                    var remaining = remainingByScene[assignedScene.id, default: 0]
                    for var question in result.questions where remaining > 0 {
                        guard approvedIDs.insert(question.id).inserted,
                              seen.insert(question.contentSignature).inserted,
                              duplicates.insert(question) else { continue }
                        question.sceneID = question.sceneID ?? assignedScene.id
                        question.generation = GenerationMetadata(jobID: jobID, batchID: result.batchID,
                            provider: configuration.kind.rawValue, model: configuration.model, createdAt: .now,
                            sourceFactIDs: question.sourceFactIDs ?? [], checks: QuestionReview.checks,
                            sourceFacts: zip(PromptBuilder.factIDs(for: request), PromptBuilder.facts(for: request)).compactMap {
                                (question.sourceFactIDs ?? []).contains($0.0) ? GenerationSourceFact(id: $0.0, text: $0.1) : nil
                            }, review: result.review)
                        approved.append(question)
                        delivered.append(question)
                        remaining -= 1
                        remainingByScene[assignedScene.id] = remaining
                    }
                    if !delivered.isEmpty { try await events?(.approved(delivered)) }
                }
                try Task.checkCancellation()
                if approved.count == request.count {
                    group.cancelAll()
                    break
                }
                if result.questions.isEmpty, !terminalError, !result.budgetExhausted,
                   attempts[result.slot] < maxAttemptsPerQuestion {
                    // Retry the failed slot immediately, without waiting for peers.
                    pending.insert(result.slot, at: 0)
                }
                while inFlight < concurrency, schedule() { }
            }
            if approved.isEmpty {
                if ContinuousClock.now >= deadline { throw GenerationError.timedOut }
                if let firstError { throw firstError }
            }
            return approved
        }
        try Task.checkCancellation()
        guard !approved.isEmpty else { throw GenerationError.noApprovedQuestions }
        return approved
    }

    /// One question's generate -> validate -> review chain. Errors are returned so
    /// sibling batches keep running; approved questions merge at the caller.
    private func runBatch(
        _ batch: TrainingRequest,
        slot: Int,
        batchID: UUID,
        provider: any QuestionProvider,
        deadline: ContinuousClock.Instant,
        candidateFilter: CandidateFilter,
        reviewer: (any FastQuestionReviewer)?,
        configuration: ProviderConfiguration,
        events: (@Sendable (QuestionGenerationEvent) async throws -> Void)?
    ) async -> BatchResult {
        do {
            try Task.checkCancellation()
            try await events?(.activity(batchID, .generating))
            try await events?(.stage(.generating))
            let output = try await ProviderDeadline.run(until: min(deadline, .now.advanced(by: .seconds(120)))) {
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
            guard !candidates.isEmpty else { return BatchResult(slot: slot, batchID: batchID, questions: [], error: nil) }
            try await events?(.activity(batchID, .reviewing))
            try await events?(.stage(.reviewing))
            let reviewed = try await ProviderDeadline.run(until: min(deadline, .now.advanced(by: .seconds(120)))) {
                try await Self.review(candidates, request: batch, provider: provider, reviewer: reviewer, configuration: configuration)
            }
            let decisions = reviewed.decisions
            try Task.checkCancellation()
            let ids = Set(candidates.map(\.id))
            guard Set(decisions.map(\.questionID)).count == decisions.count,
                  decisions.allSatisfy({ ids.contains($0.questionID) }) else {
                return BatchResult(slot: slot, batchID: batchID, questions: [], error: GenerationError.malformedResponse)
            }
            let allowed = Set(decisions.filter(\.approved).map(\.questionID))
            return BatchResult(slot: slot, batchID: batchID, questions: candidates.filter { allowed.contains($0.id) }, error: nil, review: reviewed.provenance)
        } catch {
            return BatchResult(slot: slot, batchID: batchID, questions: [], error: error)
        }
    }

    private static func review(_ questions: [GeneratedQuestion], request: TrainingRequest,
                               provider: any QuestionProvider, reviewer: (any FastQuestionReviewer)?,
                               configuration: ProviderConfiguration) async throws -> (decisions: [QuestionReview], provenance: QuestionReviewProvenance) {
        var provenance = QuestionReviewProvenance(provider: configuration.kind.rawValue, model: configuration.model)
        if let reviewer {
            // Generation currently sends exactly one validated candidate per chain.
            guard questions.count == 1, let question = questions.first else { throw TypeSafeReviewError.invalidResponse }
            let assessment = try await reviewer.assess(question, request: request)
            try Task.checkCancellation()
            provenance.policyVersion = TypeSafeReviewClient.policyVersion
            provenance.jevModel = assessment.model
            provenance.probabilities = assessment.probabilities
            switch assessment.disposition {
            case .approve, .reject:
                let approved = assessment.disposition == .approve
                provenance.provider = "typesafe"
                provenance.model = assessment.model
                let decision = QuestionReview(questionID: question.id, safe: approved, language: approved,
                    scene: approved, natural: approved, answer: approved, difficulty: approved,
                    reason: approved ? "Jev review passed" : "Jev review rejected")
                return ([decision], provenance)
            case .needsReview:
                // Disclosed in Settings: only uncertain valid judgments escalate.
                // Network/auth/schema failures never silently switch reviewers.
                break
            }
        }
        try Task.checkCancellation()
        return (try await provider.reviewQuestions(questions, request: request), provenance)
    }

    func probeReview(apiKey: String) async throws {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-prompti-ui-jev-probe") {
            if ProcessInfo.processInfo.arguments.contains("-prompti-ui-jev-probe-failure") {
                try await Task.sleep(for: .seconds(3))
                throw TypeSafeReviewError.invalidKey
            }
            try await Task.sleep(for: .milliseconds(200))
            guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw TypeSafeReviewError.missingKey }
            return
        }
        #endif
        try await TypeSafeReviewClient(apiKey: apiKey, usageSink: usageSink).probe()
    }

    static func jobDuration(for count: Int) -> Duration {
        .seconds(min(600, max(180, count * 30)))
    }

    private static func canRegenerate(after error: Error) -> Bool {
        if error is DecodingError { return true }
        guard let error = error as? GenerationError else { return false }
        switch error {
        case .malformedResponse, .truncatedOutput, .refused, .noApprovedQuestions,
             .timedOut, .providerUnavailable: return true
        default: return false
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
        let sceneSlots = SceneGenerationPlan.slots(for: request)
        if ProcessInfo.processInfo.arguments.contains("-prompti-ui-multiple-blanks") {
            let cloze = ClozeContent(segments: ["東京までの切符を", "枚", "。"], blanks: [
                ClozeBlank(id: "quantity", options: ["二", "雨", "駅"], correctAnswer: "二"),
                ClozeBlank(id: "request", options: ["お願いします", "晴れです", "おいしいです"], correctAnswer: "お願いします")
            ])
            return (0..<request.count).map {
                GeneratedQuestion(kind: .cloze, prompt: cloze.prompt, options: [], correctAnswer: cloze.answer,
                    translation: "Two tickets to Tokyo, please.", explanation: "Give the quantity, then make a polite request.",
                    sceneID: sceneSlots[$0].id, cloze: cloze)
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
            if $0 == 0, ProcessInfo.processInfo.arguments.contains("-prompti-ui-long-answers") {
                let options = [
                    "Yes, please. Could you show me how to get to the visitor area by the bay? I would like to walk there, stop at the information desk, and ask about the afternoon guided tour.",
                    "No, thank you. I have already bought my train ticket for tomorrow morning, and I am waiting here for a friend who is bringing a suitcase and a map of the station.",
                    "There are three people in our group, and we would like a table near the window. We have not made a reservation, but we can wait until a table becomes available.",
                    "The weather was sunny yesterday, so we spent the entire afternoon outside. We took photographs of the buildings, bought postcards, and returned to our hotel before dinner."
                ]
                question = GeneratedQuestion(
                    kind: .multipleChoice,
                    prompt: "Would you like directions to the visitor area by the bay?",
                    options: options.map { QuestionOption(text: $0) },
                    correctAnswer: options[0],
                    translation: "A member of staff is offering directions. Choose a reply that accepts the offer and explains where you want to go.",
                    explanation: "Accept the offer politely, then explain your destination. The other replies talk about train tickets, restaurant seating, or yesterday's weather instead of asking for directions."
                )
            }
            question.id = UUID()
            question.sceneID = sceneSlots[$0].id
            return question
        }
    }
}
#endif
