import ActivityKit
import Foundation

enum TimerDisplayState: String, Codable, Hashable {
    case running
    case paused
    case idle
}

struct StudyTimerAttributes: ActivityAttributes {
    let subjectName: String

    struct ContentState: Codable, Hashable {
        let timerState: TimerDisplayState
        let startDate: Date
        let pausedElapsed: Int // 일시정지 시 고정된 경과 시간(초)
    }
}
