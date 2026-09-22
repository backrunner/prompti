import Foundation
import SwiftData
import Testing
@testable import Prompti

@MainActor
@Suite("Review record deletion")
struct ReviewRecordDeletionTests {
    @Test("Deleting one row removes all UUID copies and attempts, preserving other history and unused inventory")
    func deleteOneQuestion() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let removed = makeQuestion("Remove me")
        let duplicate = makeQuestion("Remove me", id: removed.id)
        let retained = makeQuestion("Keep my score")
        let unused = makeQuestion("Still available")
        for question in [removed, duplicate, retained, unused] { context.insert(question) }
        let wrong = AttemptRecord(question: removed, result: .incorrect, submittedAnswer: "No")
        let copy = AttemptRecord(question: duplicate, result: .incorrect, submittedAnswer: "No")
        copy.id = wrong.id
        let skipped = AttemptRecord(question: removed, result: .skipped, submittedAnswer: "")
        let correct = AttemptRecord(question: retained, result: .correct, submittedAnswer: "Yes")
        for attempt in [wrong, copy, skipped, correct] { context.insert(attempt) }
        try context.save()

        try ReviewRecordDeletion.delete(questionIDs: [removed.id], context: context)
        let remaining = try context.fetch(FetchDescriptor<AttemptRecord>())
        #expect(remaining.map(\.id) == [correct.id])
        #expect(AttemptRecord.scored(in: remaining).map(\.result) == [.correct])
        #expect(removed.isArchived && duplicate.isArchived)
        #expect(!retained.isArchived && !unused.isArchived)
        let available = QuestionInventory.available(
            [removed, duplicate, retained, unused], attempts: remaining, destinationID: "tokyo",
            languageCode: unused.languageCode, explanationLanguage: .english, difficulty: .basic
        )
        #expect(available.map(\.id) == [unused.id])
    }

    @Test("Bulk deletion only affects the confirmed IDs, tolerates retries and protects reports arriving before confirmation")
    func scopedBulkDeletion() throws {
        let container = ModelContainerFactory.make(inMemory: true)
        let context = container.mainContext
        let first = makeQuestion("First")
        let second = makeQuestion("Second")
        let outsideFilter = makeQuestion("Outside filter")
        let reported = makeQuestion("Reported after confirmation opened")
        let quarantined = makeQuestion("Quarantined copy")
        quarantined.isQuarantined = true
        for question in [first, second, outsideFilter, reported, quarantined] {
            context.insert(question)
            context.insert(AttemptRecord(question: question, result: .incorrect, submittedAnswer: "No"))
        }
        context.insert(AttemptRecord(question: reported, result: .reported, submittedAnswer: "", reason: "unsafe"))
        try context.save()

        let selectedIDs: Set<UUID> = [first.id, second.id, reported.id, quarantined.id]
        try ReviewRecordDeletion.delete(questionIDs: selectedIDs, context: context)
        try ReviewRecordDeletion.delete(questionIDs: selectedIDs, context: context)
        try ReviewRecordDeletion.delete(questionIDs: [], context: context)
        let remaining = try context.fetch(FetchDescriptor<AttemptRecord>())
        #expect(remaining.count == 4)
        #expect(Set(remaining.map(\.questionID)) == [outsideFilter.id, reported.id, quarantined.id])
        #expect(first.isArchived && second.isArchived)
        #expect(!outsideFilter.isArchived && !reported.isArchived && !quarantined.isArchived)
        #expect(remaining.contains { $0.result == .reported })
    }

    @Test("Clearing history persists after reopening the disk store and leaves no scores")
    func deletionSurvivesReopen() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: "learning.store")
        let deletedID: UUID = try autoreleasepool {
            let container = try ModelContainerFactory.open(url: url, cloud: false).container
            let question = makeQuestion("Saved then cleared")
            container.mainContext.insert(question)
            container.mainContext.insert(AttemptRecord(question: question, result: .incorrect, submittedAnswer: "No"))
            try container.mainContext.save()
            try ReviewRecordDeletion.delete(questionIDs: [question.id], context: container.mainContext)
            return question.id
        }
        let reopened = try ModelContainerFactory.open(url: url, cloud: false).container
        let attempts = try reopened.mainContext.fetch(FetchDescriptor<AttemptRecord>())
        #expect(attempts.isEmpty)
        #expect(AttemptRecord.scored(in: attempts).isEmpty)
        let question = try #require(reopened.mainContext.fetch(FetchDescriptor<QuestionRecord>()).first)
        #expect(question.id == deletedID && question.isArchived)
    }

    private func makeQuestion(_ prompt: String, id: UUID = UUID()) -> QuestionRecord {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: "tokyo")
        let request = TrainingRequest(destination: destination, language: destination.languages[0], explanationLanguage: .english,
                                      scenes: [catalog.commonScenes[0]], difficulty: .basic, kinds: [.multipleChoice], count: 1)
        let question = GeneratedQuestion(id: id, kind: .multipleChoice, prompt: prompt,
                                        options: ["Yes", "No"].map { QuestionOption(text: $0) }, correctAnswer: "Yes",
                                        translation: "Translation", explanation: "Explanation")
        return QuestionRecord(question: question, request: request, scene: request.scenes[0])
    }
}
