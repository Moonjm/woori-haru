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
        loadedPage = 0
        bookings = []
        await fetch(page: 0)
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        await fetch(page: loadedPage + 1)
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

    private func fetch(page: Int) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await service.bookings(
                from: from, to: to, carNo: "", page: page, size: pageSize
            )
            bookings.append(contentsOf: result.content)
            loadedPage = result.number
            hasMore = !result.last
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
