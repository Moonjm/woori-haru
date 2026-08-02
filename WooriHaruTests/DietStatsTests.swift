import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct DietStatsViewModelTests {
    private let today = Date.from("2026-07-30")!

    private func stats(recordedDays: Int, scores: [DailyScore] = []) -> DietStats {
        DietStats(
            from: "2026-07-24", to: "2026-07-30", recordedDays: recordedDays,
            averageDayScore: recordedDays == 0 ? nil : 74,
            dailyScores: scores,
            averageIntake: recordedDays == 0 ? nil : NutritionTotals(
                kcal: 1980, carbsG: 250.1, proteinG: 78.4, fatG: 62,
                sugarG: 44.2, sodiumMg: 2610, fiberG: 14.8
            ),
            averageTargets: recordedDays == 0 ? nil : NutritionTargets(
                kcal: 2509, carbsG: 345, proteinG: 94, fatG: 84,
                sugarG: 125, sodiumMg: 2300, fiberG: 30
            ),
            topFoods: []
        )
    }

    /// 주 토글은 7일치(양 끝 포함)를 부른다.
    @Test func 주간_범위를_계산한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(service.statsRanges.first?.from == "2026-07-24")
        #expect(service.statsRanges.first?.to == "2026-07-30")
    }

    /// 월 토글은 30일치를 부른다. **최대 366일 상한에 걸리지 않는다.**
    @Test func 월간_범위를_계산한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 20)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.select(.month)

        #expect(service.statsRanges.last?.from == "2026-07-01")
        #expect(service.statsRanges.last?.to == "2026-07-30")
    }

    /// 기록이 0건이면 세 값이 null이다 — 옵셔널로 받아 빈 상태를 그린다.
    @Test func 기록이_0건이면_빈_상태다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 0)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.isEmpty)
        #expect(vm.stats?.averageDayScore == nil)
        #expect(vm.stats?.averageIntake == nil)
        #expect(vm.errorMessage == nil)
    }

    /// **평균은 기록한 날로만 낸 값이다** — "6일 기록"을 함께 보여줘야 평균이 무슨 뜻인지 읽힌다.
    @Test func 기록한_날_수를_함께_보여준다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.recordedDaysText == "6일 기록")
        #expect(!vm.isEmpty)
    }

    /// `dailyScores`에는 **기록한 날만** 들어간다 — x축을 배열 인덱스로 잡으면 간격이 뭉개진다.
    ///
    /// **간격을 일부러 고르지 않게 잡는다.** 24·27·30일처럼 3일씩 균등하면 인덱스 기반(0, 0.5, 1)과
    /// 날짜 기반(0, 0.5, 1)이 같은 값을 내 이 테스트가 아무것도 구분하지 못한다 — 24·25·30일로
    /// 두면 날짜 기반은 (0, 1/6, 1), 인덱스 기반은 (0, 0.5, 1)로 갈라져야 실제로 검증이 된다.
    @Test func 추이는_날짜로_배치한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 3, scores: [
            DailyScore(date: "2026-07-24", dayScore: 81),
            DailyScore(date: "2026-07-25", dayScore: 65),
            DailyScore(date: "2026-07-30", dayScore: 74)
        ])
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        let points = vm.trendPoints
        #expect(points.count == 3)
        #expect(points[0].x == 0)
        #expect(points[2].x == 1)
        // 24일→25일은 1일, 24일→30일은 6일 — 인덱스 기반이면 0.5가 나오지만
        // 날짜 기반이면 1/6이어야 한다.
        #expect(abs(points[1].x - (1.0 / 6.0)) < 0.001)
    }

    /// 기록이 하루뿐이면 간격(span)이 0이다 — 0으로 나누지 않고 유일한 점을 x=0에 둔다.
    @Test func 추이는_기록이_하루뿐이면_0으로_나누지_않는다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 1, scores: [
            DailyScore(date: "2026-07-24", dayScore: 81)
        ])
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        let points = vm.trendPoints
        #expect(points.count == 1)
        #expect(points[0].x == 0)
    }

    /// `dailyScores`가 비어 있으면 점도 없다 — 크래시하지 않는다.
    @Test func 추이는_기록이_없으면_빈다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 0, scores: [])
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.trendPoints.isEmpty)
    }

    /// 조회 자체가 실패하면 표시를 남겨 둔다 — 알림을 닫아도 "이 기간에 기록한 끼니가
    /// 없어요"로 오인되지 않으려면 이 표식이 `isEmpty`를 계속 false로 눌러야 한다.
    /// `DietDayViewModel`의 같은 사고와 같은 수정.
    @Test func 통계_조회가_실패하면_loadFailed를_켠다() async {
        let service = FakeDietService()
        service.errors["fetchStats"] = dietServerError("SERVER_ERROR", status: 500)
        let vm = DietStatsViewModel(service: service, today: today)

        await vm.load()

        #expect(vm.loadFailed)
        #expect(vm.stats == nil)
        #expect(!vm.isEmpty)
    }

    /// 실패 뒤 다시 시도해 성공하면 실패 표시가 꺼져야 실패 카드가 사라지고 정상 상태로
    /// 돌아간다.
    @Test func 재조회가_성공하면_loadFailed를_끈다() async {
        let service = FakeDietService()
        service.errors["fetchStats"] = dietServerError("SERVER_ERROR", status: 500)
        let vm = DietStatsViewModel(service: service, today: today)
        await vm.load()
        #expect(vm.loadFailed)

        service.errors["fetchStats"] = nil
        service.stats = stats(recordedDays: 6)
        await vm.load()

        #expect(!vm.loadFailed)
        #expect(vm.stats?.recordedDays == 6)
    }

    /// **범위를 바꾼 뒤 실패하면 이전 범위의 통계를 화면에 남기면 안 된다.** `select(_:)`는
    /// `range`를 먼저 바꾸고 나서 `load()`를 부르므로, 지우지 않으면 피커는 「월」을 가리키는데
    /// 숫자는 주간 것이 그대로 보인다. `DietDayViewModel`의 같은 사고와 같은 수정.
    @Test func 범위를_바꾼_뒤_조회가_실패하면_이전_범위_데이터를_남기지_않는다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)
        await vm.load()
        #expect(vm.stats?.from == "2026-07-24")

        service.errors["fetchStats"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.select(.month)

        #expect(vm.loadFailed)
        #expect(vm.stats == nil)
    }

    /// 반대로 **같은 범위를 재조회하다 실패한 경우**는 화면에 있는 통계가 여전히 맞는
    /// 값이므로 지우면 오히려 퇴행이다 — 오류는 그대로 알리되 데이터는 유지한다.
    @Test func 같은_범위_재조회가_실패하면_기존_데이터를_유지한다() async {
        let service = FakeDietService()
        service.stats = stats(recordedDays: 6)
        let vm = DietStatsViewModel(service: service, today: today)
        await vm.load()
        #expect(vm.stats?.recordedDays == 6)

        service.errors["fetchStats"] = dietServerError("SERVER_ERROR", status: 500)
        await vm.load()

        #expect(vm.loadFailed)
        #expect(vm.stats?.recordedDays == 6)
    }

    /// 첫 조회가 끝나기 전에는 `isEmpty`가 false다 — 그러지 않으면 로딩 중에도
    /// "기록 없음"이 잠깐 보인다.
    @Test func 첫_조회가_끝나기_전에는_비어있지_않다() async {
        let service = FakeDietService()
        let gate = AsyncGate()
        service.stats = stats(recordedDays: 0)
        service.statsGates["2026-07-24"] = gate
        let vm = DietStatsViewModel(service: service, today: today)

        let loadTask = Task { await vm.load() }
        await gate.waitUntilBlocked()

        #expect(!vm.hasLoaded)
        #expect(!vm.isEmpty)

        await gate.open()
        await loadTask.value
    }

    /// **토글이 응답을 기다리는 도중 다시 바뀌면 나중 선택이 이긴다.** 주간 조회를 게이트로
    /// 붙잡아 둔 채 월간으로 넘어가 먼저 끝내고, 그다음에야 주간 응답을 흘려보낸다.
    /// `generation` 토큰이 없다면 뒤늦게 도착한 주간 응답이 월간 결과를 덮어썼을 것이다.
    @Test func 응답을_기다리는_도중_토글을_바꾸면_최신_선택이_이긴다() async {
        let service = FakeDietService()
        service.statsByFrom["2026-07-24"] = stats(recordedDays: 6) // 주간
        service.statsByFrom["2026-07-01"] = stats(recordedDays: 20) // 월간
        let gate = AsyncGate()
        service.statsGates["2026-07-24"] = gate
        let vm = DietStatsViewModel(service: service, today: today)

        let loadTask = Task { await vm.load() } // 주간 조회 — 게이트 안에서 멈춘다.
        await gate.waitUntilBlocked()

        await vm.select(.month) // 월간 조회는 게이트가 없어 곧바로 끝난다.
        #expect(vm.range == .month)
        #expect(vm.stats?.recordedDays == 20)

        await gate.open() // 이제야 주간 응답을 흘려보낸다.
        await loadTask.value

        #expect(vm.range == .month)
        #expect(vm.stats?.recordedDays == 20)
        #expect(service.statsRanges.count == 2)
        #expect(service.statsRanges.contains { $0.from == "2026-07-24" })
        #expect(service.statsRanges.contains { $0.from == "2026-07-01" })
    }
}
