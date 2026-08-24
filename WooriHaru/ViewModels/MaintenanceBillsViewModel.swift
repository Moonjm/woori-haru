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

    /// 목록을 건드릴 때마다 올린다. 최초 `.task` 로딩, 당겨서 새로고침, 저장·삭제 뒤
    /// 재로딩은 **서로 겹칠 수 있고**, 먼저 시작한 요청이 나중에 끝날 수 있다. 그대로
    /// 두면 **저장 전에 찍힌 스냅샷**이 마지막에 들어와 방금 등록한 달이 사라져 보인다.
    /// (`MaintenanceUploadViewModel.generation`과 같은 장치다.)
    private var generation = 0

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        errorMessage = nil
        // **내가 아직 최신일 때만 스피너를 내린다.** 늦게 끝난 옛 요청이 끄면 뒤이어
        // 도는 새 요청의 스피너까지 사라진다.
        defer { if token == generation { isLoading = false } }
        do {
            let received = try await service.fetchBills()
            // 도는 사이에 더 새로운 로딩이나 삭제가 있었다. 이 결과는 이미 낡았다.
            guard token == generation else { return }
            bills = received
        } catch is CancellationError {
            // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
            return
        } catch {
            // 낡은 요청의 실패로 새 요청의 화면에 오류를 띄우지 않는다.
            guard token == generation else { return }
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
            // **여기서도 세대를 올린다.** 삭제 전에 시작된 로딩이 뒤늦게 돌아오면 지운 달이
            // 든 목록으로 덮여 **방금 지운 달이 되살아난다.**
            generation += 1
            // **올린 다음에는 스피너를 직접 내려야 한다.** 방금 무효화한 그 로딩은
            // `defer`에서 「나는 이미 낡았다」며 `isLoading`을 건드리지 않고, 삭제는 새
            // 로딩을 띄우지 않는다 — 아무도 안 내리면 스피너가 영영 남고, **마지막 달을
            // 지웠을 때 빈 상태가 그 뒤에 가려 안 뜬다.**
            isLoading = false
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
