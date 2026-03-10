import Foundation

struct StudyService {
    private let api = APIClient.shared

    // MARK: - Subjects

    func fetchSubjects() async throws -> [StudySubject] {
        let response: DataResponse<[StudySubject]> = try await api.get("/study/subjects")
        return response.data ?? []
    }

    func createSubject(name: String) async throws -> Int {
        try await api.postCreated("/study/subjects", body: StudySubjectRequest(name: name))
    }

    func updateSubject(id: Int, name: String) async throws {
        try await api.putVoid("/study/subjects/\(id)", body: StudySubjectRequest(name: name))
    }

    func reorderSubjects(ids: [Int]) async throws {
        try await api.putVoid("/study/subjects/reorder", body: StudySubjectReorderRequest(subjectIds: ids))
    }

    func deleteSubject(id: Int) async throws {
        try await api.deleteVoid("/study/subjects/\(id)")
    }

    // MARK: - Sessions

    func fetchActiveSession() async throws -> StudySession? {
        let response: DataResponse<StudySession?> = try await api.get("/study/sessions/active")
        return response.data ?? nil
    }

    func fetchSessions(from: String, to: String) async throws -> [StudySession] {
        let response: DataResponse<[StudySession]> = try await api.get("/study/sessions", query: ["from": from, "to": to])
        return response.data ?? []
    }

    func startSession(subjectId: Int) async throws -> Int {
        try await api.postCreated("/study/sessions", body: StudySessionStartRequest(subjectId: subjectId))
    }

    func pauseSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/pause")
    }

    func resumeSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/resume")
    }

    // MARK: - Daily Goal

    func fetchDailyGoal() async throws -> StudyDailyGoal? {
        let response: DataResponse<StudyDailyGoal?> = try await api.get("/study/daily-goals/today")
        return response.data ?? nil
    }

    func setDailyGoal(goalMinutes: Int) async throws {
        try await api.putVoid("/study/daily-goals/today", body: StudyDailyGoalRequest(goalMinutes: goalMinutes))
    }

    func endSession(id: Int) async throws -> StudySession {
        let response: DataResponse<StudySession> = try await api.patch("/study/sessions/\(id)/end")
        guard let data = response.data else { throw APIError.serverError(statusCode: 200, message: "세션 종료 응답 데이터 없음") }
        return data
    }
}
