import Foundation
import SwiftData

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
            sampleAnswer: sampleAnswer
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
        localDayKey = Date.now.formatted(.iso8601.year().month().day())
    }

    var result: AttemptResult {
        AttemptResult(rawValue: resultRaw) ?? .skipped
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
