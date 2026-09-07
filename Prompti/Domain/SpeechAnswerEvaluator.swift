import Foundation

struct SpeechEvaluation: Sendable {
    let result: AttemptResult
    let title: String
    let message: String
}

enum SpeechAnswerEvaluator {
    static func evaluate(transcript: String, reference: String, confidence: Float?) -> SpeechEvaluation {
        let transcript = normalized(transcript)
        let reference = normalized(reference)

        guard !transcript.isEmpty, !reference.isEmpty else {
            return SpeechEvaluation(
                result: .undetermined,
                title: String(localized: "Unable to judge"),
                message: String(localized: "Try recording again, or compare your wording with the sample answer.")
            )
        }

        if let confidence, confidence < 0.3 {
            return SpeechEvaluation(
                result: .undetermined,
                title: String(localized: "The transcript was uncertain"),
                message: String(localized: "Prompti did not score this attempt. Try again somewhere quieter or compare the sample answer.")
            )
        }

        let similarity = diceSimilarity(transcript, reference)
        // Wording overlap cannot establish intent: a short fragment, negation or
        // changed destination can still be almost identical to the reference.
        // Only an exact normalized match is scored without a semantic evaluator.
        if transcript == reference {
            return SpeechEvaluation(
                result: .correct,
                title: String(localized: "Expression matched"),
                message: String(localized: "Your transcript captured the key wording in the sample answer.")
            )
        }

        if similarity >= 0.34 {
            return SpeechEvaluation(
                result: .undetermined,
                title: String(localized: "Mostly understandable"),
                message: String(localized: "Your wording is close. Compare the transcript with the sample and try once more if you like.")
            )
        }

        return SpeechEvaluation(
            result: .undetermined,
            title: String(localized: "Worth another try"),
            message: String(localized: "Prompti could not confidently match the key phrase, so this attempt was not scored.")
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func diceSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsPairs = pairs(in: lhs)
        let rhsPairs = pairs(in: rhs)
        guard !lhsPairs.isEmpty, !rhsPairs.isEmpty else { return lhs == rhs ? 1 : 0 }

        var available = rhsPairs
        var intersection = 0
        for pair in lhsPairs {
            if let index = available.firstIndex(of: pair) {
                intersection += 1
                available.remove(at: index)
            }
        }
        return Double(intersection * 2) / Double(lhsPairs.count + rhsPairs.count)
    }

    private static func pairs(in value: String) -> [String] {
        let characters = Array(value)
        guard characters.count > 1 else { return value.isEmpty ? [] : [value] }
        return zip(characters, characters.dropFirst()).map { String([$0, $1]) }
    }
}
