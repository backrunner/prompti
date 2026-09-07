import CryptoKit
import Foundation

enum ContentFingerprint {
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct ClozeBlank: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var options: [String]
    var correctAnswer: String
}

struct ClozeContent: Codable, Hashable, Sendable {
    // segments.count == blanks.count + 1, including empty boundary segments.
    var segments: [String]
    var blanks: [ClozeBlank]

    var prompt: String { segments.joined(separator: "___") }
    var answer: String {
        guard segments.count == blanks.count + 1 else { return "" }
        return blanks.indices.reduce(segments[0]) { $0 + blanks[$1].correctAnswer + segments[$1 + 1] }
    }

    func isCorrect(_ selections: [String: String]) -> Bool {
        !blanks.isEmpty && blanks.allSatisfy { selections[$0.id] == $0.correctAnswer }
    }
}

struct SpeechRubric: Codable, Hashable, Sendable {
    var intent: String
    var requiredDetails: [String]
    var acceptableVariations: [String]
}

struct GenerationSourceFact: Codable, Hashable, Sendable {
    var id: String
    var text: String
}

struct GenerationMetadata: Codable, Hashable, Sendable {
    var jobID: UUID
    var batchID: UUID
    var provider: String
    var model: String
    var createdAt: Date
    var promptVersion = "2"
    var schemaVersion = "2"
    var policyVersion = "2"
    var catalogVersion = "2026-09"
    var sourceFactIDs: [String]
    var checks: [String]
    var sourceFacts: [GenerationSourceFact] = []
}

struct QuestionReview: Codable, Sendable {
    var questionID: UUID
    var safe: Bool
    var language: Bool
    var scene: Bool
    var natural: Bool
    var answer: Bool
    var difficulty: Bool
    var reason: String

    var approved: Bool { safe && language && scene && natural && answer && difficulty }
    static let checks = ["safety", "language", "scene", "naturalness", "answer validity and uniqueness", "difficulty"]
}

struct QuestionReviews: Codable, Sendable { var decisions: [QuestionReview] }

struct SemanticVerdict: Codable, Sendable {
    var result: AttemptResult
    var feedback: String

    var isValid: Bool {
        [.correct, .incorrect, .undetermined].contains(result)
            && !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && feedback.count <= 500 && ContentSafety.isLocallySafe(feedback)
    }
}
