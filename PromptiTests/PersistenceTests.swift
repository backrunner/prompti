import SwiftData
import Testing
@testable import Prompti

@MainActor
@Suite("Prompti persistence")
struct PersistenceTests {
    @Test("In-memory store saves attempts explicitly")
    func savesAttempt() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        let request = TrainingRequest(
            destination: destination,
            language: destination.languages[0],
            explanationLanguage: .english,
            scenes: [catalog.commonScenes[0]],
            customScene: nil,
            difficulty: .basic,
            kinds: [.multipleChoice],
            count: 1
        )
        let question = GeneratedQuestion(
            kind: .multipleChoice,
            prompt: "お会計をお願いします。",
            options: ["はい", "いいえ", "駅", "朝"].map { QuestionOption(text: $0) },
            correctAnswer: "はい",
            translation: "The bill, please.",
            explanation: "A dining phrase."
        )
        let record = QuestionRecord(question: question, request: request, scene: request.scenes[0])
        context.insert(record)
        context.insert(AttemptRecord(question: record, result: .correct, submittedAnswer: "はい"))
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<QuestionRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AttemptRecord>()) == 1)
    }
}
