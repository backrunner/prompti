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
    /// Snapshot of the provider chosen when the set started; a retry may pick
    /// up a repaired configuration.
    var configuration: ProviderConfiguration?
    private(set) var isFilling = false
    private(set) var fillError: Error?
    /// Furthest pipeline stage reached by the current fill. Review rejections
    /// may send work back to generation internally, but this never regresses so
    /// the UI can show steady forward progress.
    private(set) var furthestStage: QuestionGenerationStage?
    private var fillTask: Task<Void, Never>?
    private var fillContext: ModelContext?
    private var operationID = UUID()

    init(records: [QuestionRecord], request: TrainingRequest? = nil, configuration: ProviderConfiguration? = nil) {
        self.records = records
        self.request = request
        self.configuration = configuration
        requestedCount = request?.count ?? records.count
    }

    var hasRemaining: Bool { records.count < requestedCount && request != nil }

    /// User-facing fill problem. When some questions are ready a shortfall is a
    /// retryable remainder, not the raw pipeline error.
    var fillMessage: String? {
        guard let fillError else { return nil }
        if case GenerationError.noApprovedQuestions = fillError, !records.isEmpty {
            return String(localized: "Some questions did not pass review. Retry to prepare the rest.")
        }
        return fillError.localizedDescription
    }

    /// Entering practice after partial generation must not silently start a
    /// second budgeted job. A visible retry remains an explicit user action.
    func fillIfNeeded(using generation: QuestionGenerationService, context: ModelContext) {
        guard fillError == nil else { return }
        fill(using: generation, context: context)
    }

    func fill(using generation: QuestionGenerationService, context: ModelContext) {
        guard hasRemaining, !isFilling, let request, let configuration else { return }
        let operation = UUID()
        operationID = operation
        isFilling = true
        fillError = nil
        furthestStage = nil
        fillContext = context
        // At most one bounded generation job per start/retry; its batches run
        // concurrently inside the service. No endless retry loop.
        let deadline = ContinuousClock.now.advanced(by: .seconds(180))
        fillTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if operationID == operation {
                    isFilling = false
                    fillTask = nil
                    fillContext = nil
                }
            }
            do {
                var batch = request
                batch.count = requestedCount - records.count
                let existing = try context.fetch(FetchDescriptor<QuestionRecord>())
                let relevant = existing.filter { $0.destinationID == request.destination.id && $0.languageCode == request.language.code }
                    .sorted { $0.createdAt < $1.createdAt }
                let signatures = Set(relevant.map { $0.question.contentSignature })
                batch.previousQuestions = relevant.map(\.question)
                batch.previousPrompts = Array(existing.filter { $0.destinationID == request.destination.id && $0.languageCode == request.language.code }
                    .sorted { $0.createdAt < $1.createdAt }.suffix(30).map(\.prompt))
                let activeRequest = batch
                _ = try await generation.generate(batch, configuration: configuration, jobID: id,
                    excluding: signatures, deadline: deadline) { [weak self] event in
                    await self?.handleGenerationEvent(event, request: activeRequest, operation: operation)
                }
                try Task.checkCancellation()
                guard operationID == operation else { return }
                if hasRemaining {
                    fillError = GenerationError.noApprovedQuestions
                }
            } catch is CancellationError { }
            catch {
                guard operationID == operation else { return }
                fillError = error
            }
        }
    }

    private func handleGenerationEvent(_ event: QuestionGenerationEvent, request: TrainingRequest, operation: UUID) {
        guard operationID == operation else { return }
        switch event {
        case .stage(let stage):
            if stage == .reviewing { furthestStage = .reviewing }
            else if furthestStage == nil { furthestStage = .generating }
        case .approved(let questions):
            guard let context = fillContext else { return }
            do {
                let saved = try QuestionInventory.save(Array(questions.prefix(max(0, requestedCount - records.count))), request: request, context: context)
                let known = Set(records.map(\.id))
                records.append(contentsOf: saved.filter { !known.contains($0.id) })
            } catch {
                cancelFill()
                fillError = error
            }
        }
    }

    func cancelFill() {
        operationID = UUID()
        fillTask?.cancel()
        fillTask = nil
        fillContext = nil
        isFilling = false
    }
}

@MainActor
enum QuestionInventory {
    static func save(_ questions: [GeneratedQuestion], request: TrainingRequest, context: ModelContext) throws -> [QuestionRecord] {
        let existing = try context.fetch(FetchDescriptor<QuestionRecord>())
        let relevant = existing.filter { $0.destinationID == request.destination.id && $0.languageCode == request.language.code }
            .sorted { $0.createdAt < $1.createdAt }
        var duplicates = QuestionDuplicateIndex(questions: relevant.map(\.question))
        var ids = Set(existing.map(\.id))
        var saved: [QuestionRecord] = []
        do {
            for question in questions {
                var isNew = ids.insert(question.id).inserted && duplicates.insert(question)
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
        let relevant = questions.filter { $0.destinationID == destinationID && $0.languageCode == languageCode }
        var duplicates = QuestionDuplicateIndex(questions: relevant.filter {
            $0.isQuarantined || $0.isArchived || attempted.contains($0.id)
        }.map(\.question))
        return questions.filter {
            !$0.isQuarantined && !$0.isArchived && !attempted.contains($0.id)
                && $0.destinationID == destinationID && $0.languageCode == languageCode
                && $0.explanationLanguageCode == explanationLanguage.rawValue && $0.difficultyRaw == difficulty.rawValue
                && duplicates.insert($0.question)
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
