import Foundation

enum TrainingDifficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case survival
    case basic
    case natural
    case fluent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .survival: "Survival"
        case .basic: "Basic"
        case .natural: "Natural"
        case .fluent: "Fluent"
        }
    }

    var detail: String {
        switch self {
        case .survival: "Short phrases and generous hints"
        case .basic: "Everyday sentences for simple conversations"
        case .natural: "Natural phrasing and closer distractors"
        case .fluent: "Nuanced, region-aware conversation"
        }
    }

    var generationConstraints: String {
        switch self {
        case .survival: "A1: one clause, at most 8 words (30 characters for Chinese/Japanese); common concrete vocabulary; obvious but meaningful distractors; include a short usage hint."
        case .basic: "A2–B1: at most 15 words (55 characters for Chinese/Japanese); everyday vocabulary; simple questions and polite requests; distinguish distractors by meaning."
        case .natural: "B1–B2: at most 25 words (90 characters for Chinese/Japanese); at most two clauses; natural polite phrasing; plausible distractors with one unambiguous best answer."
        case .fluent: "B2–C1: at most 40 words (140 characters for Chinese/Japanese); nuanced register and connected clauses; closely related distractors; use regional expressions only when supported by supplied facts."
        }
    }
}

enum ExplanationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }

    static func suggested(preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        preferredLanguages.first?.hasPrefix("zh") == true ? .simplifiedChinese : .english
    }

    var promptName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "Simplified Chinese"
        }
    }
}

enum QuestionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloze
    case multipleChoice
    case spoken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cloze: "Fill the gap"
        case .multipleChoice: "Quick Q&A"
        case .spoken: "Speak"
        }
    }

    var symbol: String {
        switch self {
        case .cloze: "rectangle.and.pencil.and.ellipsis"
        case .multipleChoice: "checklist"
        case .spoken: "waveform"
        }
    }
}

struct QuestionOption: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var text: String
}

struct GeneratedQuestion: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: QuestionKind
    var prompt: String
    var options: [QuestionOption]
    var correctAnswer: String
    var translation: String
    var explanation: String
    var sampleAnswer: String?
    var sceneID: String? = nil
    var cloze: ClozeContent? = nil
    var rubric: SpeechRubric? = nil
    var generation: GenerationMetadata? = nil
    var sourceFactIDs: [String]? = nil

    var contentSignature: String {
        ContentFingerprint.hash([kind.rawValue, prompt, correctAnswer, cloze?.blanks.map(\.correctAnswer).joined(separator: "|") ?? ""]
            .map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{0}"))
    }
}

struct TrainingRequest: Sendable {
    var destination: Destination
    var language: TrainingLanguage
    var explanationLanguage: ExplanationLanguage
    var scenes: [TravelScene]
    var customScene: String?
    var difficulty: TrainingDifficulty
    var kinds: Set<QuestionKind>
    var count: Int
    var previousPrompts: [String] = []
}

enum AttemptResult: String, Codable, Sendable {
    case correct
    case incorrect
    case skipped
    case reported
    case undetermined
}

enum ReportReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case incorrectAnswer
    case unnaturalLanguage
    case unrelatedToDestination
    case inappropriateContent
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incorrectAnswer: "The answer looks wrong"
        case .unnaturalLanguage: "The language feels unnatural"
        case .unrelatedToDestination: "It is unrelated to the destination"
        case .inappropriateContent: "The content is inappropriate"
        case .other: "Something else"
        }
    }
}

struct SessionResultCounts: Sendable {
    private(set) var correct = 0
    private(set) var incorrect = 0
    private(set) var skipped = 0
    private(set) var undetermined = 0
    private(set) var reported = 0

    mutating func record(_ result: AttemptResult) {
        switch result {
        case .correct: correct += 1
        case .incorrect: incorrect += 1
        case .skipped: skipped += 1
        case .undetermined: undetermined += 1
        case .reported: reported += 1
        }
    }

    mutating func remove(_ result: AttemptResult) {
        switch result {
        case .correct: correct = max(0, correct - 1)
        case .incorrect: incorrect = max(0, incorrect - 1)
        case .skipped: skipped = max(0, skipped - 1)
        case .undetermined: undetermined = max(0, undetermined - 1)
        case .reported: reported = max(0, reported - 1)
        }
    }
}
