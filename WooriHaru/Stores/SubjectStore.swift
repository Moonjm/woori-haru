import Foundation
import Observation

@MainActor
@Observable
final class SubjectStore {
    private(set) var subjects: [StudySubject] = []
    private let service = StudyService()

    func load() async throws {
        subjects = try await service.fetchSubjects()
    }

    func create(name: String) async throws {
        _ = try await service.createSubject(name: name)
        try await load()
    }

    func update(id: Int, name: String) async throws {
        try await service.updateSubject(id: id, name: name)
        try await load()
    }

    func delete(id: Int) async throws {
        try await service.deleteSubject(id: id)
        try await load()
    }
}
