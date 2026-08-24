import Foundation

/// 관리비 내역 목록. 상세는 화면이 `MaintenanceBill`을 그대로 들고 가고, 필요할 때만
/// 서버에서 다시 받는다 — 목록 응답이 이미 상세와 같은 필드를 다 갖고 있다.
@MainActor
@Observable
final class MaintenanceBillsViewModel {
    private let service: any MaintenanceServing

    private(set) var bills: [MaintenanceBill] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(service: any MaintenanceServing = MaintenanceService()) {
        self.service = service
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            bills = try await service.fetchBills()
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // **이미 받아 둔 목록을 지우지 않는다** — 새로고침 한 번 실패했다고 화면이 비면,
            // 사용자는 등록한 달이 사라진 줄 안다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
    }

    /// 성공하면 true. **화면은 이 값을 보고 물러난다** — 실패했는데 물러나면 지워진 줄 안다.
    ///
    /// 상세 화면(`MaintenanceBillDetailView`)이 `deleteTask`를 `onDisappear`에서 취소한다 —
    /// 사용자가 삭제 도중 화면을 떠난 것이다. **`CancellationError`를 따로 걸러야 한다** —
    /// 걸러 내지 않으면 이 뷰모델은 상세 화면이 사라진 뒤에도 살아 있는 목록 화면의
    /// 것이라, `errorMessage`에 영문 시스템 메시지가 남아 방금 화면을 떠났을 뿐인
    /// 사용자에게 목록 화면에서 알 수 없는 오류가 뜬다.
    func delete(yearMonth: String) async -> Bool {
        errorMessage = nil
        do {
            try await service.deleteBill(yearMonth: yearMonth)
            bills.removeAll { $0.yearMonth == yearMonth }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.serverMessage ?? error.localizedDescription
            return false
        }
    }
}
