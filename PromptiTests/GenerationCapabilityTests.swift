import Foundation
import SwiftData
import Testing
@testable import Prompti

actor CapabilityProvider: QuestionProvider {
    enum ReviewMode: Sendable { case approve, rejectFirst, rejectFirstTwo, rejectAll, rejectAfterFirst, rejectInitialAttempt, missing, duplicate, unknown }
    private(set) var requests: [TrainingRequest] = []
    private(set) var speechCalls = 0
    private(set) var reviewedCounts: [Int] = []
    private(set) var rejectedIDs = Set<UUID>()
    private(set) var maxInFlight = 0
    private var inFlight = 0
    var reviewMode: ReviewMode
    let delay: Duration
    let verdict: SemanticVerdict
    let failsAfterRequests: Int?
    let failure: GenerationError
    let fixedPrompt: String?
    let citesAllFacts: Bool

    init(reviewMode: ReviewMode = .approve, delay: Duration = .zero,
         verdict: SemanticVerdict = SemanticVerdict(result: .correct, feedback: "Your request has the same meaning."),
         failsAfterRequests: Int? = nil, failure: GenerationError = .providerUnavailable, fixedPrompt: String? = nil, citesAllFacts: Bool = false) {
        self.reviewMode = reviewMode
        self.delay = delay
        self.verdict = verdict
        self.failsAfterRequests = failsAfterRequests
        self.failure = failure
        self.fixedPrompt = fixedPrompt
        self.citesAllFacts = citesAllFacts
    }

    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        requests.append(request)
        // Capture the call's ordinal before suspending; parallel batches must
        // not read a shared count after other calls have appended.
        let ordinal = requests.count
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }
        if let failsAfterRequests, ordinal > failsAfterRequests { throw failure }
        if delay != .zero { try await Task.sleep(for: delay) }
        return (0..<request.count).map { offset in
            GeneratedQuestion(kind: .multipleChoice, prompt: fixedPrompt ?? "Are you travelling to platform \(ordinal * 10 + offset)?",
                options: ["Yes, thank you", "Very tasty", "Three people", "Sunny"].map { QuestionOption(text: $0) },
                correctAnswer: "Yes, thank you", translation: "A station worker checks your destination.", explanation: "Confirm where you are going.",
                sceneID: request.scenes[0].id, sourceFactIDs: citesAllFacts ? PromptBuilder.factIDs(for: request) : [])
        }
    }

    func reviewScene(_ scene: String) async throws -> SceneReview { SceneReview(isAllowed: true, normalized: scene, reason: "travel") }

    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        reviewedCounts.append(questions.count)
        let rejected: Bool = switch reviewMode {
        case .rejectFirst: reviewedCounts.count == 1
        case .rejectFirstTwo: reviewedCounts.count <= 2
        case .rejectAll: true
        case .rejectAfterFirst: reviewedCounts.count > 1
        case .rejectInitialAttempt: request.diversityHint?.contains("Fresh replacement") != true
        default: false
        }
        if rejected { rejectedIDs.formUnion(questions.map(\.id)) }
        var decisions = questions.map { question in
            QuestionReview(questionID: question.id, safe: !rejected,
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

/// Holds every sibling until the first approved event has been observed.
/// A batching barrier would prevent that event and fail the test deadline.
private actor GatedQuestionProvider: QuestionProvider {
    let fixture = CapabilityProvider()
    private var started = 0
    private var released = false
    private var waiters: [AsyncStream<Void>.Continuation] = []
    private(set) var completed = 0

    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.finish() }
    }

    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        started += 1
        if started > 1, !released {
            let stream = AsyncStream<Void> { waiters.append($0) }
            for await _ in stream { break }
        }
        try Task.checkCancellation()
        let result = try await fixture.generate(request)
        completed += 1
        return result
    }

    func reviewScene(_ scene: String) async throws -> SceneReview { try await fixture.reviewScene(scene) }
    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        try await fixture.reviewQuestions(questions, request: request)
    }
    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String,
                        languageCode: String, explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict {
        try await fixture.evaluateSpeech(question, transcript: transcript, languageCode: languageCode, explanationLanguage: explanationLanguage)
    }
}

