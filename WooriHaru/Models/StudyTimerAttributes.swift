import ActivityKit
import Foundation

struct StudyTimerAttributes: ActivityAttributes {
    let subjectName: String

    struct ContentState: Codable, Hashable {
        let timerState: String // "running", "paused"
        let startDate: Date
        let pausedElapsed: Int // 일시정지 시 고정된 경과 시간(초)
    }
}
