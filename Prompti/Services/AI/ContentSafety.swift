import Foundation

struct SceneReview: Sendable {
    var isAllowed: Bool
    var normalized: String
    var reason: String
}

enum ContentSafety {
    private static let blockedFragments = [
        "ignore previous", "ignore all", "system prompt", "developer message", "jailbreak",
        "porn", "sexual service", "escort service", "minor sex", "child sex",
        "political campaign", "vote for", "propaganda", "extremist recruitment",
        "色情", "性服务", "拉票", "政治宣传", "忽略之前", "系统提示词",
        "ポルノ", "性的サービス", "政治宣伝", "이전 지시 무시", "성 서비스",
        "игнорируй предыдущ", "сексуальные услуги", "политическая агитация"
    ]

    static func normalizeScene(_ input: String) throws -> String {
        let normalized = input.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw GenerationError.invalidScene(String(localized: "Enter a short travel situation."))
        }
        guard normalized.count <= 80 else {
            throw GenerationError.invalidScene(String(localized: "Keep the situation under 80 characters."))
        }
        guard !normalized.contains("\n"), !normalized.contains("\r") else {
            throw GenerationError.invalidScene(String(localized: "Use one short line."))
        }
        guard !normalized.localizedCaseInsensitiveContains("http"),
              !normalized.contains("```"),
              !normalized.contains("{") else {
            throw GenerationError.invalidScene(String(localized: "Links and instruction-like text are not allowed."))
        }
        guard isLocallySafe(normalized) else {
            throw GenerationError.unsafeContent(String(localized: "That situation is outside Prompti's travel-learning scope."))
        }
        return normalized
    }

    static func isLocallySafe(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return !blockedFragments.contains(where: { folded.localizedCaseInsensitiveContains($0) })
    }

    static func validate(_ question: GeneratedQuestion, request: TrainingRequest) -> Bool {
        guard !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.prompt.count <= 500,
              question.translation.count <= 500,
              question.explanation.count <= 700,
              request.kinds.contains(question.kind) else { return false }

        let combined = [
            question.prompt,
            question.translation,
            question.explanation,
            question.correctAnswer,
            question.sampleAnswer ?? ""
        ] + question.options.map(\.text)
        guard combined.allSatisfy(isLocallySafe) else { return false }

        switch question.kind {
        case .cloze, .multipleChoice:
            guard (3...5).contains(question.options.count),
                  Set(question.options.map { $0.text.lowercased() }).count == question.options.count,
                  question.options.contains(where: { $0.text == question.correctAnswer }) else { return false }
        case .spoken:
            guard question.options.isEmpty, question.sampleAnswer?.isEmpty == false else { return false }
        }
        return true
    }
}
