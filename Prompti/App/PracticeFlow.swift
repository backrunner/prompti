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

    private var requests: [UUID: TrainingRequest] = [:]
    private var sessions: [UUID: PracticeSessionState] = [:]
    private(set) var origin = PracticeOrigin.setup

    func startGeneration(_ request: TrainingRequest, origin: PracticeOrigin = .setup) {
        clear()
        let id = UUID()
        self.origin = origin
        requests[id] = request
        path = [.generation(id)]
    }

    func startSession(_ records: [QuestionRecord], origin: PracticeOrigin) {
        clear()
        let id = UUID()
        self.origin = origin
        sessions[id] = PracticeSessionState(records: records)
        path = [.session(id)]
    }

    func showSession(_ records: [QuestionRecord], request: TrainingRequest? = nil, configuration: ProviderConfiguration? = nil) {
        let id = UUID()
        sessions[id] = PracticeSessionState(records: records, request: request, configuration: configuration)
        path.append(.session(id))
    }

    func request(for id: UUID) -> TrainingRequest? {
        requests[id]
    }

    func records(for id: UUID) -> [QuestionRecord]? {
        sessions[id]?.records
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
        requests.removeAll()
        sessions.values.forEach { $0.cancelFill() }
        sessions.removeAll()
    }
}
