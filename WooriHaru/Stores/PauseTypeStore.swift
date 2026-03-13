import Foundation
import Observation

@MainActor
@Observable
final class PauseTypeStore {
    private(set) var pauseTypes: [PauseType] = []
    private let service = StudyService()

    func load() async throws {
        guard pauseTypes.isEmpty else { return }
        pauseTypes = try await service.fetchPauseTypes()
    }
}
