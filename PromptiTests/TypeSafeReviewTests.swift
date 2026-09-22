import Foundation
import SwiftData
import Testing
@testable import Prompti

private actor JevReviewFixture: FastQuestionReviewer {
    var calls = 0
    let disposition: FastQuestionAssessment.Disposition
    let failAfter: Int?
    init(_ disposition: FastQuestionAssessment.Disposition = .approve, failAfter: Int? = nil) {
        self.disposition = disposition
        self.failAfter = failAfter
    }
    func assess(_ question: GeneratedQuestion, request: TrainingRequest) async throws -> FastQuestionAssessment {
        calls += 1
        if let failAfter, calls > failAfter { throw TypeSafeReviewError.invalidKey }
        return FastQuestionAssessment(disposition: disposition, model: TypeSafeReviewClient.model,
            probabilities: Dictionary(uniqueKeysWithValues: TypeSafeReviewClient.checks.keys.map { ($0, 0.01) }))
    }
}

@Suite("Optional TypeSafe question review")
struct TypeSafeReviewTests {
    static func question() -> GeneratedQuestion {
        GeneratedQuestion(kind: .multipleChoice, prompt: "Would you like a ticket?",
            options: ["Yes, please.", "It is sunny.", "That was tasty.", "Good night."].map { QuestionOption(text: $0) },
            correctAnswer: "Yes, please.", translation: "At the station, respond to a staff member's offer.",
            explanation: "Accept the offer politely.", sceneID: "transit", sourceFactIDs: [])
    }
    static func payload(probabilities: [String: Double]? = nil, model: String = TypeSafeReviewClient.model) throws -> Data {
        let values = probabilities ?? Dictionary(uniqueKeysWithValues: TypeSafeReviewClient.checks.keys.map { ($0, 0.01) })
        return try JSONSerialization.data(withJSONObject: ["model": model,
            "answers": values.mapValues { ["type": "noul", "noul": $0] },
            "usage": ["input_tokens": 123, "output_tokens": 42]])
    }

