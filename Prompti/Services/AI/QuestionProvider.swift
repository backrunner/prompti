import Foundation

protocol QuestionProvider: Sendable {
    func generate(_ request: TrainingRequest) async throws -> [GeneratedQuestion]
    func reviewScene(_ scene: String) async throws -> SceneReview
    func reviewQuestions(_ questions: [GeneratedQuestion], request: TrainingRequest) async throws -> [QuestionReview]
    func evaluateSpeech(_ question: GeneratedQuestion, transcript: String, languageCode: String,
                        explanationLanguage: ExplanationLanguage) async throws -> SemanticVerdict
}
