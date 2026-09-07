import Foundation
import SwiftData
import Testing
@testable import Prompti

private actor UsageTransport {
    var count = 0
    let payload: Data
    init(payload: Data) { self.payload = payload }
    func send(_ request: URLRequest) -> (Data, HTTPURLResponse) {
        count += 1
        return (count == 1 ? Data() : payload, HTTPURLResponse(url: request.url!, statusCode: count == 1 ? 400 : 200, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
@Suite("Model usage and growing sessions")
struct UsageAndSessionTests {
    @Test("Actual fallback attempts each have one ledger entry; missing tokens stay unknown")
    func usageFallback() async throws {
        let suite = "prompti-usage-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ledger = UsageLedger(defaults: defaults)
        let payload = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": #"{"allowed":true,"normalized":"hotel","reason":"travel"}"#]]],
            "usage": ["prompt_tokens": 321, "completion_tokens": 27]
        ])
        let fixture = UsageTransport(payload: payload)
        let client = RemoteAIClient(configuration: ProviderConfiguration(kind: .openAIChat), apiKey: "fixture-secret",
            transport: { await fixture.send($0) }, usageSink: { await ledger.record($0) })
        _ = try await client.probe()
        #expect(ledger.entries.count == 2)
        #expect(ledger.unknownUsageCount == 1)
        #expect(ledger.reportedInputTokens == 321)
        #expect(ledger.reportedOutputTokens == 27)
        #expect(ledger.entries.first?.status == "failed")
        #expect(ledger.entries.last?.operation.hasSuffix(".fallback") == true)
        let persisted = UsageLedger(defaults: defaults)
        #expect(persisted.entries.count == 2)
        #expect(!String(decoding: try JSONEncoder().encode(persisted.entries), as: UTF8.self).contains("fixture-secret"))
    }

    @Test("Responses and Anthropic token fields are parsed without inventing missing values")
    func tokenFields() throws {
        var entry = ModelUsage(provider: "fixture", model: "fixture", operation: "test")
        entry.complete(data: Data(#"{"usage":{"input_tokens":19,"output_tokens":4}}"#.utf8), statusCode: 200)
        #expect(entry.inputTokens == 19 && entry.outputTokens == 4)
        entry.complete(data: Data(#"{"usage":{"input_tokens":true,"output_tokens":-4}}"#.utf8), statusCode: 200)
        #expect(entry.inputTokens == nil && entry.outputTokens == nil)
        entry.complete(data: Data(#"{"usage":{"input_tokens":2.5}}"#.utf8), statusCode: 200)
        #expect(entry.inputTokens == nil && entry.outputTokens == nil)
    }

    @Test("Approved batches append without replacing the active question; cancellation saves no late output")
    func fillingAndCancellation() async throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let request = GenerationCapabilityTests.request(count: 7)
        let fixture = CapabilityProvider(delay: .milliseconds(50))
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture })
        var firstRequest = request
        firstRequest.count = 1
        let first = try await service.generate(firstRequest, configuration: ProviderConfiguration())
        let saved = try QuestionInventory.save(first, request: firstRequest, context: container.mainContext)
        let state = PracticeSessionState(records: saved, request: request, configuration: ProviderConfiguration())
        state.fill(using: service, context: container.mainContext)
        try await waitUntil { !state.isFilling }
        #expect(state.records.count == 7)
        #expect(state.records[0].id == saved[0].id)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 7)

        let other = ModelContainerFactory.make(inMemory: true)
        let slow = CapabilityProvider(delay: .seconds(10))
        let slowService = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in slow })
        let cancelled = PracticeSessionState(records: [], request: request, configuration: ProviderConfiguration())
        cancelled.fill(using: slowService, context: other.mainContext)
        try await Task.sleep(for: .milliseconds(30))
        cancelled.cancelFill()
        try await Task.sleep(for: .milliseconds(50))
        #expect(!cancelled.isFilling && cancelled.records.isEmpty)
        #expect(try other.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 0)
    }

    @Test("Fill errors retain approved questions and leave a retryable remainder")
    func fillFailure() async throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let fixture = CapabilityProvider(failsAfter: 1)
        let service = QuestionGenerationService(secureStore: SecureStore(), providerFactory: { _, _ in fixture })
        let request = GenerationCapabilityTests.request(count: 5)
        let state = PracticeSessionState(records: [], request: request, configuration: ProviderConfiguration())
        state.fill(using: service, context: container.mainContext)
        try await waitUntil { !state.isFilling }
        #expect(state.records.count == 3 && state.hasRemaining)
        #expect(state.fillError != nil)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<QuestionRecord>()) == 3)
    }

    @Test("Inventory respects explanation locale, deduplicates and clears only unused questions")
    func inventory() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let request = GenerationCapabilityTests.request(count: 1)
        let question = GeneratedQuestion(kind: .multipleChoice, prompt: "Where is the station?", options: ["There", "No", "Yes"].map { QuestionOption(text: $0) }, correctAnswer: "There", translation: "Station", explanation: "Directions", sceneID: request.scenes[0].id)
        let first = try #require(QuestionInventory.save([question], request: request, context: container.mainContext).first)
        var duplicate = question
        duplicate.id = UUID()
        #expect(try QuestionInventory.save([duplicate], request: request, context: container.mainContext).isEmpty)
        var chinese = request
        chinese.explanationLanguage = .simplifiedChinese
        let second = try #require(QuestionInventory.save([duplicate], request: chinese, context: container.mainContext).first)
        let questions = try container.mainContext.fetch(FetchDescriptor<QuestionRecord>())
        let available = QuestionInventory.available(questions, attempts: [], destinationID: request.destination.id,
            languageCode: request.language.code, explanationLanguage: .english, difficulty: .basic)
        #expect(available.map(\.id) == [first.id])
        let attempt = AttemptRecord(question: first, result: .correct, submittedAnswer: "There")
        container.mainContext.insert(attempt)
        try container.mainContext.save()
        try QuestionInventory.clearUnused(context: container.mainContext)
        #expect(!first.isArchived && second.isArchived)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<AttemptRecord>()) == 1)
        #expect(attempt.questionSnapshot != nil && !attempt.timeZoneIdentifier.isEmpty)
    }

    @Test("A request deadline cancels slow provider work")
    func deadline() async {
        await #expect(throws: GenerationError.self) {
            try await ProviderDeadline.run(until: .now.advanced(by: .milliseconds(20))) {
                try await Task.sleep(for: .seconds(10))
                return true
            }
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}
