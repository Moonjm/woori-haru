import Foundation
import Observation

@MainActor @Observable
final class VisitorCarRegisterViewModel {
    var carNo = ""
    var startDate = Date()
    var endDate = Date()
    var visitReason = ""

    private(set) var errorMessage: String?
    private(set) var isSubmitting = false
    private(set) var didSucceed = false

    private let service: any VisitorCarServing

    init(service: any VisitorCarServing = VisitorCarService.shared) {
        self.service = service
    }

    /// 사용자가 무언가 치기 시작한 뒤에만 짚어 준다 — **빈 화면을 처음부터 혼내지 않는다.**
    var validationError: String? {
        if carNo.isEmpty { return nil }
        if let error = VisitorCarValidation.carNoError(carNo) { return error }
        return VisitorCarValidation.periodError(start: startDate, end: endDate)
    }

    var canSubmit: Bool {
        !isSubmitting
            && VisitorCarValidation.carNoError(carNo) == nil
            && VisitorCarValidation.periodError(start: startDate, end: endDate) == nil
    }

    func apply(_ car: FrequentCar) {
        carNo = car.carNo
    }

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await service.register(
                VisitorCarRegisterRequest(
                    carNo: carNo,
                    startDate: startDate,
                    endDate: endDate,
                    visitReason: visitReason
                )
            )
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