private actor TypedCapabilityProvider: QuestionProvider {
    let fixture = CapabilityProvider()
    private(set) var requests: [TrainingRequest] = []
    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        requests.append(request)
        let ordinal = requests.count
        var question = try await fixture.generate(request)[0]
        if request.kinds == [.cloze] {
            let cloze = ClozeContent(segments: ["Please take me to platform \(ordinal) ", "."],
                blanks: [ClozeBlank(id: "courtesy", options: ["please", "rain", "ticket", "yesterday"], correctAnswer: "please")])
            question.kind = .cloze
            question.cloze = cloze
            question.prompt = cloze.prompt
            question.correctAnswer = cloze.answer
            question.options = []
        } else if request.kinds == [.spoken] {
            question.kind = .spoken
            question.prompt = "Ask how to reach platform \(ordinal)."
            question.correctAnswer = "How do I reach platform \(ordinal)?"
            question.sampleAnswer = question.correctAnswer
            question.options = []
            question.rubric = SpeechRubric(intent: "Ask for directions", requiredDetails: ["platform \(ordinal)"], acceptableVariations: ["polite paraphrases"])
        }
        return [question]
    }
    func reviewScene(_ scene: String) async throws -> SceneReview { try await fixture.reviewScene(scene) }
    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        try await fixture.reviewQuestions(questions, request: request)
    }
    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String,
                        languageCode: String, explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict {
        try await fixture.evaluateSpeech(question, transcript: transcript, languageCode: languageCode, explanationLanguage: explanationLanguage)
    }
}

@Suite("Structured generation and semantic feedback")
struct GenerationCapabilityTests {
    static func request(count: Int = 3) -> TrainingRequest {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        return TrainingRequest(destination: destination, language: destination.languages[1], explanationLanguage: .english,
            scenes: [catalog.commonScenes[2]], difficulty: .basic, kinds: [.multipleChoice], count: count)
    }

