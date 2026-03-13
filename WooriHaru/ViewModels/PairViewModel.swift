import Foundation
import Observation

@MainActor
@Observable
final class PairViewModel {
    var inviteCode: String?
    var inputCode: String = ""
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    private let pairStore: PairStore

    init(pairStore: PairStore) {
        self.pairStore = pairStore
    }

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await pairStore.loadStatus()
        } catch {
            errorMessage = "페어 상태를 불러오지 못했습니다."
        }
    }

    func createInvite() async {
        errorMessage = nil
        do {
            inviteCode = try await pairStore.createInvite()
        } catch {
            errorMessage = "초대 코드 생성에 실패했습니다."
        }
    }

    func acceptInvite() async {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        errorMessage = nil
        do {
            try await pairStore.acceptInvite(code: code)
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
            try await pairStore.unpair()
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
