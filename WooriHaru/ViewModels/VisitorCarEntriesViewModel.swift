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

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let today = Date()
        // 「지금 들어와 있나」가 이 화면의 질문이다 — 오늘 하루로 연다.
        self.from = calendar.startOfDay(for: today)
        self.to = calendar.date(byAdding: .second, value: 86_399, to: calendar.startOfDay(for: today)) ?? today
    }

    static func parkingText(seconds: TimeInterval) -> String {
        // 기기 시계가 어긋나면 음수가 나온다. 「-1시간 주차」는 뜻이 없다.
        let total = Int(max(0, seconds))
        return "\(total / 3600)시간 \((total % 3600) / 60)분"
    }

    func tick() { now = Date() }

    func search() async {
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
                from: from, to: to, carNo: "", page: page, size: pageSize
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
