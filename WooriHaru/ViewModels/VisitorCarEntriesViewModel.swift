import Foundation
import Observation

@MainActor @Observable
final class VisitorCarEntriesViewModel {
    var from: Date
    var to: Date

    private(set) var entries: [VisitorCarEntry] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var hasMore = false
    /// 주차시간을 세는 기준. **아직 안 나간 차는 이 값이 밀릴 때마다 늘어난다.**
    private(set) var now = Date()

    private let service: any VisitorCarServing
    private let pageSize = 10
    private var loadedPage = 0

    /// **마지막으로 제출한 조회 조건.** `from`·`to`는 픽커가 자유롭게 바꿀 수 있어서
    /// `loadMore()`가 그 값을 그대로 읽으면 다른 기간이 섞인다 — `search()`가 실제로
    /// 서버에 보낸 기간을 여기 붙잡아 두고, `fetch()`는 이 값만 쓴다.
    private var searchedFrom: Date
    private var searchedTo: Date

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let today = Date()
        // 「지금 들어와 있나」가 이 화면의 질문이다 — 오늘 하루로 연다.
        let initialFrom = calendar.startOfDay(for: today)
        let initialTo = calendar.date(byAdding: .second, value: 86_399, to: initialFrom) ?? today
        self.from = initialFrom
        self.to = initialTo
        self.searchedFrom = initialFrom
        self.searchedTo = initialTo
    }

    static func parkingText(seconds: TimeInterval) -> String {
        // 기기 시계가 어긋나면 음수가 나온다. 「-1시간 주차」는 뜻이 없다.
        let total = Int(max(0, seconds))
        return "\(total / 3600)시간 \((total % 3600) / 60)분"
    }

    func tick() { now = Date() }

    func search() async {
        // 선택기가 기간을 역전으로 두게 둘 수 있다(둘 다 `in:` 제약이 없다). 역전 기간을
        // 그대로 보내면 서버가 오류를 주거나, 더 나쁘게는 빈 목록을 줘서 「입출차 내역이
        // 사라졌다」는 오해를 산다 — 여기서 먼저 막는다.
        //
        // **`periodError`가 아니라 `timeRangeError`를 쓴다(P2).** 이 화면의 피커는
        // 시·분까지 받고, `entries()`가 그 정확한 시각을 그대로 서버에 보낸다.
        // `periodError`는 날짜만 견주므로 같은 날 안에서 시각이 거꾸로면(예: 18:00 →
        // 09:00, 기본 범위가 오늘 00:00~23:59이니 「오후만」으로 좁히면 곧바로 만난다)
        // 통과시켜 버린다 — 등록·예약 조회(날짜만 고르는 화면)를 위한 규칙을 시각까지
        // 다루는 이 화면에 그대로 쓰면 안 된다.
        if let error = VisitorCarValidation.timeRangeError(start: from, end: to) {
            errorMessage = error
            return
        }

        // **제출한 조건을 스냅샷한다.** 사용자가 조회 뒤에 픽커를 다음 조회를 위해
        // 미리 바꿔 둘 수 있다 — 그건 막을 일이 아니다. 막아야 하는 건 `loadMore()`가
        // 그 새 값을 이번 조회의 다음 페이지로 착각해 다른 기간 결과를 이어 붙이는 것이다.
        searchedFrom = from
        searchedTo = to

        // **처음부터 채운다.** 이어 붙이면 조건이 바뀐 결과와 섞인다.
        // **단, 성공했을 때만 갈아 끼운다** — 재조회가 실패하면(일시적 끊김 등) 이전 목록을
        // 지우지 않는다. 지워 버리면 「저장은 됐는데 목록이 텅 비어 보이는」 상황이 생긴다.
        await fetch(page: 0, replacing: true)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(page: loadedPage + 1, replacing: false)
    }

    /// - Parameter replacing: `true`면 `entries`를 통째로 갈아 끼운다(재조회 0쪽).
    ///   `false`면 뒤에 잇는다(더 보기). **성공했을 때만** 반영한다 — 실패하면 이전 목록을
    ///   그대로 두고 `errorMessage`만 세운다.
    private func fetch(page: Int, replacing: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.entries(
                from: searchedFrom, to: searchedTo, carNo: "", page: page, size: pageSize
            )
            if replacing {
                entries = result.content
            } else {
                entries.append(contentsOf: result.content)
            }
            loadedPage = result.number
            hasMore = !result.last
            now = Date()
        } catch {
            errorMessage = error.localizedDescription
            // 실패한 페이지는 없는 셈이다 — 「더 보기」를 남겨 두면 잘못된 다음 페이지를 부른다.
            hasMore = false
        }
    }
}
