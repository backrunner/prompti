import Foundation

enum ProviderDeadline {
    static func run<Value: Sendable>(until deadline: ContinuousClock.Instant,
                                     operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        guard deadline > .now else { throw GenerationError.timedOut }
        return try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await ContinuousClock().sleep(until: deadline)
                throw GenerationError.timedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw GenerationError.timedOut }
            return result
        }
    }
}
