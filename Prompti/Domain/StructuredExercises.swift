import CryptoKit
import Foundation

enum ContentFingerprint {
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Rebuilt from saved questions, so relaunch, changed explanations and older
/// content hashes cannot reintroduce an exercise. Semantic paraphrases are also
/// checked by the existing quality review; this local gate is conservative.
struct QuestionDuplicateIndex: Sendable {
    private struct Entry: Sendable {
        let prompt: String
        let answer: String
        let grams: Set<String>
    }
    private var prompts: Set<String> = []
    private var utterances: Set<String> = []
    private var recent: [Entry] = []

    init(questions: [GeneratedQuestion] = []) {
        prompts = Set(questions.map { Self.normalize($0.prompt) })
        utterances = Set(questions.filter { $0.kind != .multipleChoice }.map { Self.normalize($0.correctAnswer) })
        recent = questions.suffix(200).map { question in
            let prompt = Self.normalize(question.prompt)
            return Entry(prompt: prompt, answer: Self.normalize(question.correctAnswer), grams: Self.trigrams(prompt))
        }
    }

    mutating func insert(_ question: GeneratedQuestion) -> Bool {
        let prompt = Self.normalize(question.prompt)
        let answer = Self.normalize(question.correctAnswer)
        guard !prompts.contains(prompt),
              question.kind == .multipleChoice || !utterances.contains(answer) else { return false }
        let grams = Self.trigrams(prompt)
        // Near matching only applies when the answer and numeric details are
        // identical and the long prompt barely varies.
        if prompt.count >= 24, recent.contains(where: { entry in
            entry.answer == answer && entry.prompt.count >= 24
                && entry.prompt.filter(\.isNumber) == prompt.filter(\.isNumber)
                && Double(grams.intersection(entry.grams).count) / Double(max(1, grams.union(entry.grams).count)) >= 0.9
        }) { return false }
        prompts.insert(prompt)
        if question.kind != .multipleChoice { utterances.insert(answer) }
        recent.append(Entry(prompt: prompt, answer: answer, grams: grams))
        if recent.count > 200 { recent.removeFirst() }
        return true
    }

    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func trigrams(_ text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.count >= 3 else { return [text] }
        return Set((0...(characters.count - 3)).map { String(characters[$0..<($0 + 3)]) })
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
    var promptVersion = "5"
    var schemaVersion = "2"
    var policyVersion = "2"
    var catalogVersion = "2026-09.3"
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
