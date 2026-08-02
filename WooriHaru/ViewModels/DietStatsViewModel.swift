import Foundation

/// 기간 통계 — 주·월 토글로 `from`~`to`만 바꿔 같은 엔드포인트를 부른다.
/// **LLM 조언이 없어서 폴링도 로딩 상태도 필요 없다.** 한 번 부르면 끝이다.
@MainActor
@Observable
final class DietStatsViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week, month

        var id: String { rawValue }
        var label: String { self == .week ? "주" : "월" }
        /// 양 끝을 포함한 일수. 서버 상한(366일)에 한참 못 미친다.
        var days: Int { self == .week ? 7 : 30 }
    }

    private(set) var range: Range = .week
    private(set) var stats: DietStats?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// 통계 조회 자체가 실패했는지. 알림을 닫아도 남아 있어야 "기록 없음"으로 오인되지 않는다.
    private(set) var loadFailed = false
    var errorMessage: String?

    /// 진행 중인 조회를 무효화하는 표식. 토글이 응답을 기다리는 도중 다시 바뀌면 값을 올려
    /// 뒤늦게 돌아온 이전 응답이 최신 선택의 결과를 덮어쓰지 않게 막는다.
    private var generation = 0

    private let service: any DietServing
    private let today: Date

    init(service: any DietServing = DietService(), today: Date = Date()) {
        self.service = service
        self.today = today
    }

    /// 조회가 실패했거나(loadFailed) 아직 끝나지 않았을 때는(!hasLoaded) 빈 상태로 보지
    /// 않는다 — 그러지 않으면 "기록 없음"과 "조회 실패/로딩 중"이 뒤섞여 보인다.
    var isEmpty: Bool { hasLoaded && !loadFailed && (stats?.recordedDays ?? 0) == 0 }

    /// 평균의 분모를 함께 보여줘야 "평균 1,980kcal"이 무슨 뜻인지 읽힌다.
    var recordedDaysText: String { "\(stats?.recordedDays ?? 0)일 기록" }

    /// 추이 차트용 좌표. **x는 날짜 간격을 반영한다** — 안 적은 날이 빠져 있으므로
    /// 배열 인덱스로 잡으면 3일 공백과 1일 공백이 같은 폭이 된다.
    var trendPoints: [(x: Double, y: Double, score: DailyScore)] {
        let scores = stats?.dailyScores ?? []
        let dates = scores.compactMap { Date.from($0.date) }
        guard dates.count == scores.count, let first = dates.first, let last = dates.last else { return [] }

        let span = last.timeIntervalSince(first)
        return zip(scores, dates).map { score, date in
            let x = span > 0 ? date.timeIntervalSince(first) / span : 0
            return (x: x, y: Double(score.dayScore) / 100.0, score: score)
        }
    }

    func select(_ newRange: Range) async {
        range = newRange
        await load()
    }

    func load() async {
        // `!isLoading` 가드로 두 번째 호출을 막지 않는다 — 토글을 연타하면 나중 선택이
        // 아무 응답도 받지 못한 채 이전 화면에 머문다. 대신 두 호출 다 내보내고,
        // 토큰이 최신인 쪽만 결과를 반영한다(`DietDayViewModel`과 같은 패턴).
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        loadFailed = false

        let calendar = Calendar.current
        // between이라 양 끝을 포함한다 — days만큼 빼면 days+1일이 잡히므로 1을 뺀다.
        guard let from = calendar.date(byAdding: .day, value: -(range.days - 1), to: today) else {
            if token == generation { isLoading = false }
            return
        }

        do {
            let result = try await service.fetchStats(from: from.dateString, to: today.dateString)
            guard token == generation else { return }
            stats = result
            loadFailed = false
        } catch is CancellationError {
            return
        } catch {
            guard token == generation else { return }
            errorMessage = error.localizedDescription
            loadFailed = true
            // 화면에 남아 있는 통계가 지금 선택된 기간(range)의 것이 아니면 지운다. `select(_:)`가
            // `range`를 먼저 바꾸고 나서 `load()`를 부르므로, 여기서 실패하면 화면에는
            // "이전 기간의 숫자 + 새 기간 라벨"이 남는다 — 예를 들어 주→월로 바꿨다가 실패하면
            // 「월」이 선택된 채 주간 평균이 그대로 보인다. 같은 기간을 재조회하다 실패한
            // 경우는 `stats.from/to`가 이미 요청한 범위와 같으니 지우지 않는다 — 그 데이터는
            // 여전히 맞는 값이라 지우면 오히려 퇴행이다.
            if let stats, stats.from != from.dateString || stats.to != today.dateString {
                self.stats = nil
            }
        }
        guard token == generation else { return }
        hasLoaded = true
        isLoading = false
    }
}
