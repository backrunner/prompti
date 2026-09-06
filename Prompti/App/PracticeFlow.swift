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
    private var sessions: [UUID: [QuestionRecord]] = [:]
    private(set) var origin = PracticeOrigin.setup

    func startGeneration(_ request: TrainingRequest, origin: PracticeOrigin = .setup) {
        let id = UUID()
        self.origin = origin
        requests[id] = request
        path = [.generation(id)]
    }

    func startSession(_ records: [QuestionRecord], origin: PracticeOrigin) {
        let id = UUID()
        self.origin = origin
        sessions[id] = records
        path = [.session(id)]
    }

    func showSession(_ records: [QuestionRecord]) {
        let id = UUID()
        sessions[id] = records
        path.append(.session(id))
    }

    func request(for id: UUID) -> TrainingRequest? {
        requests[id]
    }

    func records(for id: UUID) -> [QuestionRecord]? {
        sessions[id]
    }

    @discardableResult
    func finish() -> PracticeOrigin {
        let completedOrigin = origin
        path.removeAll()
        return completedOrigin
    }

    @discardableResult
    func cancel() -> PracticeOrigin {
        let cancelledOrigin = origin
        path.removeAll()
        return cancelledOrigin
    }
}
