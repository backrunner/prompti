import Foundation
import SwiftData

@MainActor
enum ReviewRecordDeletion {
    /// A review row represents a question and every attempt at that question.
    static func delete(questionIDs: Set<UUID>, context: ModelContext) throws {
        guard !questionIDs.isEmpty else { return }
        let questions = try context.fetch(FetchDescriptor<QuestionRecord>())
        let attempts = try context.fetch(FetchDescriptor<AttemptRecord>())
        // Recheck at confirmation time in case a report arrived through sync.
        let protectedIDs = Set(questions.filter(\.isQuarantined).map(\.id))
            .union(attempts.filter { $0.result == .reported }.map(\.questionID))
        let deletableIDs = questionIDs.subtracting(protectedIDs)
        guard !deletableIDs.isEmpty else { return }

        do {
            // Keep inventory tombstones so removing the last attempt cannot return
            // answered questions to the unused tray. Update every synced UUID copy.
            for question in questions where deletableIDs.contains(question.id) {
                question.isArchived = true
            }
            for attempt in attempts where deletableIDs.contains(attempt.questionID) {
                context.delete(attempt)
            }
            // SwiftData propagates the attempt deletions through the CloudKit store.
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
