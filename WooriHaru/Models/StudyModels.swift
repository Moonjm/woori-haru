import Foundation

struct StudySubject: Codable, Identifiable {
    let id: Int
    let name: String
}

struct PauseType: Codable, Identifiable {
    let value: String
    let label: String
    var id: String { value }
}

struct StudyPause: Codable, Identifiable {
    let id: Int
    let pausedAt: String
    let resumedAt: String?
    let pauseType: String?
}

struct PauseTypeRequest: Encodable {
    let type: String
}

struct StudySession: Codable, Identifiable {
    let id: Int
    let subject: StudySubject
    let startedAt: String
    let endedAt: String?
    let totalSeconds: Int
    let pauses: [StudyPause]
}

extension StudySession {
    var pauseSeconds: Int {
        let sessionEnd = endedAt.flatMap { Date.fromISO($0) } ?? Date()
        return pauses.reduce(0) { sum, pause in
            guard let start = Date.fromISO(pause.pausedAt) else { return sum }
            let end = pause.resumedAt.flatMap { Date.fromISO($0) } ?? sessionEnd
            return sum + Int(end.timeIntervalSince(start))
        }
    }
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
