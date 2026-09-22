import Foundation

enum QuestionReviewMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case generationModel
    case typeSafeJev

    var id: String { rawValue }
    var title: String {
        switch self {
        case .generationModel: "Use generation model"
        case .typeSafeJev: "TypeSafe Jev"
        }
    }
}

/// Optional metadata keeps old saved questions decodable. No credentials or
/// rejected content are persisted; probabilities describe the approved question.
struct QuestionReviewProvenance: Codable, Hashable, Sendable {
    var provider: String
    var model: String
    var policyVersion: String?
    var jevModel: String?
    var probabilities: [String: Double]?
}

struct FastQuestionAssessment: Sendable {
    enum Disposition: Sendable { case approve, reject, needsReview }
    var disposition: Disposition
    var model: String
    var probabilities: [String: Double]
}

protocol FastQuestionReviewer: Sendable {
    func assess(_ question: GeneratedQuestion, request: TrainingRequest) async throws -> FastQuestionAssessment
}
