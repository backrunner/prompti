import Foundation
import SwiftData

@MainActor
enum LearningDataImport {
    // Stable event IDs make repeated imports safe. Quarantine/archive wins over older copies.
    static func merge(from source: ModelContext, into target: ModelContext) throws -> Int {
        var questions = Dictionary((try target.fetch(FetchDescriptor<QuestionRecord>())).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var attemptIDs = Set(try target.fetch(FetchDescriptor<AttemptRecord>()).map(\.id))
        var sceneIDs = Set(try target.fetch(FetchDescriptor<UserSceneRecord>()).map(\.id))
        var inserted = 0
        do {
            for old in try source.fetch(FetchDescriptor<QuestionRecord>()) {
                if let existing = questions[old.id] {
                    existing.isQuarantined = existing.isQuarantined || old.isQuarantined
                    existing.isArchived = existing.isArchived || old.isArchived
                    continue
                }
                let record = QuestionRecord(question: old.question, request: request(for: old), scene: scene(for: old))
                record.destinationName = old.destinationName
                record.explanationLanguageCode = old.explanationLanguageCode
                record.createdAt = old.createdAt
                record.isQuarantined = old.isQuarantined
                record.isArchived = old.isArchived
                target.insert(record)
                questions[record.id] = record
                inserted += 1
            }
            for old in try source.fetch(FetchDescriptor<AttemptRecord>()) where attemptIDs.insert(old.id).inserted {
                // Preserve orphaned attempts too: legacy history may outlive its question.
                let reference = questions[old.questionID] ?? placeholder(for: old)
                let record = AttemptRecord(question: reference, result: old.result, submittedAnswer: old.submittedAnswer, reason: old.reasonRaw)
                record.id = old.id
                record.questionID = old.questionID
                record.destinationID = old.destinationID
                record.languageCode = old.languageCode
                record.sceneTitle = old.sceneTitle
                record.resultRaw = old.resultRaw
                record.createdAt = old.createdAt
                record.localDayKey = old.localDayKey
                record.questionSnapshot = old.questionSnapshot
                record.sessionID = old.sessionID
                record.speechConfidence = old.speechConfidence
                record.feedback = old.feedback
                record.timeZoneIdentifier = old.timeZoneIdentifier
                target.insert(record)
                inserted += 1
            }
            for old in try source.fetch(FetchDescriptor<UserSceneRecord>()) where sceneIDs.insert(old.id).inserted {
                let record = UserSceneRecord(destinationID: old.destinationID, title: old.title, isApproved: old.isApproved)
                record.id = old.id
                record.createdAt = old.createdAt
                target.insert(record)
                inserted += 1
            }
            try target.save()
            return inserted
        } catch {
            target.rollback()
            throw error
        }
    }

    private static func scene(for record: QuestionRecord) -> TravelScene {
        TravelScene(id: record.sceneID, title: record.sceneTitle, symbol: "suitcase", context: record.sceneTitle)
    }

    private static func request(for record: QuestionRecord) -> TrainingRequest {
        var destination = DestinationCatalog().destination(id: record.destinationID)
        destination.id = record.destinationID
        destination.city = record.destinationName
        var language = destination.languages[0]
        language.code = record.languageCode
        return TrainingRequest(destination: destination, language: language,
            explanationLanguage: ExplanationLanguage(rawValue: record.explanationLanguageCode) ?? .english,
            scenes: [scene(for: record)], difficulty: TrainingDifficulty(rawValue: record.difficultyRaw) ?? .basic,
            kinds: [record.question.kind], count: 1)
    }

    private static func placeholder(for attempt: AttemptRecord) -> QuestionRecord {
        let catalog = DestinationCatalog()
        let destination = catalog.destination(id: attempt.destinationID)
        let request = TrainingRequest(destination: destination, language: destination.languages[0], explanationLanguage: .english,
                                      scenes: [catalog.commonScenes[0]], difficulty: .basic, kinds: [.spoken], count: 1)
        return QuestionRecord(question: GeneratedQuestion(id: attempt.questionID, kind: .spoken, prompt: "", options: [], correctAnswer: "", translation: "", explanation: ""), request: request, scene: request.scenes[0])
    }
}
