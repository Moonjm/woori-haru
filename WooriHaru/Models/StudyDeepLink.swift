import Foundation

enum StudyDeepLink {
    case pause
    case resume
    case end

    var url: URL {
        switch self {
        case .pause: URL(string: "wooriharu://study/pause")!
        case .resume: URL(string: "wooriharu://study/resume")!
        case .end: URL(string: "wooriharu://study/end")!
        }
    }

    init?(url: URL) {
        guard url.scheme == "wooriharu", url.host() == "study" else { return nil }
        switch url.lastPathComponent {
        case "pause": self = .pause
        case "resume": self = .resume
        case "end": self = .end
        default: return nil
        }
    }
}
