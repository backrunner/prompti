import Foundation
import Observation

enum PracticeOrigin: Sendable {
    case setup
    case quickQuestion
}

enum PracticeRoute: Hashable {
    case generation(UUID)
    case session(UUID)
}

@MainActor
@Observable
final class PracticeFlow {
    var path: [PracticeRoute] = []

    private var sessions: [UUID: PracticeSessionState] = [:]
    private(set) var origin = PracticeOrigin.setup

    func startGeneration(_ request: TrainingRequest, configuration: ProviderConfiguration? = nil, origin: PracticeOrigin = .setup) {
        clear()
        self.origin = origin
        let session = PracticeSessionState(records: [], request: request, configuration: configuration)
        sessions[session.id] = session
        path = [.generation(session.id)]
    }

    func startSession(_ records: [QuestionRecord], origin: PracticeOrigin) {
        clear()
        self.origin = origin
        let session = PracticeSessionState(records: records)
        sessions[session.id] = session
        path = [.session(session.id)]
    }

    /// Pushes the session that a generation route has been filling, so approved
    /// questions keep arriving in the background without restarting the job.
    /// Idempotent: repeated calls while that session is on top are ignored, so
    /// swiping back to the generation view lets the user enter again.
    func openSession(_ session: PracticeSessionState) {
        guard sessions[session.id] != nil, path.last != .session(session.id) else { return }
        path.append(.session(session.id))
    }

    func session(for id: UUID) -> PracticeSessionState? { sessions[id] }

    @discardableResult
    func finish() -> PracticeOrigin {
        let completedOrigin = origin
        clear()
        return completedOrigin
    }

    @discardableResult
    func cancel() -> PracticeOrigin {
        let cancelledOrigin = origin
        clear()
        return cancelledOrigin
    }

    private func clear() {
        path.removeAll()
        sessions.values.forEach { $0.cancelFill() }
        sessions.removeAll()
    }
}
