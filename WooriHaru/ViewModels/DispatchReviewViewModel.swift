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
        /// `"토"`. 사진의 표가 요일 머리글로 정렬돼 있어 대조할 때 실제로 쓰인다.
        /// 연월을 못 읽으면 빈 문자열이다.
        let weekday: String
        var recognized: Bool
        var working: Bool
        var slot: Int?
        var note: String?
        var conflict: Bool
    }

    private let recognition: DispatchRecognition
    private let service: DispatchServing
    private let calendar: Calendar

    /// **사진에서 못 읽었으면 빈 문자열이다.** 사람이 채우기 전에는 저장할 수 없다 —
    /// 어느 달인지 모르면 `2026-08-01` 같은 날짜를 만들 수 없다.
    private(set) var yearMonth: String

    private(set) var entries: [DayEntry] = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    init(
        recognition: DispatchRecognition,
        service: DispatchServing = DispatchService(),
        calendar: Calendar = .dispatchGregorian
    ) {
        self.recognition = recognition
        self.service = service
        self.calendar = calendar
        self.yearMonth = recognition.yearMonth ?? ""
        self.entries = Self.buildEntries(from: recognition, yearMonth: recognition.yearMonth, calendar: calendar)
    }

    /// 화면이 형식 오류를 알리고 저장을 잠그는 데 쓴다.
    var isYearMonthValid: Bool {
        Self.isValidYearMonth(yearMonth)
    }

    /// `^\d{4}-(0[1-9]|1[0-2])$`. **월에 0을 채워야 한다** — `2026-3`·`2026-13`은
    /// 서버의 `YearMonth` 파싱이 400을 낸다.
    static func isValidYearMonth(_ value: String) -> Bool {
        value.range(of: "^[0-9]{4}-(0[1-9]|1[0-2])$", options: .regularExpression) != nil
    }

    /// 연월이 정해지면 **요일과 말일이 따라온다.** 고쳐 둔 값은 날짜 기준으로 옮겨 살린다 —
    /// 연월을 나중에 채운다고 검수한 내용이 날아가면 처음부터 다시 해야 한다.
    func setYearMonth(_ value: String) {
        yearMonth = value
        guard Self.isValidYearMonth(value) else { return }

        let existing = Dictionary(entries.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let rebuilt = Self.buildEntries(from: recognition, yearMonth: value, calendar: calendar)
        entries = rebuilt.map { entry in
            guard let kept = existing[entry.day] else { return entry }
            let merged = kept
            // 요일만 새 연월 기준으로 갈아 끼운다.
            return DayEntry(
                day: merged.day,
                weekday: entry.weekday,
                recognized: merged.recognized,
                working: merged.working,
                slot: merged.slot,
                note: merged.note,
                conflict: merged.conflict
            )
        }
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
            case "ROSTER_FROM_OTHER_MONTH":
                return "저장된 줄 위치를 다른 달 것으로 맞췄습니다. 순번이 밀리지 않았는지 사진과 대조해 주세요."
            default:
                return code
            }
        }
    }

    func setWorking(day: Int, working: Bool, slot: Int?) {
        guard let index = entries.firstIndex(where: { $0.day == day }) else { return }
        // **사람이 인식값을 고쳤으면 `note`를 버린다.** `note`는 사람이 방금 틀렸다고 판정한
        // 바로 그 칸에서 나온 원문이다. 남겨 두면 `working: true, slot: 1, note: "휴"`가
        // 저장되고, 웹 달력이 근무 뱃지에 원문을 덧붙여 「1번 휴」로 찍힌다. 순번만 고친
        // 경우도 같다 — `note: "*97"`인 근무를 「2번」으로 고쳐도 검수 화면 라벨이 원문을
        // 우선해 여전히 `*97`로 보이고, 저장에는 고친 순번과 낡은 원문이 함께 실린다.
        // 인식값을 그대로 확정한 경우엔 `간담회` 같은 원문이 쓸모 있으므로 남긴다.
        if entries[index].working != working || entries[index].slot != slot {
            entries[index].note = nil
        }
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

    /// 보낼 날짜가 하나라도 있고 연월도 정해졌는가. 화면은 이 값으로 저장 버튼을 잠근다.
    var canSave: Bool {
        entries.contains(where: \.recognized) && isYearMonthValid
    }

    func save() async {
        guard !isSaving else { return }
        // 서버 `ShiftSaveRequest.days`에 `@NotEmpty`가 걸려 있다. 모든 날을 「미인식으로
        // 두기」로 돌리거나 인식 결과가 비어 오면 빈 배열이 나가 400을 받는다. 연월을 모르면
        // 애초에 `2026-08-01` 같은 날짜를 만들 수 없다.
        guard canSave else {
            errorMessage = isYearMonthValid
                ? "저장할 날짜가 없습니다. 한 날 이상 값을 정해 주세요."
                : "연월을 2026-08처럼 적어 주세요."
            return
        }
        isSaving = true
        errorMessage = nil
        // 첫 저장이 성공한 뒤 값을 고쳐 다시 저장했다가 실패하면, 이 값이 남아 있어
        // 화면이 「저장됨」과 오류를 동시에 보여준다.
        didSave = false

        let days = entries
            .filter(\.recognized)
            .map { entry in
                DispatchShiftSaveDay(
                    date: String(format: "%@-%02d", yearMonth, entry.day),
                    working: entry.working,
                    slot: entry.slot,
                    note: entry.note
                )
            }

        do {
            try await service.saveShifts(DispatchShiftSaveRequest(role: "FATHER", days: days))
            didSave = true
        } catch {
            // 봉투 JSON째 보여주지 않는다 — `APIError.serverError`의 message에는 본문 전체가 실린다.
            errorMessage = error.serverMessage ?? error.localizedDescription
        }
        isSaving = false
    }

    private static func buildEntries(
        from recognition: DispatchRecognition,
        yearMonth: String?,
        calendar: Calendar
    ) -> [DayEntry] {
        // `uniqueKeysWithValues`는 같은 키가 두 번 오면 **크래시한다.** 서버가 중복 `day`를
        // 주는 일은 없어야 하지만, 모델 응답 하나 때문에 검수 화면이 죽는 것보다는
        // 뒤에 온 값을 쓰는 편이 낫다.
        let recognizedByDay = Dictionary(recognition.days.map { ($0.day, $0) }, uniquingKeysWith: { _, latest in latest })
        let parsed = yearMonth.flatMap(Self.parseYearMonth)
        // 연월을 모르면 며칠까지인지도 모른다. 넉넉히 31일로 두면 사진에 있던 날이 사라지지 않는다.
        let dayCount = Self.dayCount(of: parsed, calendar: calendar)

        return (1...dayCount).map { day in
            let weekday = Self.weekdaySymbol(of: parsed, day: day, calendar: calendar)
            if let recognized = recognizedByDay[day] {
                return DayEntry(
                    day: day,
                    weekday: weekday,
                    recognized: true,
                    working: recognized.working,
                    slot: recognized.slot,
                    note: recognized.note,
                    conflict: recognized.conflict
                )
            }
            return DayEntry(
                day: day,
                weekday: weekday,
                recognized: false,
                working: false,
                slot: nil,
                note: nil,
                conflict: false
            )
        }
    }

    private static func parseYearMonth(_ yearMonth: String) -> (year: Int, month: Int)? {
        let parts = yearMonth.split(separator: "-")
        guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return (year, month)
    }

    private static func dayCount(of yearMonth: (year: Int, month: Int)?, calendar: Calendar) -> Int {
        guard let yearMonth,
              let date = calendar.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: date)
        else {
            return 31
        }
        return range.count
    }

    /// 로케일에 기대지 않고 고정 표기를 쓴다 — 기기 언어가 무엇이든 사진의 한글 요일 머리글과
    /// 맞아야 대조가 된다. `Calendar`는 주입받은 것을 그대로 쓴다(테스트가 시계에 안 묶인다).
    private static let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]

    private static func weekdaySymbol(of yearMonth: (year: Int, month: Int)?, day: Int, calendar: Calendar) -> String {
        guard let yearMonth,
              let date = calendar.date(from: DateComponents(year: yearMonth.year, month: yearMonth.month, day: day))
        else {
            return ""
        }
        let weekday = calendar.component(.weekday, from: date)
        guard weekdaySymbols.indices.contains(weekday - 1) else { return "" }
        return weekdaySymbols[weekday - 1]
    }
}