    @Test("Jev uses the System One contract and sends all independent checks in one request")
    func contract() async throws {
        let question = Self.question()
        let client = TypeSafeReviewClient(apiKey: " fixture-jev ", transport: { request in
            #expect(request.url == TypeSafeReviewClient.endpoint)
            #expect(request.httpMethod == "POST" && request.timeoutInterval == 30)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-jev")
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect(Set(body.keys) == ["model", "state", "questions"])
            #expect(body["model"] as? String == TypeSafeReviewClient.model)
            let questions = try #require(body["questions"] as? [String: [String: Any]])
            #expect(Set(questions.keys) == Set(TypeSafeReviewClient.checks.keys))
            #expect(questions.count == 14)
            #expect(questions.values.allSatisfy { $0["type"] as? String == "noul" })
            let text = String(decoding: request.httpBody!, as: UTF8.self)
            #expect(!text.contains("fixture-jev") && !text.contains(question.id.uuidString))
            #expect(question.options.allSatisfy { !text.contains($0.id.uuidString) })
            #expect(text.contains("untrusted data") && text.contains("tourist"))
            return (try Self.payload(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let result = try await client.assess(question, request: GenerationCapabilityTests.request(count: 1))
        #expect(result.disposition == .approve)
    }

    @Test("A single defect cannot be averaged away", arguments: ["sexual", "answer", "role"])
    func thresholds(_ key: String) throws {
        var probabilities = Dictionary(uniqueKeysWithValues: TypeSafeReviewClient.checks.keys.map { ($0, 0.0) })
        let limit = TypeSafeReviewClient.safetyChecks.contains(key) ? 0.02 : 0.1
        probabilities[key] = limit
        #expect(try TypeSafeReviewClient.assessment(from: Self.payload(probabilities: probabilities)).disposition == .approve)
        probabilities[key] = limit + 0.000001
        #expect(try TypeSafeReviewClient.assessment(from: Self.payload(probabilities: probabilities)).disposition == .needsReview)
        probabilities[key] = 0.89
        #expect(try TypeSafeReviewClient.assessment(from: Self.payload(probabilities: probabilities)).disposition == .needsReview)
        probabilities[key] = 0.9
        #expect(try TypeSafeReviewClient.assessment(from: Self.payload(probabilities: probabilities)).disposition == .reject)
    }

    @Test("Missing, extra, invalid, wrong-type and unexpected-model answers fail closed", arguments: ["missing", "extra", "negative", "over", "string", "bool", "type", "model", "null"])
    func malformed(_ kind: String) throws {
        var body = try #require(JSONSerialization.jsonObject(with: Self.payload()) as? [String: Any])
        var answers = try #require(body["answers"] as? [String: [String: Any]])
        switch kind {
        case "missing": answers.removeValue(forKey: "answer")
        case "extra": answers["unknown"] = ["type": "noul", "noul": 0.0]
        case "negative": answers["answer"]?["noul"] = -0.1
        case "over": answers["answer"]?["noul"] = 1.1
        case "string": answers["answer"]?["noul"] = "0.0"
        case "bool": answers["answer"]?["noul"] = false
        case "type": answers["answer"]?["type"] = "score"
        case "model": body["model"] = "jev-unverified-future"
        default: answers["answer"]?["noul"] = NSNull()
        }
        body["answers"] = answers
        let data = try JSONSerialization.data(withJSONObject: body)
        #expect(throws: TypeSafeReviewError.self) { try TypeSafeReviewClient.assessment(from: data) }
    }

    @Test("API errors do not retry or return unreviewed questions", arguments: [401, 402, 403, 429, 529, 500, 307])
    func apiErrors(_ status: Int) async {
        let client = TypeSafeReviewClient(apiKey: "fixture-only", transport: { request in
            (Data("untrusted server details".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: TypeSafeReviewError.self) {
            try await client.assess(Self.question(), request: GenerationCapabilityTests.request(count: 1))
        }
    }

    @Test("Connection probe validates a synthetic typed decision")
    func probe() async throws {
        let client = TypeSafeReviewClient(apiKey: "fixture-only", transport: { request in
            let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            #expect((body["questions"] as? [String: Any])?.keys.sorted() == ["directions"])
            let data = try Self.payload(probabilities: ["directions": 0.99])
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        try await client.probe()
    }

    @Test("Malformed protocol replies and oversized data cannot approve content", arguments: [false, true])
    func invalidReply(_ oversized: Bool) async {
        let client = TypeSafeReviewClient(apiKey: "fixture-only", transport: { request in
            let data = oversized ? Data(repeating: 32, count: 2_000_001) : Data(#"{"answers":{}}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        await #expect(throws: TypeSafeReviewError.self) {
            try await client.assess(Self.question(), request: GenerationCapabilityTests.request(count: 1))
        }
    }

    @Test("Cancellation propagates instead of switching reviewer")
    func cancellation() async throws {
        let client = TypeSafeReviewClient(apiKey: "fixture-only", transport: { _ in
            try await Task.sleep(for: .seconds(60))
            throw TypeSafeReviewError.unavailable
        })
        let task = Task { try await client.assess(Self.question(), request: GenerationCapabilityTests.request(count: 1)) }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test("Numerical difficulty limits stay in code")
    func difficultyLimits() {
        var request = GenerationCapabilityTests.request(count: 1)
        request.difficulty = .survival
        var question = Self.question()
        question.prompt = Array(repeating: "word", count: 8).joined(separator: " ")
        #expect(TypeSafeReviewClient.fitsDifficulty(question, request: request))
        question.prompt += " extra"
        #expect(!TypeSafeReviewClient.fitsDifficulty(question, request: request))
        request.language = DestinationCatalog().destination(id: "tokyo").languages[0]
        question.prompt = String(repeating: "あ", count: 30)
        #expect(TypeSafeReviewClient.fitsDifficulty(question, request: request))
        question.prompt += "あ"
        #expect(!TypeSafeReviewClient.fitsDifficulty(question, request: request))
    }

    @Test("Clear Jev decisions replace the generative review and retain reviewer provenance")
    func directReview() async throws {
        let fixture = CapabilityProvider(reviewMode: .rejectAll)
        let reviewer = JevReviewFixture()
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture },
            reviewMode: { .typeSafeJev }, fastReviewerFactory: { _ in reviewer })
        let questions = try await service.generate(GenerationCapabilityTests.request(), configuration: ProviderConfiguration())
        #expect(questions.count == 3)
        #expect(await fixture.reviewedCounts.isEmpty)
        #expect(await reviewer.calls == 3)
        #expect(questions.allSatisfy { $0.generation?.review?.provider == "typesafe" && $0.generation?.review?.policyVersion == TypeSafeReviewClient.policyVersion })
    }

    @Test("Only uncertain Jev judgments use the original model's full review")
    func uncertainReview() async throws {
        let fixture = CapabilityProvider()
        let reviewer = JevReviewFixture(.needsReview)
        let configuration = ProviderConfiguration(kind: .openAIChat, model: "fixture-original")
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture },
            reviewMode: { .typeSafeJev }, fastReviewerFactory: { _ in reviewer })
        let questions = try await service.generate(GenerationCapabilityTests.request(count: 1), configuration: configuration)
        #expect(await fixture.reviewedCounts == [1])
        #expect(questions.first?.generation?.review?.model == "fixture-original")
        #expect(questions.first?.generation?.review?.jevModel == TypeSafeReviewClient.model)
    }

    @Test("Jev rejection retains the existing bounded regeneration limit")
    func rejectedReview() async {
        let fixture = CapabilityProvider()
        let reviewer = JevReviewFixture(.reject)
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture },
            reviewMode: { .typeSafeJev }, fastReviewerFactory: { _ in reviewer })
        await #expect(throws: GenerationError.self) {
            try await service.generate(GenerationCapabilityTests.request(count: 1), configuration: ProviderConfiguration())
        }
        #expect(await reviewer.calls == 3)
        #expect(await fixture.requests.count == 3)
        #expect(await fixture.reviewedCounts.isEmpty)
    }

    @Test("Missing Jev credentials stop before generation spends any tokens")
    func missingKey() async {
        let fixture = CapabilityProvider()
        let store = SecureStore(service: "prompti-tests-" + UUID().uuidString)
        let service = QuestionGenerationService(secureStore: store, providerFactory: { _, _ in fixture }, reviewMode: { .typeSafeJev })
        await #expect(throws: TypeSafeReviewError.self) {
            try await service.generate(GenerationCapabilityTests.request(), configuration: ProviderConfiguration())
        }
        #expect(await fixture.requests.isEmpty)
    }

    @Test("Default mode never constructs a Jev reviewer")
    func defaultMode() async throws {
        let fixture = CapabilityProvider()
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture },
            fastReviewerFactory: { _ in throw TypeSafeReviewError.invalidKey })
        _ = try await service.generate(GenerationCapabilityTests.request(count: 1), configuration: ProviderConfiguration())
        #expect(await fixture.reviewedCounts == [1])
    }

    @MainActor
    @Test("Jev failure preserves approved inventory, stops retries and surfaces the actual error")
    func partialFailure() async throws {
        let fixture = CapabilityProvider()
        let reviewer = JevReviewFixture(failAfter: 1)
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture },
            reviewMode: { .typeSafeJev }, fastReviewerFactory: { _ in reviewer })
        let container = ModelContainerFactory.make(inMemory: true)
        let session = PracticeSessionState(records: [], request: GenerationCapabilityTests.request(count: 3), configuration: ProviderConfiguration(kind: .apple))
        session.fill(using: service, context: container.mainContext)
        for _ in 0..<100 where session.isFilling { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!session.isFilling)
        #expect(session.records.count == 1)
        #expect(session.fillError is TypeSafeReviewError)
        #expect(await fixture.requests.count == 2)
        #expect(await fixture.reviewedCounts.isEmpty)
        session.fillIfNeeded(using: service, context: container.mainContext)
        #expect(!session.isFilling)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 1)
    }

