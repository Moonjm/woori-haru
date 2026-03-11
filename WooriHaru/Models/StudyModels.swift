import Foundation

struct StudySubject: Codable, Identifiable {
    let id: Int
    let name: String
}

struct StudyPause: Codable, Identifiable {
    let id: Int
    let pausedAt: String
    let resumedAt: String?
}

struct StudySession: Codable, Identifiable {
    let id: Int
    let subject: StudySubject
    let startedAt: String
    let endedAt: String?
    let totalSeconds: Int
    let pauses: [StudyPause]
}

struct StudySessionStartRequest: Encodable {
    let subjectId: Int
}

struct StudySubjectRequest: Encodable {
    let name: String
}

struct StudySubjectReorderRequest: Encodable {
    let subjectIds: [Int]
}

// MARK: - Daily Goal

struct StudyDailyGoal: Codable {
    let goalMinutes: Int?
}

struct StudyDailyGoalRequest: Encodable {
    let date: String
    let goalMinutes: Int
}

// MARK: - Weekly Summary

struct StudyWeeklySummary: Codable {
    let totalGoalMinutes: Int
    let totalActualMinutes: Int
}
