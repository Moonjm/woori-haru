import Foundation

/// 달력에 표시할 대상. **실명을 쓰지 않는다** — 무인증 조회로 나가는 값이다.
enum DispatchRole: String, Codable, Equatable {
    case father = "FATHER"
    case mother = "MOTHER"
}

/// 조회된 하루. 엄마는 패턴에서 계산돼 내려오므로 `slot`이 늘 nil이다.
struct DispatchShiftDay: Codable, Equatable {
    /// `2026-08-01` 형식.
    let date: String
    let role: DispatchRole
    /// 그날 일하는가. **판정은 이 값만 본다** — `slot`이 nil이어도 근무일 수 있다.
    let working: Bool
    /// 아빠 배차 순번. 엄마는 늘 nil이다.
    let slot: Int?
    /// 엄마 근무조(`A`·`B`·`C`). 아빠는 늘 nil이고, 패턴에서 만들어진 엄마 기본값도 nil이다.
    ///
    /// **옵셔널로 두어 이 키가 없는 응답도 받는다.** 서버가 내려주기 전에 앱이 먼저
    /// 배포될 수 있고, 그때 디코딩이 통째로 실패하면 달력이 빈다.
    let slotCode: String?
    /// 칸의 원문. 달력에는 쓰지 않는다 — 무인증 응답에 실려 나가는 자유 입력이다.
    let note: String?
}

struct DispatchShiftRange: Codable, Equatable {
    let days: [DispatchShiftDay]
}

/// 서버가 대상 행을 어떻게 찾았는지.
///
/// `rowIndex`면 **사진에 성명 컬럼이 없어 저장된 행 위치로 맞춘 것**이라, 검수 화면이
/// 그 사실을 알려야 한다. 인원이 바뀌어 행 순서가 밀리면 엉뚱한 기사의 근무가 들어오는데
/// 화면만 봐서는 구분되지 않기 때문이다.
// `DataResponse<T: Codable>`로 감싸 받으므로 Decodable만으로는 부족하다.
enum DispatchMatchedBy: String, Codable, Equatable {
    case name = "NAME"
    case rowIndex = "ROW_INDEX"
}

/// 사진에서 읽은 하루. **`days`에는 사진에 보인 날짜만 들어온다** — 잘린 사진이면 일부만 온다.
struct DispatchRecognitionDay: Codable, Equatable {
    let day: Int
    /// 그날 일하는가. **판정은 이 값만 본다** — `slot`이 nil이어도 근무일 수 있다.
    let working: Bool
    /// 배차 순번. 근무여도 미정이면 nil.
    let slot: Int?
    /// 칸의 원문(`휴`·`간담회`·`*97` 등). 표시용이고 판정에 끼어들지 않는다.
    let note: String?
    /// 겹친 구간에서 두 조각의 답이 갈렸다. 화면이 강조한다.
    let conflict: Bool
}

struct DispatchRecognition: Codable, Equatable {
    /// 사진 제목이 잘려 서버가 못 읽으면 nil이다. **검수 화면이 채운다.**
    let yearMonth: String?
    let hasNameColumn: Bool
    let matchedBy: DispatchMatchedBy
    let rowIndex: Int
    let rowCount: Int
    /// `ROW_COUNT_CHANGED`, `YEAR_MONTH_MISMATCH` 등. 비어 있을 수 있다.
    let warnings: [String]
    let days: [DispatchRecognitionDay]
}

struct DispatchShiftSaveDay: Encodable, Equatable {
    /// `2026-08-01` 형식. 서버가 `LocalDate`로 받는다.
    let date: String
    let working: Bool
    let slot: Int?
    /// **개인 식별 정보를 넣지 않는다** — 무인증 조회로 그대로 나간다. 서버 한도 100자.
    let note: String?
}

struct DispatchShiftSaveRequest: Encodable {
    /// 지금은 항상 `FATHER`다. 사진에서 읽는 대상이 아빠뿐이다.
    let role: String
    let days: [DispatchShiftSaveDay]
}

/// 하루 편집에서 역할 하나를 어떻게 바꿀지.
///
/// **아빠는 `slot`, 엄마는 `slotCode`다.** 한 필드에 정수와 문자를 겹쳐 담지 않는다 —
/// `A`를 `1`로 접으면 같은 숫자의 뜻이 역할마다 갈리고, 엄마 순번이 늘어나는 순간 무너진다.
/// 역할에 맞지 않는 필드를 보내면 서버가 400을 낸다.
///
/// **휴무면 순번을 싣지 않는다.** 서버도 `working: false`면 순번을 nil로 눕히지만,
/// 보내는 쪽에서 맞춰야 「보낸 값 = 저장된 값」이 깨지지 않는다.
struct DispatchRoleEdit: Encodable, Equatable {
    let working: Bool
    let slot: Int?
    let slotCode: String?
}

/// 날짜 하나의 편집 요청. **손대지 않은 역할은 nil로 두어 아예 보내지 않는다.**
///
/// 아빠 배차표를 아직 안 올린 달에 엄마만 고칠 때 아빠까지 값을 실어 보내면, 사람이 고른
/// 적 없는 「휴무」가 그 달 아빠의 첫 레코드로 생긴다. 「저장된 적 없음」과 「휴무」는
/// 조회에서 이미 갈리는 상태다.
///
/// `JSONEncoder`는 nil 프로퍼티의 키를 아예 빼므로 따로 처리할 것이 없다.
struct DispatchDayEditRequest: Encodable, Equatable {
    let father: DispatchRoleEdit?
    let mother: DispatchRoleEdit?
}

extension Calendar {
    /// 서버로 나가는 `yearMonth`·`date`는 ISO 그레고리력 문자열이다. `Calendar.current`는
    /// 기기 설정을 따르므로 달력을 불교력으로 둔 기기에서는 오늘이 **`2026-08`이 아니라
    /// `2569-08`**로 만들어진다. 형식 검사는 이 값을 통과시키고 서버는 그대로 ISO로 읽어,
    /// 엉뚱한 연도를 인식하고 저장한다. 말일·요일 계산도 같은 이유로 여기에 맞춘다.
    ///
    /// **시간대를 명시한다.** `Calendar(identifier:)`의 시간대 기본값은 문서화돼 있지 않다.
    /// 실측으로는 기기 시간대를 물려받지만, 그것이 GMT로 바뀌면 한국에서 매달 1일 오전 9시
    /// 이전에 「오늘」이 지난달로 계산돼 **스케줄표가 지난달을 연다.** 기대지 않고 못 박는다.
    static let dispatchGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()
}
