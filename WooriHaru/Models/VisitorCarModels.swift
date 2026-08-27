import Foundation
import SwiftUI

// MARK: - 날짜

/// 사이트가 요구하는 날짜 문자열. **엔드포인트별로 형식이 다르다** —
/// 등록 내역·등록 폼은 날짜만, 진입 현황은 시각까지다. 날짜만 보내면 진입 현황이 500으로 죽는다.
/// 하나로 합치려는 순간 한쪽이 조용히 깨지므로 둘로 나눠 둔다.
enum VisitorCarDateFormat {
    /// 주차장은 한국에 있다 — 이 기능이 다루는 모든 날짜·시각의 기준은 기기 시간대가
    /// 아니라 **여기 하나**다. 포맷터도, 기간 검증도, 날짜 선택기도 이 값을 따라야
    /// 「사용자가 고른 날」과 「서버로 보낸 날」이 갈리지 않는다.
    static let seoulTimeZone = TimeZone(identifier: "Asia/Seoul")!
    static let seoulCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoulTimeZone
        return calendar
    }()

    static let day = make("yyyy-MM-dd")
    static let second = make("yyyy-MM-dd HH:mm:ss")

    /// 서버는 한국 시각으로만 말한다. 기기 시간대에 끌려가면 자정 근처에서 하루가 어긋난다.
    private static func make(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = seoulTimeZone
        formatter.dateFormat = format
        return formatter
    }
}

extension View {
    /// `DatePicker`가 표시·조작하는 값은 `\.timeZone`·`\.calendar` 두 환경값을 함께 읽는다 —
    /// 하나만 주면 나머지는 기기 값으로 남아 둘이 어긋난다.
    ///
    /// **이게 없으면 벌어지는 일 (LA, 서울보다 16시간 느림):** 사용자가 선택기에서
    /// 「2026-07-18 09:00」을 골라도, 그 순간의 절대 시각은 서울 기준 이미 다음 날이라
    /// `VisitorCarDateFormat`이 `2026-07-19`로 실어 보낸다. LA 하루 대부분이 다음 한국
    /// 날짜로 넘어간다 — 해외에서 방문차량을 등록하면 조용히 하루 밀린 날짜가 저장된다.
    /// **단순해 보인다고 이 중 하나를 지우지 말 것** — 시간대만 주고 달력을 그대로 두면
    /// `DatePicker`가 여전히 기기 달력(주 시작 요일 등)으로 그 시간대를 해석해 자정 경계가
    /// 다시 어긋날 수 있다.
    func seoulDatePickerEnvironment() -> some View {
        environment(\.timeZone, VisitorCarDateFormat.seoulTimeZone)
            .environment(\.calendar, VisitorCarDateFormat.seoulCalendar)
    }
}

// MARK: - 세대

/// 등록 폼에 **되돌려 보내야** 하는 값들. 사이트가 등록 모달 HTML에 박아서 준다.
struct VisitorCarHousehold: Codable, Equatable, Sendable {
    let dong: String
    let ho: String
    let parkingLot: String
    let parkingZone: String
}

// MARK: - 등록 내역

enum VisitorCarInsertType: String, Sendable, Equatable {
    case kiosk = "K"
    case preVisit = "W"
    case visit = "L"
    case booking = "B"
    case approvedVisit = "N"
    case unknown = "?"

    /// 사이트가 새 구분을 늘려도 디코딩이 죽지 않게 한다 — 화면에 한 줄 덜 보일 뿐이다.
    static func from(_ raw: String) -> VisitorCarInsertType {
        VisitorCarInsertType(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .kiosk: "키오스크"
        case .preVisit: "사전방문"
        case .visit: "방문"
        case .booking: "예약차량"
        case .approvedVisit: "방문차량(승인)"
        case .unknown: ""
        }
    }
}

struct VisitorCarBooking: Identifiable, Equatable, Sendable {
    let id: Int
    let carNo: String
    let name: String
    let tel: String
    let dong: String
    let ho: String
    let startDate: Date
    let endDate: Date
    let updateDate: Date?
    let registrant: String
    let insertType: VisitorCarInsertType
    /// 서버 필드 이름은 `address`다. **주소가 아니라 방문사유다.**
    let visitReason: String
}

extension VisitorCarBooking: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, carNo, name, tel, compName, deptName
        case startDate, endDate, updateDate, userName, insertType, address
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        // 이름·전화·사유는 **빈 문자열로 오거나 아예 빠진다.** 세대 계정이 채우지 않는 칸이다.
        carNo = try c.decodeIfPresent(String.self, forKey: .carNo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        tel = try c.decodeIfPresent(String.self, forKey: .tel) ?? ""
        dong = try c.decodeIfPresent(String.self, forKey: .compName) ?? ""
        ho = try c.decodeIfPresent(String.self, forKey: .deptName) ?? ""
        startDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .startDate))
        endDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .endDate))
        updateDate = try c.decodeIfPresent(TimeInterval.self, forKey: .updateDate)
            .map(Date.init(timeIntervalSince1970:))
        registrant = try c.decodeIfPresent(String.self, forKey: .userName) ?? ""
        insertType = .from(try c.decodeIfPresent(String.self, forKey: .insertType) ?? "")
        visitReason = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
    }
}

