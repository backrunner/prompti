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
        guard !normalized.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
        }) else {
            throw GenerationError.invalidScene(String(localized: "Use plain text without invisible control characters."))
        }
        guard !normalized.localizedCaseInsensitiveContains("http"),
              !normalized.contains("```"),
              !normalized.contains("://"),
              !normalized.localizedCaseInsensitiveContains("www."),
              !normalized.contains("{"), !normalized.contains("<"), !normalized.contains(">") else {
            throw GenerationError.invalidScene(String(localized: "Links and instruction-like text are not allowed."))
        }
        guard isLocallySafe(normalized) else {
            throw GenerationError.unsafeContent(String(localized: "That situation is outside Prompti's travel-learning scope."))
        }
        return normalized.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func isLocallySafe(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return !blockedFragments.contains(where: { folded.localizedCaseInsensitiveContains($0) })
    }

    static func validate(_ question: GeneratedQuestion, request: TrainingRequest) -> Bool {
        if let sceneID = question.sceneID {
            guard request.scenes.contains(where: { $0.id == sceneID }) else { return false }
        } else if request.scenes.count != 1 {
            return false
        }
        guard !question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.prompt.count <= 500,
              !question.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.translation.count <= 500,
              !question.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.explanation.count <= 700,
              !question.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              question.correctAnswer.count <= 500,
              (question.sampleAnswer?.count ?? 0) <= 500,
              request.kinds.contains(question.kind) else { return false }

        if let sources = question.sourceFactIDs {
            guard sources.count <= request.destination.facts.count,
                  Set(sources).count == sources.count,
                  Set(sources).isSubset(of: Set(PromptBuilder.factIDs(for: request))) else { return false }
        }
        if let rubric = question.rubric {
            guard question.kind == .spoken, !rubric.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  rubric.intent.count <= 300, rubric.requiredDetails.count <= 8,
                  rubric.acceptableVariations.count <= 5,
                  ([rubric.intent] + rubric.requiredDetails + rubric.acceptableVariations).allSatisfy({
                      !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 && isLocallySafe($0)
                  }) else { return false }
        }
        if let cloze = question.cloze {
            guard question.kind == .cloze, (1...3).contains(cloze.blanks.count),
                  cloze.segments.count == cloze.blanks.count + 1,
                  Set(cloze.blanks.map(\.id)).count == cloze.blanks.count,
                  cloze.blanks.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 40 && validOptions($0.options, answer: $0.correctAnswer) }),
                  cloze.segments.allSatisfy({ $0.count <= 500 && !$0.contains("___") && isLocallySafe($0) }),
                  question.prompt == cloze.prompt, question.correctAnswer == cloze.answer,
                  question.options.isEmpty else { return false }
        }
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
            if question.cloze != nil { return true }
            guard (3...5).contains(question.options.count),
                  question.options.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 500 }),
                  Set(question.options.map { $0.text.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == question.options.count,
                  question.options.contains(where: { $0.text == question.correctAnswer }) else { return false }
            if question.kind == .cloze, question.prompt.components(separatedBy: "___").count != 2 { return false }
        case .spoken:
            guard question.options.isEmpty,
                  let sample = question.sampleAnswer,
                  !sample.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  sample.count <= 500 else { return false }
        }
        return true
    }
    private static func validOptions(_ options: [String], answer: String) -> Bool {
        (3...5).contains(options.count) && options.contains(answer)
            && options.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 500 && isLocallySafe($0) }
            && Set(options.map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == options.count
    }

}
