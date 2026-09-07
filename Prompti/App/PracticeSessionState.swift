import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class PracticeSessionState {
    let id = UUID()
    private(set) var records: [QuestionRecord]
    let requestedCount: Int
    let request: TrainingRequest?
    let configuration: ProviderConfiguration?
    private(set) var isFilling = false
    private(set) var fillError: String?
    private var fillTask: Task<Void, Never>?
    private var operationID = UUID()

    init(records: [QuestionRecord], request: TrainingRequest? = nil, configuration: ProviderConfiguration? = nil) {
        self.records = records
        self.request = request
        self.configuration = configuration
        requestedCount = request?.count ?? records.count
    }

    var hasRemaining: Bool { records.count < requestedCount && request != nil }

    func fill(using generation: QuestionGenerationService, context: ModelContext) {
        guard hasRemaining, !isFilling, let request, let configuration else { return }
        let operation = UUID()
        operationID = operation
        isFilling = true
        fillError = nil
        fillTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if operationID == operation { isFilling = false; fillTask = nil }
            }
            // At most one bounded generation job per start/retry. No endless retry loop.
            let batchSize = configuration.kind == .apple ? 2 : 3
            let deadline = ContinuousClock.now.advanced(by: .seconds(180))
            let maximumBatches = (requestedCount - records.count + batchSize - 1) / batchSize
            do {
                for _ in 0..<maximumBatches {
                    try Task.checkCancellation()
                    guard operationID == operation, hasRemaining else { return }
                    guard ContinuousClock.now < deadline else { throw GenerationError.timedOut }
                    var batch = request
                    batch.count = min(configuration.kind == .apple ? 2 : 3, requestedCount - records.count)
                    let existing = try context.fetch(FetchDescriptor<QuestionRecord>())
                    let signatures = Set(existing.filter { $0.destinationID == request.destination.id && $0.languageCode == request.language.code && $0.explanationLanguageCode == request.explanationLanguage.rawValue }.map { $0.question.contentSignature })
                    batch.previousPrompts = Array(existing.filter { $0.destinationID == request.destination.id && $0.languageCode == request.language.code }
                        .sorted { $0.createdAt < $1.createdAt }.suffix(30).map(\.prompt))
                    let generated = try await generation.generate(batch, configuration: configuration, jobID: id, excluding: signatures, deadline: deadline)
                    try Task.checkCancellation()
                    guard operationID == operation else { return }
                    let saved = try QuestionInventory.save(generated, request: batch, context: context)
                    records.append(contentsOf: saved)
                    if saved.isEmpty { break }
                }
                if hasRemaining { fillError = String(localized: "Some questions did not pass review. Retry to prepare the rest.") }
            } catch is CancellationError { }
            catch {
                guard operationID == operation else { return }
                fillError = error.localizedDescription
            }
        }
    }

    func cancelFill() {
        operationID = UUID()
        fillTask?.cancel()
        fillTask = nil
        isFilling = false
    }
}

@MainActor
enum QuestionInventory {
    static func save(_ questions: [GeneratedQuestion], request: TrainingRequest, context: ModelContext) throws -> [QuestionRecord] {
        let existing = try context.fetch(FetchDescriptor<QuestionRecord>())
        var signatures = Set(existing.filter {
            $0.destinationID == request.destination.id && $0.languageCode == request.language.code
                && $0.explanationLanguageCode == request.explanationLanguage.rawValue
        }.map { $0.question.contentSignature })
        var saved: [QuestionRecord] = []
        do {
            for question in questions {
                var isNew = signatures.insert(question.contentSignature).inserted
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-prompti-demo") { isNew = true }
                #endif
                guard isNew else { continue }
                guard let scene = request.scenes.first(where: { $0.id == question.sceneID }) ?? request.scenes.first else { continue }
                let record = QuestionRecord(question: question, request: request, scene: scene)
                context.insert(record)
                saved.append(record)
            }
            try context.save()
            return saved
        } catch { context.rollback(); throw error }
    }

    static func available(_ questions: [QuestionRecord], attempts: [AttemptRecord], destinationID: String,
                          languageCode: String, explanationLanguage: ExplanationLanguage, difficulty: TrainingDifficulty) -> [QuestionRecord] {
        let attempted = Set(attempts.map(\.questionID))
        let relevant = questions.filter { $0.destinationID == destinationID && $0.languageCode == languageCode && $0.explanationLanguageCode == explanationLanguage.rawValue }
        let excluded = Set(relevant.filter { $0.isQuarantined || $0.isArchived || attempted.contains($0.id) }.map { $0.question.contentSignature })
        var seen = excluded
        return questions.filter {
            !$0.isQuarantined && !$0.isArchived && !attempted.contains($0.id)
                && $0.destinationID == destinationID && $0.languageCode == languageCode
                && $0.explanationLanguageCode == explanationLanguage.rawValue && $0.difficultyRaw == difficulty.rawValue
                && seen.insert($0.question.contentSignature).inserted
        }
    }

    static func clearUnused(context: ModelContext) throws {
        let attempted = Set(try context.fetch(FetchDescriptor<AttemptRecord>()).map(\.questionID))
        do {
            for record in try context.fetch(FetchDescriptor<QuestionRecord>()) where !attempted.contains(record.id) {
                record.isArchived = true // Synced tombstone prevents stale devices from restoring the tray.
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
