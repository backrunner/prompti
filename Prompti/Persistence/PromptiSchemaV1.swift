import Foundation
import SwiftData

// Frozen storage layout shipped before structured exercises and provenance.
enum PromptiSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [QuestionRecord.self, AttemptRecord.self, UserSceneRecord.self] }
    @Model
    final class QuestionRecord {
        var id: UUID = UUID()
        var kindRaw: String = QuestionKind.multipleChoice.rawValue
        var destinationID: String = ""
        var destinationName: String = ""
        var languageCode: String = "en"
        var sceneID: String = ""
        var sceneTitle: String = ""
        var difficultyRaw: String = TrainingDifficulty.basic.rawValue
        var prompt: String = ""
        var optionsData: Data = Data()
        var correctAnswer: String = ""
        var translation: String = ""
        var explanationText: String = ""
        var sampleAnswer: String?
        var isQuarantined: Bool = false
        var createdAt: Date = Date()

        init(question: GeneratedQuestion, request: TrainingRequest, scene: TravelScene) {
            id = question.id
            kindRaw = question.kind.rawValue
            destinationID = request.destination.id
            destinationName = request.destination.city
            languageCode = request.language.code
            sceneID = scene.id
            sceneTitle = scene.title
            difficultyRaw = request.difficulty.rawValue
            prompt = question.prompt
            optionsData = (try? JSONEncoder().encode(question.options)) ?? Data()
            correctAnswer = question.correctAnswer
            translation = question.translation
            explanationText = question.explanation
            sampleAnswer = question.sampleAnswer
        }

        var question: GeneratedQuestion {
            GeneratedQuestion(
                id: id,
                kind: QuestionKind(rawValue: kindRaw) ?? .multipleChoice,
                prompt: prompt,
                options: (try? JSONDecoder().decode([QuestionOption].self, from: optionsData)) ?? [],
                correctAnswer: correctAnswer,
                translation: translation,
                explanation: explanationText,
                sampleAnswer: sampleAnswer,
                sceneID: sceneID
            )
        }
    }

    @Model
    final class AttemptRecord {
        var id: UUID = UUID()
        var questionID: UUID = UUID()
        var destinationID: String = ""
        var languageCode: String = "en"
        var sceneTitle: String = ""
        var resultRaw: String = AttemptResult.skipped.rawValue
        var submittedAnswer: String = ""
        var reasonRaw: String = ""
        var createdAt: Date = Date()
        var localDayKey: String = ""

        init(question: QuestionRecord, result: AttemptResult, submittedAnswer: String, reason: String = "") {
            id = UUID()
            questionID = question.id
            destinationID = question.destinationID
            languageCode = question.languageCode
            sceneTitle = question.sceneTitle
            resultRaw = result.rawValue
            self.submittedAnswer = submittedAnswer
            reasonRaw = reason
            createdAt = Date()
            localDayKey = PracticeMetrics.localDayKey(for: createdAt)
        }

        var result: AttemptResult {
            AttemptResult(rawValue: resultRaw) ?? .skipped
        }

        static func scored(in attempts: [AttemptRecord]) -> [AttemptRecord] {
            let reported = Set(attempts.filter { $0.result == .reported }.map(\.questionID))
            return attempts.filter { !reported.contains($0.questionID) && ($0.result == .correct || $0.result == .incorrect) }
        }

        static func latestScoredResult(in attempts: [AttemptRecord]) -> AttemptResult? {
            scored(in: attempts).max {
                if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
                return $0.createdAt < $1.createdAt
            }?.result
        }
    }

    @Model
    final class UserSceneRecord {
        var id: UUID = UUID()
        var destinationID: String = ""
        var title: String = ""
        var isApproved: Bool = false
        var createdAt: Date = Date()

        init(destinationID: String, title: String, isApproved: Bool) {
            id = UUID()
            self.destinationID = destinationID
            self.title = title
            self.isApproved = isApproved
            createdAt = Date()
        }
    }
}
