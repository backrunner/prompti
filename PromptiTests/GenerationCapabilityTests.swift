import Foundation
import SwiftData
import Testing
@testable import Prompti

actor CapabilityProvider: QuestionProvider {
    enum ReviewMode: Sendable { case approve, rejectFirst, missing, duplicate, unknown }
    private(set) var requests: [TrainingRequest] = []
    private(set) var speechCalls = 0
    private(set) var maxInFlight = 0
    private var inFlight = 0
    var reviewMode: ReviewMode
    let delay: Duration
    let verdict: SemanticVerdict
    /// Fail every batch whose size is below this value. Ordinal-based failure
    /// is meaningless once batches run concurrently, so failures key off the
    /// request itself.
    let failsBelowCount: Int?
    let fixedPrompt: String?

    init(reviewMode: ReviewMode = .approve, delay: Duration = .zero,
         verdict: SemanticVerdict = SemanticVerdict(result: .correct, feedback: "Your request has the same meaning."),
         failsBelowCount: Int? = nil, fixedPrompt: String? = nil) {
        self.reviewMode = reviewMode
        self.delay = delay
        self.verdict = verdict
        self.failsBelowCount = failsBelowCount
        self.fixedPrompt = fixedPrompt
    }

    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        requests.append(request)
        // Capture the call's ordinal before suspending; parallel batches must
        // not read a shared count after other calls have appended.
        let ordinal = requests.count
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if let failsBelowCount, request.count < failsBelowCount { throw GenerationError.providerUnavailable }
        if delay != .zero { try await Task.sleep(for: delay) }
        return (0..<request.count).map { offset in
            GeneratedQuestion(kind: .multipleChoice, prompt: fixedPrompt ?? "Where is platform \(ordinal * 10 + offset)?",
                options: ["Over there", "Very tasty", "Three people", "Sunny"].map { QuestionOption(text: $0) },
                correctAnswer: "Over there", translation: "Asking for directions.", explanation: "A clear, polite direction question.",
                sceneID: request.scenes[0].id, sourceFactIDs: [])
        }
    }

    func reviewScene(_ scene: String) async throws -> SceneReview { SceneReview(isAllowed: true, normalized: scene, reason: "travel") }

    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        var decisions = questions.enumerated().map { index, question in
            QuestionReview(questionID: question.id, safe: reviewMode != .rejectFirst || index != 0,
                language: true, scene: true, natural: true, answer: true, difficulty: true, reason: "Reviewed")
        }
        switch reviewMode {
        case .missing: decisions = []
        case .duplicate: decisions += decisions
        case .unknown: decisions[0].questionID = UUID()
        default: break
        }
        return decisions
    }

    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String, languageCode: String,
                        explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict {
        speechCalls += 1
        if delay != .zero { try await Task.sleep(for: delay) }
        return verdict
    }
}

@Suite("Structured generation and semantic feedback")
struct GenerationCapabilityTests {
    static func request(count: Int = 3) -> TrainingRequest {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        return TrainingRequest(destination: destination, language: destination.languages[1], explanationLanguage: .english,
            scenes: [catalog.commonScenes[2]], difficulty: .basic, kinds: [.multipleChoice, .cloze, .spoken], count: count)
    }

