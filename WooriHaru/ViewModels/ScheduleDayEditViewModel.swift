import Foundation

/// 날짜 하나의 근무를 고치는 폼. **역할마다 「아직 고르지 않음」이 따로 있다.**
///
/// 데이터에는 근무·휴무 말고 **미등록**(레코드 없음)이 있다. 아빠 배차표를 아직 안 올린
/// 달이 통째로 그 상태다. 미등록을 휴무로 미리 칠해 두면, 엄마만 고치려고 연 시트에서
/// 저장 한 번에 아빠의 그 달 첫 레코드가 사람이 고른 적 없는 「휴무」로 생긴다.
///
/// 그래서 선택 자체를 옵셔널로 둔다. nil인 역할은 요청에 실리지 않고 서버도 건드리지 않는다.
@MainActor
@Observable
final class ScheduleDayEditViewModel: Identifiable {
    enum Working: Equatable {
        case working
        case off
    }

    /// 아빠 순번 선택지. 실제로 쓰이는 값이 둘뿐이라 자유 입력을 열지 않는다 —
    /// 열면 숫자가 아닌 값과 오타를 거르는 검증이 따라붙는다.
    private static let baseFatherSlots = [1, 2]
    private static let baseMotherSlotCodes = ["A", "B", "C"]

    let date: String

    /// `8월 15일 (토)`처럼 이미 만들어진 제목. **여기서 날짜를 다시 계산하지 않는다** —
    /// 기기 달력이 비그레고리력이면 달력 칸과 시트 제목이 서로 다른 날을 가리킨다.
    let dayLabel: String

    /// `sheet(item:)`이 쓴다. 날짜가 곧 이 시트의 정체다.
    nonisolated var id: String { date }

    private let service: DispatchServing

    /// 시트를 열 때 받은 그날의 원본. **저장 성공 뒤 화면에 그릴 값을 여기서 만든다** —
    /// 서버가 204라 돌려주는 것이 없다. 손대지 않은 역할과 `note`가 여기서 나온다.
    private let originalDays: [DispatchShiftDay]

    var fatherWorking: Working? {
        didSet { if fatherWorking == .off { fatherSlot = nil } }
    }

    var motherWorking: Working? {
        didSet { if motherWorking == .off { motherSlotCode = nil } }
    }

    var fatherSlot: Int?
    var motherSlotCode: String?

    private(set) var fatherSlotOptions: [Int]
    private(set) var motherSlotCodeOptions: [String]

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init(
        date: String,
        dayLabel: String,
        days: [DispatchShiftDay],
        service: DispatchServing = DispatchService()
    ) {
        self.date = date
        self.dayLabel = dayLabel
        self.service = service
        self.originalDays = days

        let father = days.first { $0.role == .father }
        let mother = days.first { $0.role == .mother }

        self.fatherWorking = father.map { $0.working ? .working : .off }
        self.motherWorking = mother.map { $0.working ? .working : .off }
        self.fatherSlot = father?.slot
        self.motherSlotCode = mother?.slotCode

        // **저장된 값이 선택지에 없으면 함께 넣는다.** 사진 인식이 `3`을 넣어 둔 날을
        // 열었을 때 선택이 비어 보이면, 휴무만 고치려던 저장이 순번을 조용히 지운다.
        self.fatherSlotOptions = Self.options(base: Self.baseFatherSlots, current: father?.slot)
        self.motherSlotCodeOptions = Self.options(base: Self.baseMotherSlotCodes, current: mother?.slotCode)
    }

    /// 건드린 역할이 하나라도 있어야 보낼 것이 있다.
    var canSave: Bool {
        !isSaving && (fatherWorking != nil || motherWorking != nil)
    }

    /// 성공하면 **그 날짜의 최종 상태**를, 실패하면 nil을 준다.
    /// 실패해도 시트를 닫지 않으므로 화면은 `errorMessage`를 그대로 보여 준다.
    ///
    /// 서버는 204라 돌려주는 것이 없다. **두 역할이 한 트랜잭션이므로 204를 받으면 보낸
    /// 것이 전부 들어갔고**, 안 보낸 역할은 서버가 건드리지 않아 원본 그대로다. 그래서
    /// 최종 상태를 여기서 만들 수 있다.
    func save() async -> [DispatchShiftDay]? {
        guard canSave else { return nil }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let father = fatherWorking.map { edit(working: $0, slot: fatherSlot, slotCode: nil) }
        let mother = motherWorking.map { edit(working: $0, slot: nil, slotCode: motherSlotCode) }

        do {
            try await service.editDay(
                date: date,
                request: DispatchDayEditRequest(father: father, mother: mother)
            )
        } catch is CancellationError {
            return nil
        } catch {
            // 서버 메시지가 이미 사용자용 한국어다. 봉투 JSON째 보여주지 않는다.
            errorMessage = error.serverMessage ?? error.localizedDescription
            return nil
        }

        return [
            saved(role: .father, edit: father),
            saved(role: .mother, edit: mother)
        ].compactMap { $0 }
    }

    /// **휴무면 순번을 싣지 않는다.** 화면에서 이미 비우지만 여기서 한 번 더 못 박는다 —
    /// 두 곳이 어긋나면 휴무인데 순번이 남은 레코드가 생긴다.
    private func edit(working: Working, slot: Int?, slotCode: String?) -> DispatchRoleEdit {
        guard working == .working else {
            return DispatchRoleEdit(working: false, slot: nil, slotCode: nil)
        }
        return DispatchRoleEdit(working: true, slot: slot, slotCode: slotCode)
    }

    /// 저장 뒤 그 역할의 상태. 보낸 적이 없으면 원본을 그대로 쓰고, 원본도 없으면
    /// **레코드가 없는 것이다** — 없는 것을 휴무로 만들어 두면 달력이 거짓말을 한다.
    ///
    /// `note`는 원본에서 가져온다. 이 경로는 `note`를 보내지 않고 서버도 건드리지 않으므로,
    /// 화면 값에서만 지우면 다음 조회에 되살아나 잠깐 사라졌다 돌아오는 것처럼 보인다.
    private func saved(role: DispatchRole, edit: DispatchRoleEdit?) -> DispatchShiftDay? {
        let original = originalDays.first { $0.role == role }
        guard let edit else { return original }
        return DispatchShiftDay(
            date: date,
            role: role,
            working: edit.working,
            slot: edit.slot,
            slotCode: edit.slotCode,
            note: original?.note
        )
    }

    private static func options<T: Equatable>(base: [T], current: T?) -> [T] {
        guard let current, !base.contains(current) else { return base }
        return base + [current]
    }
}
