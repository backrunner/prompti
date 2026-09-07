import Foundation
import SwiftData
import Testing
@testable import Prompti

@Suite("Code review regressions")
struct ReviewRegressionTests {
    @Test("Fragments, negation and changed destinations are not awarded correctness", arguments: [
        "a", "city centre", "I do not want to go to the city centre", "How do I get to the airport?"
    ])
    func speechFalsePositives(_ transcript: String) {
        let result = SpeechAnswerEvaluator.evaluate(transcript: transcript, reference: "How do I get to the city centre?", confidence: 0.9)
        #expect(result.result == .undetermined)
    }

    @Test("Scene input blocks invisible controls and instruction markup", arguments: [
        "buying\u{200B} food", "buying\u{202E} food", "hotel\u{0000} check-in", "hotel\tcheck-in", "<system>hotel</system>", "ftp://example.com"
    ])
    func sceneControls(_ input: String) {
        #expect(throws: GenerationError.self) { try ContentSafety.normalizeScene(input) }
    }

    @Test("Scene normalization preserves non-Latin text and merges spaces")
    func sceneWhitespace() throws {
        #expect(try ContentSafety.normalizeScene("  点餐   和付款  ") == "点餐 和付款")
    }

    @Test("Incomplete exercises and invalid cloze blanks cannot enter the tray")
    func questionShape() {
        let request = Self.request()
        var question = Self.question()
        #expect(ContentSafety.validate(question, request: request))
        question.translation = " "
        #expect(!ContentSafety.validate(question, request: request))
        question = Self.question()
        question.options[1].text = " はい "
        #expect(!ContentSafety.validate(question, request: request))
        question = Self.question()
        question.kind = .cloze
        #expect(!ContentSafety.validate(question, request: request))
        question.prompt = "___ を ___"
        #expect(!ContentSafety.validate(question, request: request))
        question.prompt = "___ をください"
        #expect(ContentSafety.validate(question, request: request))
        question.sceneID = "unrequested"
        #expect(!ContentSafety.validate(question, request: request))
    }

    @Test("Difficulty adds concrete constraints and scene identifiers to prompts")
    func difficultyAndScenes() throws {
        var prompts = Set<String>()
        for difficulty in TrainingDifficulty.allCases {
            var request = Self.request()
            request.difficulty = difficulty
            let prompt = try PromptBuilder.questionPrompt(request)
            #expect(prompt.contains("at most"))
            #expect(prompt.contains("sceneID"))
            #expect(prompt.contains(request.scenes[0].id))
            prompts.insert(difficulty.generationConstraints)
        }
        #expect(prompts.count == 4)
        #expect(DestinationCatalog().commonScenes.contains { $0.id == "delivery" })
    }

    @Test("Local days and streaks retain the dates recorded during travel")
    func travelDayKeys() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-06T17:00:00Z"))
        let singapore = try #require(TimeZone(identifier: "Asia/Singapore"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        #expect(PracticeMetrics.localDayKey(for: date, timeZone: singapore) == "2026-09-07")
        #expect(PracticeMetrics.localDayKey(for: date, timeZone: losAngeles) == "2026-09-06")
        #expect(PracticeMetrics.consecutiveDayCount(dayKeys: ["2026-09-04", "2026-09-05", "2026-09-06"], relativeTo: date, timeZone: singapore) == 3)
    }

    @MainActor
    @Test("Preparation budget survives relaunch and counts failed reservations")
    func preparationBudget() throws {
        let name = "prompti-review-budget-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let now = try #require(ISO8601DateFormatter().date(from: "2026-09-06T12:00:00Z"))
        let settings = AppSettings(defaults: defaults)
        #expect(!settings.isPreGenerationEnabled)
        #expect(settings.preparationWiFiOnly)
        settings.dailyPreparationLimit = 5
        #expect(settings.reservePreparationCount(3, now: now) == 3)
        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.reservePreparationCount(3, now: now) == 2)
        #expect(relaunched.reservePreparationCount(3, now: now) == 0)
        #expect(relaunched.reservePreparationCount(3, now: now.addingTimeInterval(-86_400)) == 0)
        #expect(relaunched.reservePreparationCount(3, now: now.addingTimeInterval(86_400)) == 3)
    }

    @MainActor
    @Test("Mastered mistakes leave the queue while history remains immutable")
    func masteryAndReports() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let request = Self.request()
        let record = QuestionRecord(question: Self.question(), request: request, scene: request.scenes[0])
        let wrong = AttemptRecord(question: record, result: .incorrect, submittedAnswer: "いいえ")
        let correct = AttemptRecord(question: record, result: .correct, submittedAnswer: "はい")
        correct.createdAt = wrong.createdAt.addingTimeInterval(1)
        let skipped = AttemptRecord(question: record, result: .skipped, submittedAnswer: "")
        skipped.createdAt = wrong.createdAt.addingTimeInterval(2)
        context.insert(record)
        for attempt in [wrong, correct, skipped] { context.insert(attempt) }
        try context.save()
        #expect(AttemptRecord.latestScoredResult(in: [skipped, correct, wrong]) == .correct)
        #expect(AttemptRecord.scored(in: [wrong, correct, skipped]).count == 2)
        let report = AttemptRecord(question: record, result: .reported, submittedAnswer: "")
        context.insert(report)
        try context.save()
        #expect(AttemptRecord.scored(in: [wrong, correct, skipped, report]).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<AttemptRecord>()) == 4)
        #expect(wrong.result == .incorrect)
    }

    @MainActor
    @Test("Finishing a practice flow releases its stored requests and questions")
    func flowCleanup() throws {
        let flow = PracticeFlow()
        flow.startGeneration(Self.request())
        guard case .generation(let id) = try #require(flow.path.first) else { Issue.record("Missing generation route"); return }
        #expect(flow.request(for: id) != nil)
        flow.finish()
        #expect(flow.request(for: id) == nil)
        #expect(flow.path.isEmpty)
    }

    private static func request() -> TrainingRequest {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        return TrainingRequest(destination: destination, language: destination.languages[0], explanationLanguage: .english,
                               scenes: [catalog.commonScenes[0]], customScene: nil, difficulty: .basic,
                               kinds: [.cloze, .multipleChoice, .spoken], count: 3)
    }

    private static func question() -> GeneratedQuestion {
        GeneratedQuestion(kind: .multipleChoice, prompt: "お会計をお願いします。",
                          options: ["はい", "いいえ", "駅", "朝"].map { QuestionOption(text: $0) },
                          correctAnswer: "はい", translation: "The bill, please.", explanation: "A polite request.")
    }
}