    private func service(_ fixture: CapabilityProvider) -> QuestionGenerationService {
        QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture })
    }

    @Test("Large sets use bounded batches and every accepted question has review provenance", arguments: [ProviderKind.apple, .openAIResponses])
    func smallBatches(_ kind: ProviderKind) async throws {
        let provider = CapabilityProvider()
        let generated = try await service(provider).generate(Self.request(count: 8), configuration: ProviderConfiguration(kind: kind, model: "fixture"))
        #expect(generated.count == 8)
        let requests = await provider.requests
        #expect(requests.allSatisfy { $0.count <= (kind == .apple ? 2 : 3) })
        #expect(Set(generated.compactMap { $0.generation?.jobID }).count == 1)
        #expect(Set(generated.compactMap { $0.generation?.batchID }).count == requests.count)
        #expect(generated.allSatisfy { $0.generation?.checks == QuestionReview.checks && $0.generation?.model == "fixture" })
    }

    @Test("One rejected question does not discard approved peers")
    func individualReview() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectFirst)
        let result = try await service(fixture).generate(Self.request(), configuration: ProviderConfiguration())
        #expect(result.count == 2)
        #expect(result.allSatisfy { !$0.prompt.contains("10") })
        #expect(await fixture.requests.count == 2) // One bounded regeneration, then partial success.
    }

    @Test("Missing, duplicate and unknown review IDs cannot approve a question", arguments: [CapabilityProvider.ReviewMode.missing, .duplicate, .unknown])
    func reviewIDs(_ mode: CapabilityProvider.ReviewMode) async {
        let fixture = CapabilityProvider(reviewMode: mode)
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(), configuration: ProviderConfiguration())
        }
    }

    @Test("A later provider failure preserves already reviewed questions")
    func partialFailure() async throws {
        let fixture = CapabilityProvider(failsBelowCount: 3)
        let result = try await service(fixture).generate(Self.request(count: 5), configuration: ProviderConfiguration())
        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.generation != nil })
    }

    @Test("Remote batches overlap while the on-device model stays serialized", arguments: [
        (ProviderKind.openAIResponses, 3), (ProviderKind.apple, 1)
    ])
    func batchConcurrency(_ kind: ProviderKind, _ expectedPeak: Int) async throws {
        let provider = CapabilityProvider(delay: .milliseconds(120))
        let generated = try await service(provider).generate(Self.request(count: 9),
            configuration: ProviderConfiguration(kind: kind, model: "fixture"))
        #expect(generated.count == 9)
        #expect(await provider.maxInFlight == expectedPeak)
    }

    @Test("Approved questions stream incrementally instead of arriving in one result")
    func incrementalDelivery() async throws {
        actor Collector {
            private(set) var approvedEvents = 0
            private(set) var approvedTotal = 0
            private(set) var stages = Set<QuestionGenerationStage>()
            func record(_ event: QuestionGenerationEvent) {
                switch event {
                case .stage(let stage): stages.insert(stage)
                case .approved(let questions): approvedEvents += 1; approvedTotal += questions.count
                }
            }
        }
        let collector = Collector()
        let provider = CapabilityProvider(delay: .milliseconds(40))
        let result = try await service(provider).generate(Self.request(count: 9),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture")) { event in
            await collector.record(event)
        }
        #expect(result.count == 9)
        #expect(await collector.approvedEvents == 3)
        #expect(await collector.approvedTotal == 9)
        #expect(await collector.stages == [.generating, .reviewing])
    }

    @Test("Identical exercises across parallel batches are delivered once")
    func deduplication() async throws {
        let provider = CapabilityProvider(fixedPrompt: "Where is the exit?")
        let result = try await service(provider).generate(Self.request(count: 6),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        #expect(result.count == 1)
        // Attempts stay bounded even though the remainder could never be filled.
        #expect(await provider.requests.count <= 3)
    }

    @MainActor
    @Test("Session fill persists approved questions and reports a review shortfall")
    func sessionFill() async throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let provider = CapabilityProvider()
        let service = service(provider)
        let session = PracticeSessionState(records: [], request: Self.request(count: 4),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        session.fill(using: service, context: container.mainContext)
        while session.isFilling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(session.records.count == 4)
        #expect(session.fillMessage == nil)
        #expect(session.furthestStage == .reviewing)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 4)
    }

    @MainActor
    @Test("A rejected remainder surfaces as a retryable shortfall when questions exist")
    func sessionShortfall() async throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let provider = CapabilityProvider(reviewMode: .rejectFirst)
        let service = service(provider)
        let session = PracticeSessionState(records: [], request: Self.request(count: 5),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        session.fill(using: service, context: container.mainContext)
        while session.isFilling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.records.isEmpty)
        #expect(session.hasRemaining)
        #expect(session.fillMessage == String(localized: "Some questions did not pass review. Retry to prepare the rest."))
    }

    @Test("Multi-gap answers require all choices and reject ambiguous or mismatched structures")
    func cloze() throws {
        let cloze = ClozeContent(segments: ["I'd like ", " tickets to ", "."], blanks: [
            ClozeBlank(id: "quantity", options: ["two", "eat", "go", "where"], correctAnswer: "two"),
            ClozeBlank(id: "place", options: ["Tokyo", "soon", "please", "yesterday"], correctAnswer: "Tokyo")
        ])
        var question = GeneratedQuestion(kind: .cloze, prompt: cloze.prompt, options: [], correctAnswer: cloze.answer,
            translation: "I'd like two tickets to Tokyo.", explanation: "Specify quantity and destination.", sceneID: "transit", cloze: cloze)
        #expect(ContentSafety.validate(question, request: Self.request()))
        #expect(!cloze.isCorrect(["quantity": "two"]))
        #expect(!cloze.isCorrect(["quantity": "two", "place": "soon"]))
        #expect(cloze.isCorrect(["quantity": "two", "place": "Tokyo"]))
        question.cloze?.blanks[1].id = "quantity"
        #expect(!ContentSafety.validate(question, request: Self.request()))
        question.cloze = cloze
        question.cloze?.blanks[0].options[1] = "two"
        #expect(!ContentSafety.validate(question, request: Self.request()))
        question.cloze = cloze
        question.correctAnswer = "Wrong filled sentence"
        #expect(!ContentSafety.validate(question, request: Self.request()))
    }

    @Test("Paraphrases use provider meaning feedback; low confidence never calls or scores")
    func speech() async throws {
        let fixture = CapabilityProvider()
        let service = service(fixture)
        let question = GeneratedQuestion(kind: .spoken, prompt: "Ask how to reach the station.", options: [],
            correctAnswer: "How do I get to the station?", translation: "Ask for directions.", explanation: "A polite request.",
            sampleAnswer: "How do I get to the station?", rubric: SpeechRubric(intent: "Ask for directions", requiredDetails: ["station"], acceptableVariations: ["Could you tell me the way to the station?"]))
        let result = try await service.evaluateSpeech(question, transcript: "Could you tell me the way to the station?", confidence: 0.9,
            languageCode: "en", explanationLanguage: .english, configuration: ProviderConfiguration())
        #expect(result.result == .correct)
        #expect(await fixture.speechCalls == 1)
        let uncertain = try await service.evaluateSpeech(question, transcript: question.correctAnswer, confidence: 0.1,
            languageCode: "en", explanationLanguage: .english, configuration: ProviderConfiguration())
        #expect(uncertain.result == .undetermined)
        #expect(await fixture.speechCalls == 1)
        let prompt = try PromptBuilder.speechEvaluationPrompt(question, transcript: "not the station", languageCode: "en", explanationLanguage: .simplifiedChinese)
        #expect(prompt.contains("negation") && prompt.contains("Simplified Chinese"))
        #expect(!prompt.contains("attemptHistory"))
    }

    @Test("Malformed semantic verdicts are unscored", arguments: [AttemptResult.skipped, .reported])
    func invalidVerdict(_ outcome: AttemptResult) async throws {
        let fixture = CapabilityProvider(verdict: SemanticVerdict(result: outcome, feedback: "OK"))
        let question = GeneratedQuestion(kind: .spoken, prompt: "Ask for water", options: [], correctAnswer: "Water, please.", translation: "Water", explanation: "Polite")
        let result = try await service(fixture).evaluateSpeech(question, transcript: "Could I have water?", confidence: nil,
            languageCode: "en", explanationLanguage: .english, configuration: ProviderConfiguration())
        #expect(result.result == .undetermined)
    }

    @Test("Cancellation during semantic feedback propagates without returning a score")
    func cancelSpeech() async throws {
        let fixture = CapabilityProvider(delay: .seconds(10))
        let service = service(fixture)
        let question = GeneratedQuestion(kind: .spoken, prompt: "Ask for water", options: [], correctAnswer: "Water, please.", translation: "Water", explanation: "Polite")
        let task = Task {
            try await service.evaluateSpeech(question, transcript: "Could I have water?", confidence: nil,
                languageCode: "en", explanationLanguage: .english, configuration: ProviderConfiguration())
        }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
