import Foundation

struct StudyService: Sendable {
    private let api: any APIClientProtocol

    init(api: any APIClientProtocol = APIClient.shared) {
        self.api = api
    }

    // MARK: - Subjects

    func fetchSubjects() async throws -> [StudySubject] {
        let response: DataResponse<[StudySubject]> = try await api.get("/study/subjects", query: [:])
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
        let response: DataResponse<StudySession?> = try await api.get("/study/sessions/active", query: [:])
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
        try await api.patchVoid("/study/sessions/\(id)/pause", body: nil)
    }

    func resumeSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/resume", body: nil)
    }

    func endSession(id: Int) async throws {
        try await api.patchVoid("/study/sessions/\(id)/end", body: nil)
    }

    // MARK: - Pause Types

    func fetchPauseTypes() async throws -> [PauseType] {
        let response: DataResponse<[PauseType]> = try await api.get("/study/pause-types", query: [:])
        return response.data ?? []
    }

    func setPauseType(sessionId: Int, pauseType: String) async throws {
        try await api.patchVoid("/study/sessions/\(sessionId)/pause-type", body: PauseTypeRequest(type: pauseType))
    }

    // MARK: - Daily Goal

    func fetchDailyGoal() async throws -> StudyDailyGoal? {
        let response: DataResponse<StudyDailyGoal?> = try await api.get("/study/daily-goals/today", query: [:])
        return response.data ?? nil
    }

    func setDailyGoal(goalMinutes: Int) async throws {
        let today = Date().dateString
        try await api.putVoid("/study/daily-goals", body: StudyDailyGoalRequest(date: today, goalMinutes: goalMinutes))
    }

    // MARK: - Weekly Summary

    func fetchWeeklySummary() async throws -> StudyWeeklySummary {
        let response: DataResponse<StudyWeeklySummary> = try await api.get("/study/weekly-summary", query: [:])
        return response.data ?? StudyWeeklySummary(totalGoalMinutes: 0, totalActualMinutes: 0)
    }
}
