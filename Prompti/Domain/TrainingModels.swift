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
}

enum ExplanationLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
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
}
