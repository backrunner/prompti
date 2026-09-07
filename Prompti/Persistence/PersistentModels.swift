import Foundation
import SwiftData

typealias QuestionRecord = PromptiSchemaV2.QuestionRecord
typealias AttemptRecord = PromptiSchemaV2.AttemptRecord
typealias UserSceneRecord = PromptiSchemaV2.UserSceneRecord

enum PromptiSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
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
        var explanationLanguageCode: String = ""
        var clozeData: Data?
        var rubricData: Data?
        var generationData: Data?
        var contentHash: String = ""
        var isArchived: Bool = false

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
            explanationLanguageCode = request.explanationLanguage.rawValue
            clozeData = question.cloze.flatMap { try? JSONEncoder().encode($0) }
            rubricData = question.rubric.flatMap { try? JSONEncoder().encode($0) }
            generationData = question.generation.flatMap { try? JSONEncoder().encode($0) }
            contentHash = question.contentSignature
        }

        var question: GeneratedQuestion {
            let metadata = generationData.flatMap { try? JSONDecoder().decode(GenerationMetadata.self, from: $0) }
            return GeneratedQuestion(
                id: id,
                kind: QuestionKind(rawValue: kindRaw) ?? .multipleChoice,
                prompt: prompt,
                options: (try? JSONDecoder().decode([QuestionOption].self, from: optionsData)) ?? [],
                correctAnswer: correctAnswer,
                translation: translation,
                explanation: explanationText,
                sampleAnswer: sampleAnswer,
                sceneID: sceneID,
                cloze: clozeData.flatMap { try? JSONDecoder().decode(ClozeContent.self, from: $0) },
                rubric: rubricData.flatMap { try? JSONDecoder().decode(SpeechRubric.self, from: $0) },
                generation: metadata,
                sourceFactIDs: metadata?.sourceFactIDs
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
        var questionSnapshot: Data?
        var sessionID: UUID?
        var speechConfidence: Float?
        var feedback: String = ""
        var timeZoneIdentifier: String = ""

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
            timeZoneIdentifier = TimeZone.current.identifier
            questionSnapshot = try? JSONEncoder().encode(question.question)
        }

        var result: AttemptResult {
            AttemptResult(rawValue: resultRaw) ?? .skipped
        }

        static func scored(in attempts: [AttemptRecord]) -> [AttemptRecord] {
            let attempts = unique(in: attempts)
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

// CloudKit cannot enforce UUID uniqueness; imported copies may arrive from another device.
extension QuestionRecord {
    static func canonical(in records: [QuestionRecord]) -> [QuestionRecord] {
        let groups = Dictionary(grouping: records, by: \.id)
        var seen = Set<UUID>()
        return records.compactMap { record in
            guard seen.insert(record.id).inserted else { return nil }
            let copies = groups[record.id] ?? [record]
            return copies.first(where: \.isQuarantined) ?? copies.first(where: \.isArchived) ?? record
        }
    }
}

extension AttemptRecord {
    static func unique(in attempts: [AttemptRecord]) -> [AttemptRecord] {
        var seen = Set<UUID>()
        return attempts.filter { seen.insert($0.id).inserted }
    }
}