    private func service(_ fixture: CapabilityProvider) -> QuestionGenerationService {
        QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture })
    }

    @Test("Mixed sets schedule every selected type as an independently validated single question", arguments: [ProviderKind.apple, .openAIChat])
    func mixedTypesStayBalanced(_ kind: ProviderKind) async throws {
        let fixture = TypedCapabilityProvider()
        let generation = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture })
        var request = Self.request(count: 6)
        request.kinds = [.multipleChoice, .cloze, .spoken]
        let questions = try await generation.generate(request, configuration: ProviderConfiguration(kind: kind))
        #expect(questions.count == 6)
        for style in request.kinds { #expect(questions.filter { $0.kind == style }.count == 2) }
        #expect(await fixture.requests.allSatisfy { $0.count == 1 && $0.kinds.count == 1 })
    }

    @Test("Single-type requests reduce prompt and schema size without dropping shared quality rules", arguments: QuestionKind.allCases)
    func focusedQuestionRequest(_ kind: QuestionKind) throws {
        var request = Self.request(count: 1)
        request.kinds = Set(QuestionKind.allCases)
        let fullPrompt = try PromptBuilder.questionPrompt(request)
        let fullSchema = try JSONSerialization.data(withJSONObject: RemoteAIClient.questionSchema(for: request.kinds))
        request.kinds = [kind]
        let prompt = try PromptBuilder.questionPrompt(request)
        let schema = try JSONSerialization.data(withJSONObject: RemoteAIClient.questionSchema(for: request.kinds))
        #expect(prompt.utf8.count < fullPrompt.utf8.count)
        #expect(schema.count < fullSchema.count)
        #expect(prompt.contains("learner role is fixed") && prompt.contains("sourceFactIDs"))
        #expect(prompt.contains("near-duplicate") && prompt.contains(request.difficulty.generationConstraints))
        #expect(prompt.contains("independently expand") && prompt.contains("never stereotype"))
        print("Focused request \(kind.rawValue): prompt \(fullPrompt.utf8.count) -> \(prompt.utf8.count) bytes, schema \(fullSchema.count) -> \(schema.count) bytes")
    }

    @Test("Wrong question types are rejected before paid review")
    func rejectsUnrequestedType() async {
        var request = Self.request(count: 1)
        request.kinds = [.spoken]
        let fixture = CapabilityProvider() // Deliberately returns multiple choice.
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(request, configuration: ProviderConfiguration())
        }
        #expect(await fixture.reviewedCounts.isEmpty)
        #expect(await fixture.requests.count == 3)
    }

    @Test("Large sets use single-question requests and every accepted question has review provenance", arguments: [ProviderKind.apple, .openAIResponses])
    func smallBatches(_ kind: ProviderKind) async throws {
        let provider = CapabilityProvider()
        let generated = try await service(provider).generate(Self.request(count: 8), configuration: ProviderConfiguration(kind: kind, model: "fixture"))
        #expect(generated.count == 8)
        let requests = await provider.requests
        #expect(requests.allSatisfy { $0.count == 1 })
        #expect(Set(generated.compactMap { $0.generation?.jobID }).count == 1)
        #expect(Set(generated.compactMap { $0.generation?.batchID }).count == requests.count)
        #expect(generated.allSatisfy { $0.generation?.checks == QuestionReview.checks && $0.generation?.model == "fixture" })
    }

    @Test("One rejected question does not discard approved peers")
    func individualReview() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectFirst)
        let result = try await service(fixture).generate(Self.request(), configuration: ProviderConfiguration())
        #expect(result.count == 3)
        let rejectedIDs = await fixture.rejectedIDs
        #expect(result.allSatisfy { !rejectedIDs.contains($0.id) })
        #expect(await fixture.requests.count == 4) // Only the rejected slot is regenerated.
    }

    @Test("Every rejected slot automatically gets a fresh attempt")
    func eachQuestionRetries() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectInitialAttempt)
        let result = try await service(fixture).generate(Self.request(count: 5), configuration: ProviderConfiguration())
        #expect(result.count == 5)
        #expect(await fixture.requests.count == 10)
        #expect(await fixture.reviewedCounts.allSatisfy { $0 == 1 })
    }

    @Test("Two rejections recover on the last allowed attempt")
    func finalAttemptSucceeds() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectFirstTwo)
        let result = try await service(fixture).generate(Self.request(count: 1), configuration: ProviderConfiguration())
        #expect(result.count == 1)
        #expect(await fixture.requests.count == 3)
    }

    @Test("Persistent rejection stops at two retries per question")
    func rejectionLimit() async {
        let fixture = CapabilityProvider(reviewMode: .rejectAll)
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 4), configuration: ProviderConfiguration())
        }
        #expect(await fixture.requests.count == 12)
    }

    @Test("Malformed output and timeouts get bounded automatic regeneration", arguments: [
        GenerationError.malformedResponse, .truncatedOutput, .timedOut, .providerUnavailable
    ])
    func recoverableErrors(_ error: GenerationError) async {
        let fixture = CapabilityProvider(failsAfterRequests: 0, failure: error)
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 1), configuration: ProviderConfiguration())
        }
        #expect(await fixture.requests.count == 3)
    }

    @Test("Automatic preparation reserves every extra attempt and respects an exhausted budget")
    func retryReservation() async {
        actor Budget {
            var remaining = 1
            var calls = 0
            func reserve() -> Bool {
                calls += 1
                guard remaining > 0 else { return false }
                remaining -= 1
                return true
            }
        }
        let budget = Budget()
        let fixture = CapabilityProvider(reviewMode: .rejectAll)
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 1), configuration: ProviderConfiguration(),
                reserveAdditionalAttempt: { await budget.reserve() })
        }
        #expect(await fixture.requests.count == 2)
        #expect(await budget.calls == 2)
    }

    @Test("An expired job never starts a paid generation request")
    func expiredJob() async {
        let fixture = CapabilityProvider()
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 1), configuration: ProviderConfiguration(), deadline: .now)
        }
        #expect(await fixture.requests.isEmpty)
    }

    @Test("Generation and review keep the learner on the tourist side for every question style")
    func touristPerspective() throws {
        var request = Self.request()
        request.kinds = [.multipleChoice, .cloze, .spoken]
        let generation = try PromptBuilder.questionPrompt(request)
        let review = try PromptBuilder.qualityReviewPrompt([], request: request)
        #expect(PromptBuilder.systemInstructions.contains("ALWAYS a visiting tourist"))
        #expect(generation.contains("utterance spoken by the tourist"))
        #expect(generation.contains("telling the tourist what to say"))
        #expect(!generation.contains("vary register and turn direction"))
        #expect(review.contains("Reject role reversals with scene=false"))
        #expect(review.contains("filled cloze text, spoken answer/sample"))
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
        let fixture = CapabilityProvider(failsAfterRequests: 3)
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
                case .activity: break
                case .stage(let stage): stages.insert(stage)
                case .approved(let questions): approvedEvents += 1; approvedTotal += questions.count
                }
            }
        }
        let collector = Collector()
        let provider = CapabilityProvider(delay: .milliseconds(40))
        let result = try await service(provider).generate(Self.request(count: 9),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"), events: { event in
            await collector.record(event)
        })
        #expect(result.count == 9)
        #expect(await collector.approvedEvents == 9)
        #expect(await collector.approvedTotal == 9)
        #expect(await collector.stages == [.generating, .reviewing])
    }

    @Test("The first approved question is delivered before slow siblings finish", .timeLimit(.minutes(1)))
    func noSiblingBarrier() async throws {
        actor Observer {
            var sawFirst = false
            func isFirst() -> Bool {
                if sawFirst { return false }
                sawFirst = true
                return true
            }
        }
        let provider = GatedQuestionProvider()
        let observer = Observer()
        let generation = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in provider })
        let result = try await generation.generate(Self.request(count: 3), configuration: ProviderConfiguration(), events: { event in
            if case .approved(let questions) = event, await observer.isFirst() {
                #expect(questions.count == 1)
                #expect(await provider.completed == 1)
                await provider.release()
            }
        })
        #expect(result.count == 3)
    }

    @Test("A failed inventory save stops scheduling new paid requests")
    func consumerFailure() async {
        let fixture = CapabilityProvider()
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 5), configuration: ProviderConfiguration(), events: { event in
                if case .approved = event { throw GenerationError.modelUnavailable }
            })
        }
        #expect((1...3).contains(await fixture.requests.count))
    }

    @Test("Identical exercises across parallel batches are delivered once")
    func deduplication() async throws {
        let provider = CapabilityProvider(fixedPrompt: "Where is the exit?")
        let result = try await service(provider).generate(Self.request(count: 6),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        #expect(result.count == 1)
        // Attempts stay bounded even though the remainder could never be filled.
        #expect(await provider.requests.count == 16)
        #expect(await provider.reviewedCounts.reduce(0, +) == 1)
    }

    @Test("Forgiving generation requests a candidate cushion but returns the target size")
    func forgivingGenerationBudget() async throws {
        let fixture = CapabilityProvider()
        var request = Self.request(count: 5)
        request.generationMode = .forgiving
        let result = try await service(fixture).generate(request,
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        #expect(result.count == 5)
        let requested = await fixture.requests.map(\.count).reduce(0, +)
        #expect((5...7).contains(requested)) // At most two single-question peers remain in flight.
    }

    @Test("Flexible candidates absorb individual rejections without a serial refill")
    func forgivingRejections() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectFirst)
        var request = Self.request(count: 5)
        request.generationMode = .forgiving
        let result = try await service(fixture).generate(request, configuration: ProviderConfiguration())
        #expect(result.count == 5)
        #expect((6...8).contains(await fixture.requests.count))
    }

    @Test("Pre-generation cannot exceed its reserved count even in flexible mode")
    func reservedBudget() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectFirst)
        var request = Self.request(count: 3)
        request.generationMode = .forgiving
        let result = try await service(fixture).generate(request, configuration: ProviderConfiguration(), allowsRegeneration: false)
        #expect(result.count == 2)
        #expect(await fixture.requests.map(\.count).reduce(0, +) == 3)
    }

    @Test("A known duplicate incurs no review request, and an intra-batch duplicate is reviewed once")
    func deduplicateBeforeReview() async throws {
        let fixture = CapabilityProvider(fixedPrompt: "Where is the exit?")
        var request = Self.request()
        let first = try await service(fixture).generate(request, configuration: ProviderConfiguration(), allowsRegeneration: false)
        #expect(first.count == 1)
        #expect(await fixture.reviewedCounts == [1])
        request.previousQuestions = first
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(request, configuration: ProviderConfiguration(), allowsRegeneration: false)
        }
        #expect(await fixture.reviewedCounts == [1])
    }

    @Test("Invalid credentials stop scheduling after the initial parallel work")
    func noFailureRetry() async {
        let fixture = CapabilityProvider(failsAfterRequests: 0, failure: .invalidCredential)
        await #expect(throws: GenerationError.self) {
            try await service(fixture).generate(Self.request(count: 20), configuration: ProviderConfiguration())
        }
        #expect(await fixture.requests.count == 3)
    }

    @Test("All set sizes and modes respect delivery and candidate bounds", arguments: [1, 3, 5, 8, 20], GenerationMode.allCases)
    func deliveryBounds(_ count: Int, _ mode: GenerationMode) async throws {
        actor Collector {
            var total = 0
            func receive(_ event: QuestionGenerationEvent) {
                if case .approved(let questions) = event { total += questions.count }
            }
        }
        let collector = Collector()
        let fixture = CapabilityProvider()
        var request = Self.request(count: count)
        request.generationMode = mode
        let result = try await service(fixture).generate(request, configuration: ProviderConfiguration(), events: {
            await collector.receive($0)
        })
        #expect(result.count == count)
        #expect(await collector.total == count)
        let requested = await fixture.requests.map(\.count).reduce(0, +)
        #expect(requested <= count + (mode == .forgiving ? min(10, max(2, (count + 1) / 2)) : 0))
    }

    @Test("Duplicate comparison normalizes punctuation and width, retaining distinct numeric tasks")
    func duplicateFormatting() {
        var question = GeneratedQuestion(kind: .multipleChoice, prompt: "Could you please confirm platform 12 for this train?",
            options: [], correctAnswer: "Yes, please.", translation: "", explanation: "")
        var index = QuestionDuplicateIndex(questions: [question])
        question.prompt = "COULD you please confirm platform １２ for this train！"
        let inserted1 = index.insert(question)
        #expect(!inserted1)
        question.correctAnswer = "Of course."
        let inserted2 = index.insert(question)
        #expect(!inserted2)
        question.correctAnswer = "Yes, please."
        question.prompt = "Could you please confirm platform 13 for this train?"
        let inserted3 = index.insert(question)
        #expect(inserted3)
        question.prompt = "お持ち帰りですか？"
        let inserted4 = index.insert(question)
        #expect(inserted4)
        question.prompt = "お持ち帰りですか。"
        let inserted5 = index.insert(question)
        #expect(!inserted5)
    }

    @Test("Moving a cloze gap or switching to speech cannot repeat the same complete utterance")
    func duplicateSolvedUtterance() {
        var question = GeneratedQuestion(kind: .cloze, prompt: "I'd like ___ coffee.", options: [],
            correctAnswer: "I'd like iced coffee.", translation: "", explanation: "")
        var index = QuestionDuplicateIndex(questions: [question])
        question.prompt = "I'd like iced ___."
        let shifted = index.insert(question)
        #expect(!shifted)
        question.kind = .spoken
        question.prompt = "Order an iced coffee."
        let spoken = index.insert(question)
        #expect(!spoken)
    }

    @Test("Review prompts retain constraints without resending generation instructions or option UUIDs")
    func compactReviewPrompt() throws {
        let question = GeneratedQuestion(kind: .multipleChoice, prompt: "Hot or iced?",
            options: [QuestionOption(text: "Iced, please.")], correctAnswer: "Iced, please.", translation: "Ordering at a cafe.", explanation: "State a temperature.")
        let request = Self.request()
        let prompt = try PromptBuilder.qualityReviewPrompt([question], request: request)
        #expect(!prompt.contains("Generate exactly"))
        #expect(!prompt.contains(question.options[0].id.uuidString))
        #expect(prompt.contains(question.id.uuidString))
        #expect(prompt.contains(request.difficulty.generationConstraints))
        #expect(prompt.contains("sourceFactIDs") && prompt.contains("near duplicates"))
        #expect(prompt.count < (try PromptBuilder.questionPrompt(request)).count)
    }

    @Test("Broad scenes carry local inspiration without turning examples into selectable topics")
    func sceneDiversityPrompt() throws {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "singapore")
        #expect(Set(catalog.suggestedScenes.map(\.id)) == ["dining", "transit"])
        #expect(!catalog.commonScenes.contains { ["cafe", "desserts", "market"].contains($0.id) })
        for city in catalog.destinations where city.country == "Japan" {
            #expect(DestinationCultureCatalog.facts(for: city, languageCode: "ja").contains { $0.contains("sushi") && $0.contains("wagashi") })
        }
        #expect(DestinationCultureCatalog.cityLife["osaka"]?.contains("takoyaki") == true)
        #expect(DestinationCultureCatalog.cityLife["kyoto"]?.contains("matcha") == true)
        // Legacy labels still resolve when viewing old saved questions.
        #expect(destination.localScenes.contains { $0.id == "singapore-highlights" })
        var request = Self.request(count: 2)
        request.destination = destination
        request.scenes = [catalog.commonScenes[0]]
        request.diversityHint = "Explore a different kind of venue."
        let prompt = try PromptBuilder.questionPrompt(request)
        #expect(prompt.contains("Bak kut teh") && prompt.contains("Durian") && prompt.contains("kopi"))
        #expect(!prompt.contains("singapore-highlights") && !prompt.contains("singapore-bak-kut-teh"))
        #expect(prompt.contains("independently expand") && prompt.contains("never create a new scene ID"))
        #expect(prompt.contains("Explore a different kind of venue."))
    }

    @Test("Every destination and learning language receives bounded cultural context with traceable facts")
    func allDestinationCultureCoverage() throws {
        let catalog = DestinationCatalog()
        #expect(Set(catalog.destinations.map(\.id)) == Set(DestinationCultureCatalog.cityLife.keys))
        #expect(Set(catalog.destinations.map(\.country)) == Set(DestinationCultureCatalog.regions.keys))
        for destination in catalog.destinations {
            let region = try #require(DestinationCultureCatalog.region(forCountry: destination.country))
            let city = try #require(DestinationCultureCatalog.cityLife[destination.id])
            for language in destination.languages {
                var request = Self.request(count: 1)
                request.destination = destination
                request.language = language
                let localFacts = DestinationCultureCatalog.facts(for: destination, languageCode: language.code)
                // City life, regional culture, situational etiquette and the chosen language.
                #expect(localFacts.count == 4)
                #expect(localFacts.contains(city) && localFacts.contains(region.culture) && localFacts.contains(region.etiquette))
                #expect(localFacts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                #expect(localFacts.joined().utf8.count < 2000)
                let prompt = try PromptBuilder.questionPrompt(request)
                let contextLine = try #require(prompt.split(separator: "\n").first { $0.hasPrefix("{") })
                let context = try #require(JSONSerialization.jsonObject(with: Data(contextLine.utf8)) as? [String: Any])
                let facts = try #require(context["approvedFacts"] as? [[String: String]])
                #expect(Set(localFacts).isSubset(of: Set(facts.compactMap { $0["text"] })))
                #expect(facts.compactMap { $0["id"] } == PromptBuilder.factIDs(for: request))
                #expect(Set(PromptBuilder.factIDs(for: request)).count == facts.count)
                let review = try PromptBuilder.qualityReviewPrompt([], request: request)
                #expect(review.contains("misplaced customs") && review.contains("standard polite reply"))
            }
        }
    }

    @Test("Culture keeps the chosen language and known custom regions without guessing city facts")
    func cultureLanguageAndCustomDestinations() throws {
        let catalog = DestinationCatalog()
        let japan = catalog.destination(id: "osaka")
        let japanese = DestinationCultureCatalog.facts(for: japan, languageCode: "ja")
        let english = DestinationCultureCatalog.facts(for: japan, languageCode: "en")
        #expect(japanese.dropLast() == english.dropLast())
        #expect(japanese.last?.contains("です・ます") == true)
        #expect(english.last?.contains("international English") == true)
        #expect(english.last?.contains("です・ます") == false)
        for country in ["France", "法国", "FR"] {
            let custom = try #require(catalog.makeCustomDestination(city: "Lyon", country: country))
            let facts = DestinationCultureCatalog.facts(for: custom, languageCode: "en")
            #expect(facts.count == 3)
            #expect(facts.contains { $0.contains("French shop") })
            #expect(!facts.contains { $0.contains("Paris") || $0.contains("Tokyo") })
        }
        let unknown = try #require(catalog.makeCustomDestination(city: "Unknown place", country: "Unknown region"))
        let fallback = DestinationCultureCatalog.facts(for: unknown, languageCode: "en")
        #expect(fallback.count == 1 && fallback[0].contains("international English"))
    }

    @Test("Cultural fact IDs pass validation and survive generation provenance without accepting unknown IDs")
    func culturalFactProvenance() async throws {
        var request = Self.request(count: 1)
        request.destination = DestinationCatalog().destination(id: "paris")
        let fixture = CapabilityProvider(citesAllFacts: true)
        let generated = try await service(fixture).generate(request, configuration: ProviderConfiguration(kind: .openAIResponses))
        var question = try #require(generated.first)
        #expect(ContentSafety.validate(question, request: request))
        #expect((question.sourceFactIDs?.count ?? 0) > request.destination.facts.count)
        #expect(question.generation?.sourceFacts.map(\.text) == PromptBuilder.facts(for: request))
        #expect(question.generation?.sourceFacts.map(\.id) == question.sourceFactIDs)
        question.sourceFactIDs = ["paris:invented"]
        #expect(!ContentSafety.validate(question, request: request))
    }

    @Test("Single-category batches explore different perspectives without extra planning calls")
    func singleSceneExpansion() async throws {
        let catalog = DestinationCatalog()
        var request = Self.request(count: 8)
        request.destination = catalog.destination(id: "singapore")
        request.scenes = [catalog.commonScenes[0]]
        let fixture = CapabilityProvider(delay: .milliseconds(20))
        let result = try await service(fixture).generate(request, configuration: ProviderConfiguration(kind: .openAIResponses))
        let batches = await fixture.requests
        #expect(result.count == 8 && batches.count == 8)
        #expect(batches.allSatisfy { $0.scenes.map(\.id) == ["dining"] && $0.destination.facts == request.destination.facts })
        #expect(Set(batches.compactMap(\.diversityHint)).count == batches.count)
        #expect(batches.allSatisfy { $0.diversityHint?.contains("explore") == true })
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
        let provider = CapabilityProvider(reviewMode: .rejectAfterFirst)
        let service = service(provider)
        let session = PracticeSessionState(records: [], request: Self.request(count: 5),
            configuration: ProviderConfiguration(kind: .openAIResponses, model: "fixture"))
        session.fill(using: service, context: container.mainContext)
        while session.isFilling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.records.isEmpty)
        #expect(session.hasRemaining)
        let calls = await provider.requests.count
        session.fillIfNeeded(using: service, context: container.mainContext)
        #expect(!session.isFilling)
        #expect(await provider.requests.count == calls)
        #expect(session.fillMessage == String(localized: "Automatic preparation has stopped. Retry to prepare the remaining questions."))
    }

    @Test("Multi-gap answers require all choices and reject ambiguous or mismatched structures")
    func cloze() throws {
        var request = Self.request()
        request.kinds = [.cloze]
        let cloze = ClozeContent(segments: ["I'd like ", " tickets to ", "."], blanks: [
            ClozeBlank(id: "quantity", options: ["two", "eat", "go", "where"], correctAnswer: "two"),
            ClozeBlank(id: "place", options: ["Tokyo", "soon", "please", "yesterday"], correctAnswer: "Tokyo")
        ])
        var question = GeneratedQuestion(kind: .cloze, prompt: cloze.prompt, options: [], correctAnswer: cloze.answer,
            translation: "I'd like two tickets to Tokyo.", explanation: "Specify quantity and destination.", sceneID: "transit", cloze: cloze)
        #expect(ContentSafety.validate(question, request: request))
        #expect(!cloze.isCorrect(["quantity": "two"]))
        #expect(!cloze.isCorrect(["quantity": "two", "place": "soon"]))
        #expect(cloze.isCorrect(["quantity": "two", "place": "Tokyo"]))
        question.cloze?.blanks[1].id = "quantity"
        #expect(!ContentSafety.validate(question, request: request))
        question.cloze = cloze
        question.cloze?.blanks[0].options[1] = "two"
        #expect(!ContentSafety.validate(question, request: request))
        question.cloze = cloze
        question.correctAnswer = "Wrong filled sentence"
        #expect(!ContentSafety.validate(question, request: request))
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
