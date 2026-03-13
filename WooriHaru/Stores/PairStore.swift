import Foundation
import Observation

@MainActor
@Observable
final class PairStore {
    private(set) var pairInfo: PairInfo?
    private let service = PairService()

    var isPaired: Bool { pairInfo?.status == .connected }
    var isPending: Bool { pairInfo?.status == .pending }
    var partnerName: String { pairInfo?.partnerName ?? "파트너" }

    func loadStatus() async throws {
        pairInfo = try await service.getStatus()
    }

    func createInvite() async throws -> String {
        let response = try await service.createInvite()
        try await loadStatus()
        return response.inviteCode
    }

    func acceptInvite(code: String) async throws {
        pairInfo = try await service.acceptInvite(code: code)
    }

    func unpair() async throws {
        try await service.unpair()
        pairInfo = nil
    }
}