// MARK: - 진입 현황

enum VisitorCarEntryStatus: Int, Sendable, Equatable {
    case entered = 0
    case readyToExit = 1
    case exited = 2
    case forcedExit = 3
    case unidentifiedExit = 4
    case faultExit = 5

    var label: String {
        switch self {
        case .entered: "입차"
        case .readyToExit: "출차대기"
        case .exited: "출차"
        case .forcedExit: "강제출차"
        case .unidentifiedExit: "미확인출차"
        case .faultExit: "장애출차"
        }
    }

    /// 아직 주차장 안에 있는가. 진입 현황이 「몇 시간째」를 흘려보낼지 가른다.
    var isParked: Bool { self == .entered || self == .readyToExit }
}

struct VisitorCarEntry: Identifiable, Equatable, Sendable {
    let id: Int
    let inDate: Date
    /// **아직 안 나갔으면 `nil`이다.** 0으로 접으면 1970년에 나간 차가 된다.
    let outDate: Date?
    /// `outChk`가 0~5 밖이면 `nil`. 화면은 빈칸을 둔다 — 웹의 `default` 분기와 같다.
    let status: VisitorCarEntryStatus?
    let carNo: String
    let name: String
    let startDate: Date
    let endDate: Date
    let updateDate: Date?

    /// 주차시간. 서버 응답에 `parkingTime` 필드가 있지만 **웹도 쓰지 않는다** — 렌더러가
    /// 매번 다시 센다. 안 나간 차는 화면이 떠 있는 동안 계속 늘어야 해서 저장할 수가 없다.
    func parkingSeconds(now: Date) -> TimeInterval {
        (outDate ?? now).timeIntervalSince(inDate)
    }
}

extension VisitorCarEntry: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, inDate, outDate, outChk, carNo, name, startDate, endDate, updateDate
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        inDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .inDate))
        outDate = try c.decodeIfPresent(TimeInterval.self, forKey: .outDate)
            .map(Date.init(timeIntervalSince1970:))
        status = try c.decodeIfPresent(Int.self, forKey: .outChk).flatMap(VisitorCarEntryStatus.init(rawValue:))
        carNo = try c.decodeIfPresent(String.self, forKey: .carNo) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        startDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .startDate))
        endDate = Date(timeIntervalSince1970: try c.decode(TimeInterval.self, forKey: .endDate))
        updateDate = try c.decodeIfPresent(TimeInterval.self, forKey: .updateDate)
            .map(Date.init(timeIntervalSince1970:))
    }
}

// MARK: - 페이지

/// 스프링 `Page` 껍데기. 두 목록이 같은 모양이라 하나로 받는다.
struct VisitorCarPage<T: Decodable & Sendable>: Decodable, Sendable {
    let content: [T]
    let totalElements: Int
    let totalPages: Int
    let number: Int
    let last: Bool
}

/// **진입 현황 응답에는 `message: "200"`이 더 붙는다.** 읽지 않는다 —
/// 두 엔드포인트를 같은 디코더로 다루기 위해서다.
struct VisitorCarPageResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let data: VisitorCarPage<T>
}

// MARK: - 등록·수정·삭제 응답

struct VisitorCarResult: Decodable, Sendable {
    let result: String
    let message: String?

    var isSuccess: Bool { result == "success" }
}

// MARK: - 오류

enum VisitorCarError: Error, LocalizedError, Equatable {
    /// 저장된 자격증명이 없다. 화면이 로그인 카드로 되돌아간다.
    case notLoggedIn
    /// 로그인 시도가 거절됐다. 문자열은 **서버가 준 한국어 그대로**다.
    case loginFailed(String)
    /// 재로그인까지 했는데도 로그인 페이지로 튕겼다.
    case sessionExpired
    /// `result != "success"`. 문자열은 서버 `message` 그대로.
    case rejected(String)
    case remainingTimeUnavailable
    case householdUnavailable
    case server(Int)
    case network(String)
    case keychain(Int)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "로그인이 필요합니다."
        case .loginFailed(let message): message
        case .sessionExpired: "다시 로그인해 주세요."
        case .rejected(let message): message
        case .remainingTimeUnavailable: "잔여시간을 불러오지 못했습니다."
        case .householdUnavailable: "세대 정보를 불러오지 못했습니다."
        case .server(let code): "서버에 연결하지 못했습니다. (\(code))"
        // **실린 문구를 그대로 쓴다.** 버리면 `network(String)`의 값이 죽은 짐이 되고,
        // 「연결 실패」와 「응답을 못 읽음」이 화면에서 같은 말이 된다.
        case .network(let message): message
        case .keychain(let status): "계정을 저장하지 못했습니다. (\(status))"
        }
    }
}