    @MainActor
    @Test("Review preference persists independently, defaults off and never contains the key")
    func settings() throws {
        let name = "prompti-review-settings-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        #expect(settings.questionReviewMode == .generationModel)
        settings.questionReviewMode = .typeSafeJev
        #expect(AppSettings(defaults: defaults).questionReviewMode == .typeSafeJev)
        defaults.set("future-mode", forKey: "generation.questionReview")
        #expect(AppSettings(defaults: defaults).questionReviewMode == .generationModel)
    }

    @Test("Jev and generation keys have isolated scopes in the existing Keychain manager")
    func credentialScopes() throws {
        let store = SecureStore(service: "prompti-review-key-tests-" + UUID().uuidString)
        let configuration = ProviderConfiguration(kind: .openAIChat, baseURL: "https://api.typesafe.ai/v1/systemone")
        defer { store.deleteAPIKey(for: configuration); store.deleteReviewKey() }
        try store.saveAPIKey("fixture-generation", for: configuration)
        try store.saveReviewKey("fixture-review")
        #expect(store.readAPIKey(for: configuration) == "fixture-generation")
        #expect(store.readReviewKey() == "fixture-review")
        store.deleteReviewKey()
        #expect(store.readReviewKey() == nil && store.readAPIKey(for: configuration) == "fixture-generation")
    }

    @MainActor
    @Test("Jev usage is attributed to review and includes actual returned token counts")
    func usage() async throws {
        let name = "prompti-review-usage-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let ledger = UsageLedger(defaults: defaults)
        let jobID = UUID()
        let client = TypeSafeReviewClient(apiKey: "fixture-only", transport: { request in
            (try Self.payload(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, usageSink: { await ledger.record($0) }, jobID: jobID)
        _ = try await client.assess(Self.question(), request: GenerationCapabilityTests.request(count: 1))
        let entry = try #require(ledger.entries.first)
        #expect(ledger.entries.count == 1 && entry.provider == "typesafe" && entry.jobID == jobID)
        #expect(entry.operationTitle == "Question review" && entry.inputTokens == 123 && entry.outputTokens == 42)
        #expect(!String(decoding: try JSONEncoder().encode(ledger.entries), as: UTF8.self).contains("fixture-only"))
    }

    @Test("Old question provenance decodes without reviewer metadata")
    func metadataMigration() throws {
        let metadata = GenerationMetadata(jobID: UUID(), batchID: UUID(), provider: "fixture", model: "fixture", createdAt: .now, sourceFactIDs: [], checks: QuestionReview.checks)
        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(GenerationMetadata.self, from: data)
        #expect(decoded.review == nil)
    }
}
