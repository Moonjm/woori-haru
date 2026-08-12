import Foundation

/// 인식 결과를 사진과 대조해 고치고 확정한다.
///
/// **그 달 전체를 보여주되 사진에 없던 날은 「미인식」으로 둔다.** 잘린 변경분 사진은 그 달의
/// 일부만 담으므로 `days`에 일부만 온다. 미인식 날짜를 휴무로 채워 보내면 서버가 그대로
/// upsert해 **멀쩡한 기존 값이 휴무로 덮인다.**
@MainActor
@Observable
final class DispatchReviewViewModel {
    /// 화면 한 줄. `recognized == false`면 저장에서 빠진다.
    struct DayEntry: Identifiable, Equatable {
        var id: Int { day }
        let day: Int
        var recognized: Bool
        var working: Bool
        var slot: Int?
        var note: String?
        var conflict: Bool
    }

    private let recognition: DispatchRecognition
    private let service: DispatchServing

    private(set) var entries: [DayEntry] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    init(
        recognition: DispatchRecognition,
        service: DispatchServing = DispatchService(),
        calendar: Calendar = .current
    ) {
        self.recognition = recognition
        self.service = service
        self.entries = Self.buildEntries(from: recognition, calendar: calendar)
    }

    /// 성명 컬럼이 없어 저장된 행 위치로 맞춘 경우. 인원이 바뀌어 행이 밀리면 엉뚱한 기사의
    /// 근무가 들어오는데 화면만 봐서는 구분되지 않으므로, 사진과 대조하라고 알린다.
    var needsRowIndexWarning: Bool {
        recognition.matchedBy == .rowIndex
    }

    var warningMessages: [String] {
        recognition.warnings.map { code in
            switch code {
            case "ROW_COUNT_CHANGED":
                return "배차표 인원이 지난번과 다릅니다. 줄이 밀리지 않았는지 사진과 대조해 주세요."
            case "YEAR_MONTH_MISMATCH":
                return "사진의 달이 고른 달과 다릅니다. 연월을 확인해 주세요."
            default:
                return code
            }
        }
    }

    func setWorking(day: Int, working: Bool, slot: Int?) {
        guard let index = entries.firstIndex(where: { $0.day == day }) else { return }
        entries[index].recognized = true
        entries[index].working = working
        entries[index].slot = slot
        // 사람이 값을 정했으면 조각 간 불일치는 해소된 것이다.
        entries[index].conflict = false
    }

    /// 저장 대상에서 뺀다. 서버는 보낸 날짜만 갱신하므로 기존 값이 그대로 남는다.
    func markUnrecognized(day: Int) {
        guard let index = entries.firstIndex(where: { $0.day == day }) else { return }
        entries[index].recognized = false
        entries[index].conflict = false
    }

    func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        // 첫 저장이 성공한 뒤 값을 고쳐 다시 저장했다가 실패하면, 이 값이 남아 있어
        // 화면이 「저장됨」과 오류를 동시에 보여준다.
        didSave = false

        let days = entries
            .filter(\.recognized)
            .map { entry in
                DispatchShiftSaveDay(
                    date: String(format: "%@-%02d", recognition.yearMonth, entry.day),
                    working: entry.working,
                    slot: entry.slot,
                    note: entry.note
                )
            }

        do {
            try await service.saveShifts(DispatchShiftSaveRequest(role: "FATHER", days: days))
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private static func buildEntries(from recognition: DispatchRecognition, calendar: Calendar) -> [DayEntry] {
        // `uniqueKeysWithValues`는 같은 키가 두 번 오면 **크래시한다.** 서버가 중복 `day`를
        // 주는 일은 없어야 하지만, 모델 응답 하나 때문에 검수 화면이 죽는 것보다는
        // 뒤에 온 값을 쓰는 편이 낫다.
        let recognizedByDay = Dictionary(recognition.days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let dayCount = Self.dayCount(of: recognition.yearMonth, calendar: calendar)

        return (1...dayCount).map { day in
            if let recognized = recognizedByDay[day] {
                return DayEntry(
                    day: day,
                    recognized: true,
                    working: recognized.working,
                    slot: recognized.slot,
                    note: recognized.note,
                    conflict: recognized.conflict
                )
            }
            return DayEntry(day: day, recognized: false, working: false, slot: nil, note: nil, conflict: false)
        }
    }

    private static func dayCount(of yearMonth: String, calendar: Calendar) -> Int {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }
}
