import Foundation
import Observation

@MainActor
@Observable
final class PairViewModel {

    // MARK: - State

    var pairInfo: PairInfo?
    var inviteCode: String?
    var inputCode: String = ""
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Computed

    var isPaired: Bool {
        pairInfo?.status == .connected
    }

    var isPending: Bool {
        pairInfo?.status == .pending
    }

    // MARK: - Service

    private let pairService = PairService()

    // MARK: - Actions

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            pairInfo = try await pairService.getStatus()
        } catch {
            errorMessage = "페어 상태를 불러오지 못했습니다."
        }
    }

    func createInvite() async {
        errorMessage = nil
        do {
            let response = try await pairService.createInvite()
            inviteCode = response.inviteCode
            await loadStatus()
        } catch {
            errorMessage = "초대 코드 생성에 실패했습니다."
        }
    }

    func acceptInvite() async {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        errorMessage = nil
        do {
            let info = try await pairService.acceptInvite(code: code)
            pairInfo = info
            inputCode = ""
            inviteCode = nil
            successMessage = "페어링이 완료되었습니다!"
        } catch {
            errorMessage = "초대 코드가 올바르지 않습니다."
        }
    }

    func unpair() async {
        errorMessage = nil
        do {
            try await pairService.unpair()
            pairInfo = nil
            inviteCode = nil
            successMessage = "페어가 해제되었습니다."
        } catch {
            errorMessage = "페어 해제에 실패했습니다."
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
