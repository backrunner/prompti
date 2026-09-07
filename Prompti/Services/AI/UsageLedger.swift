import CoreFoundation
import Foundation
import Observation

struct ModelUsage: Codable, Identifiable, Sendable {
    var id = UUID()
    var jobID: UUID?
    var createdAt = Date()
    var provider: String
    var model: String
    var operation: String
    var status = "started"
    var inputTokens: Int?
    var outputTokens: Int?

    var operationTitle: String {
        if operation.contains("speech") || operation == "speechEvaluation" { return "Speech feedback" }
        if operation.contains("probe") { return "Connection check" }
        if operation.contains("scene") || operation == "sceneReview" { return "Scene review" }
        if operation.contains("question_review") || operation == "questionReview" { return "Question review" }
        return "Question generation"
    }

    var statusTitle: String {
        switch status {
        case "received": "Response received"
        case "failed": "Request failed"
        case "cancelled": "Cancelled"
        default: "No response recorded"
        }
    }

    mutating func complete(data: Data, statusCode: Int) {
        status = (200..<300).contains(statusCode) ? "received" : "failed"
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let usage = object?["usage"] as? [String: Any]
        inputTokens = Self.tokenCount(usage?["input_tokens"] ?? usage?["prompt_tokens"])
        outputTokens = Self.tokenCount(usage?["output_tokens"] ?? usage?["completion_tokens"])
    }

    private static func tokenCount(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 0, number.doubleValue < Double(Int.max / 1000),
              number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
        return number.intValue
    }
}

typealias UsageSink = @Sendable (ModelUsage) async -> Void

@MainActor
@Observable
final class UsageLedger {
    private(set) var entries: [ModelUsage]
    private let defaults: UserDefaults
    private let key = "model.usage.v1"
    // This is a recent-request ledger, not an invoice or price estimate.
    static let retainedCount = 1000

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([ModelUsage].self, from: $0) } ?? []
    }

    func record(_ entry: ModelUsage) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) { entries[index] = entry }
        else { entries.append(entry) }
        if entries.count > Self.retainedCount { entries.removeFirst(entries.count - Self.retainedCount) }
        defaults.set(try? JSONEncoder().encode(entries), forKey: key)
    }

    var reportedInputTokens: Int { entries.compactMap(\.inputTokens).reduce(0, +) }
    var reportedOutputTokens: Int { entries.compactMap(\.outputTokens).reduce(0, +) }
    var unknownUsageCount: Int { entries.filter { $0.inputTokens == nil || $0.outputTokens == nil }.count }
}
