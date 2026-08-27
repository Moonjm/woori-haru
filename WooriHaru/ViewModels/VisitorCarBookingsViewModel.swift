import Foundation
import Observation

@MainActor @Observable
final class VisitorCarBookingsViewModel {
    var from: Date
    var to: Date

    private(set) var bookings: [VisitorCarBooking] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    private(set) var hasMore = false

    private let service: any VisitorCarServing
    private let pageSize = 10
    private var loadedPage = 0

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let today = Date()
        // 방문 예약은 앞날을 잡는 일이다 — 지난 달을 기본으로 보여줄 이유가 없다.
        self.from = today
        self.to = calendar.date(byAdding: .month, value: 1, to: today) ?? today
    }

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

    /// 편집 모드로 들어갈 때 부른다. 조회·편집 모드가 같은 자리에 오류 문구를 그리므로,
    /// 지우지 않으면 직전 실패(예: 삭제 거절)의 문구가 아직 아무것도 보내지 않은 편집 폼
    /// 아래에 그대로 남는다.
    func clearError() {
        errorMessage = nil
    }

    /// - Returns: 실제로 지워졌으면 `true`. 서버가 거절하면 `false`이고 문구는 `errorMessage`에 남는다.
    func delete(id: Int) async -> Bool {
        errorMessage = nil
        do {
            try await service.delete(id: id)
            bookings.removeAll { $0.id == id }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// - Returns: 실제로 바뀌었으면 `true`. 검증에 걸리거나 서버가 거절하면 `false`이고
    ///   문구는 `errorMessage`에 남는다.
    func update(
        id: Int,
        carNo: String,
        startDate: Date,
        endDate: Date,
        visitReason: String
    ) async -> Bool {
        errorMessage = nil

        // 등록 화면과 같은 규칙으로 먼저 막는다 — 잘못된 번호를 서버까지 보낼 이유가 없다.
        if let error = VisitorCarValidation.carNoError(carNo) {
            errorMessage = error
            return false
        }
        if let error = VisitorCarValidation.periodError(start: startDate, end: endDate) {
            errorMessage = error
            return false
        }

        do {
            try await service.update(
                id: id,
                VisitorCarRegisterRequest(
                    carNo: carNo,
                    startDate: startDate,
                    endDate: endDate,
                    visitReason: visitReason
                )
            )
            // **결과를 손으로 기워 넣지 않는다.** 서버가 무엇을 바꿨는지(시각 보정 등)
            // 우리가 모르므로 다시 읽어 확인한다.
            await search()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// - Parameter replacing: `true`면 `bookings`를 통째로 갈아 끼운다(재조회 0쪽).
    ///   `false`면 뒤에 잇는다(더 보기). **성공했을 때만** 반영한다 — 실패하면 이전 목록을
    ///   그대로 두고 `errorMessage`만 세운다.
    private func fetch(page: Int, replacing: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.bookings(
                from: from, to: to, carNo: "", page: page, size: pageSize
            )
            if replacing {
                bookings = result.content
            } else {
                bookings.append(contentsOf: result.content)
            }
            loadedPage = result.number
            hasMore = !result.last
        } catch {
            errorMessage = error.localizedDescription
            // 실패한 페이지는 없는 셈이다 — 「더 보기」를 남겨 두면 잘못된 다음 페이지를 부른다.
            hasMore = false
        }
    }
}
