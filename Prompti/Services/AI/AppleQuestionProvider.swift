import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable(description: "A batch of safe, practical tourist language exercises")
private struct AppleQuestionBatch {
    @Guide(description: "The requested exercises")
    var questions: [AppleQuestion]
}

@available(iOS 26.0, *)
@Generable(description: "One tourist language exercise")
private struct AppleQuestion {
    @Guide(description: "One of: cloze, multipleChoice, spoken")
    var type: String
    var prompt: String
    var options: [String]
    var correctAnswer: String
    var translation: String
    var explanation: String
    var sampleAnswer: String
}

@available(iOS 26.0, *)
@Generable(description: "A content safety decision")
private struct AppleReview {
    var allowed: Bool
    var normalized: String
    var reason: String
}

enum AppleModelCapability {
    static func status(for languageCode: String) -> AppleModelStatus {
        guard #available(iOS 26.0, *) else { return .hidden }
        let model = SystemLanguageModel.default
        guard model.supportsLocale(Locale(identifier: languageCode)) else { return .unsupportedLanguage }
        switch model.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .hidden
        case .unavailable(.modelNotReady), .unavailable(.appleIntelligenceNotEnabled): return .notReady
        case .unavailable: return .unavailable
        }
    }
}

@available(iOS 26.0, *)
struct AppleQuestionProvider {
    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        let model = SystemLanguageModel.default
        guard model.availability == .available,
              model.supportsLocale(Locale(identifier: request.language.code)) else {
            throw GenerationError.modelUnavailable
        }
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.systemInstructions)
        let response = try await session.respond(
            to: PromptBuilder.questionPrompt(request),
            generating: AppleQuestionBatch.self
        )
        return response.content.questions.compactMap { item in
            guard let kind = QuestionKind(rawValue: item.type) else { return nil }
            return GeneratedQuestion(
                kind: kind,
                prompt: item.prompt,
                options: item.options.map { QuestionOption(text: $0) },
                correctAnswer: item.correctAnswer,
                translation: item.translation,
                explanation: item.explanation,
                sampleAnswer: item.sampleAnswer.isEmpty ? nil : item.sampleAnswer
            )
        }
    }

    func reviewScene(_ scene: String) async throws -> SceneReview {
        let session = LanguageModelSession(instructions: PromptBuilder.systemInstructions)
        let response = try await session.respond(
            to: PromptBuilder.sceneReviewPrompt(scene),
            generating: AppleReview.self
        )
        return SceneReview(
            isAllowed: response.content.allowed,
            normalized: response.content.normalized,
            reason: response.content.reason
        )
    }

    func reviewQuestions(_ questions: [GeneratedQuestion]) async throws -> Bool {
        let session = LanguageModelSession(instructions: PromptBuilder.systemInstructions)
        let response = try await session.respond(
            to: PromptBuilder.batchReviewPrompt(questions),
            generating: AppleReview.self
        )
        return response.content.allowed
    }
}
