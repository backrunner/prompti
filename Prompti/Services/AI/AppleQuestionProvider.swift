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
    var sceneID: String
    var cloze: AppleCloze?
    var rubric: AppleRubric?
    var sourceFactIDs: [String]
}

@available(iOS 26.0, *)
@Generable(description: "A content safety decision")
private struct AppleReview {
    var allowed: Bool
    var normalized: String
    var reason: String
}

@available(iOS 26.0, *)
@Generable
private struct AppleCloze {
    var segments: [String]
    var blanks: [AppleBlank]
}

@available(iOS 26.0, *)
@Generable
private struct AppleBlank {
    var id: String
    var options: [String]
    var correctAnswer: String
}

@available(iOS 26.0, *)
@Generable
private struct AppleRubric {
    var intent: String
    var requiredDetails: [String]
    var acceptableVariations: [String]
}

@available(iOS 26.0, *)
@Generable
private struct AppleQualityDecision {
    var questionID: String
    var safe: Bool
    var language: Bool
    var scene: Bool
    var natural: Bool
    var answer: Bool
    var difficulty: Bool
    var reason: String
}

@available(iOS 26.0, *)
@Generable
private struct AppleQualityReview { var decisions: [AppleQualityDecision] }

@available(iOS 26.0, *)
@Generable
private struct AppleSemanticVerdict {
    @Guide(description: "One of correct, incorrect, undetermined")
    var result: String
    var feedback: String
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
struct AppleQuestionProvider: QuestionProvider {
    var usageSink: UsageSink? = nil
    var jobID: UUID? = nil

    private func measured<T: Sendable>(_ operation: String, work: () async throws -> T) async throws -> T {
        var usage = ModelUsage(jobID: jobID, provider: ProviderKind.apple.rawValue, model: "system", operation: operation)
        await usageSink?(usage)
        do {
            let value = try await work()
            usage.status = "received"
            await usageSink?(usage)
            return value
        } catch {
            usage.status = Task.isCancelled ? "cancelled" : "failed"
            await usageSink?(usage)
            throw error
        }
    }

    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion] {
        let model = SystemLanguageModel.default
        guard model.availability == .available,
              model.supportsLocale(Locale(identifier: request.language.code)),
              model.supportsLocale(Locale(identifier: request.explanationLanguage.rawValue)) else {
            throw GenerationError.modelUnavailable
        }
        let session = LanguageModelSession(model: model, instructions: PromptBuilder.systemInstructions)
        let response = try await measured("generation") {
            try await session.respond(to: PromptBuilder.questionPrompt(request), generating: AppleQuestionBatch.self).content
        }
        return response.questions.compactMap { item in
            guard let kind = QuestionKind(rawValue: item.type) else { return nil }
            return GeneratedQuestion(
                kind: kind,
                prompt: item.prompt,
                options: item.options.map { QuestionOption(text: $0) },
                correctAnswer: item.correctAnswer,
                translation: item.translation,
                explanation: item.explanation,
                sampleAnswer: item.sampleAnswer.isEmpty ? nil : item.sampleAnswer,
                sceneID: item.sceneID,
                cloze: item.cloze.map { ClozeContent(segments: $0.segments, blanks: $0.blanks.map { ClozeBlank(id: $0.id, options: $0.options, correctAnswer: $0.correctAnswer) }) },
                rubric: item.rubric.map { SpeechRubric(intent: $0.intent, requiredDetails: $0.requiredDetails, acceptableVariations: $0.acceptableVariations) },
                sourceFactIDs: item.sourceFactIDs
            )
        }
    }

    func reviewScene(_ scene: String) async throws -> SceneReview {
        let session = LanguageModelSession(instructions: PromptBuilder.systemInstructions)
        let response = try await measured("sceneReview") {
            try await session.respond(to: PromptBuilder.sceneReviewPrompt(scene), generating: AppleReview.self).content
        }
        return SceneReview(
            isAllowed: response.allowed,
            normalized: response.normalized,
            reason: response.reason
        )
    }

    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview] {
        let session = LanguageModelSession(instructions: PromptBuilder.systemInstructions)
        let response = try await measured("questionReview") {
            try await session.respond(to: PromptBuilder.qualityReviewPrompt(questions, request: request), generating: AppleQualityReview.self).content
        }
        return try response.decisions.map { item in
            guard let id = UUID(uuidString: item.questionID) else { throw GenerationError.malformedResponse }
            return QuestionReview(questionID: id, safe: item.safe, language: item.language, scene: item.scene,
                                  natural: item.natural, answer: item.answer, difficulty: item.difficulty, reason: item.reason)
        }
    }

    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String, languageCode: String,
                        explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict {
        let model = SystemLanguageModel.default
        guard model.supportsLocale(Locale(identifier: languageCode)),
              model.supportsLocale(Locale(identifier: explanationLanguage.rawValue)) else { throw GenerationError.modelUnavailable }
        let session = LanguageModelSession(instructions: PromptBuilder.systemInstructions)
        let response = try await measured("speechEvaluation") {
            try await session.respond(to: PromptBuilder.speechEvaluationPrompt(question, transcript: transcript,
                languageCode: languageCode, explanationLanguage: explanationLanguage), generating: AppleSemanticVerdict.self).content
        }
        guard let result = AttemptResult(rawValue: response.result) else { throw GenerationError.malformedResponse }
        return SemanticVerdict(result: result, feedback: response.feedback)
    }
}
