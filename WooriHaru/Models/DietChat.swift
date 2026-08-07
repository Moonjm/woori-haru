import Foundation

// MARK: - Enum (rawValue는 서버 값 그대로)

/// 타임라인 한 줄에 무엇이 놓였는가.
enum ChatMessageType: String, Codable, Hashable {
    case text = "TEXT"
    case mealCard = "MEAL_CARD"
    case daySummary = "DAY_SUMMARY"
    /// 서버가 카드 종류를 늘렸을 때(활동 에너지·몸무게 카드는 서버 설계의 「범위 밖」에 있다)
    /// **페이지 전체가 날아가지 않게** 흡수하는 값. `FoodDataset.unknown`이 같은 이유로 있다.
    ///
    /// **화면은 이 메시지를 건너뛴다**(`DietChatViewModel.isRenderable`) — 무엇인지 모르는
    /// 것을 빈 말풍선으로 그리면 사용자는 서버가 무언가를 빠뜨렸다고 읽는다.
    case unknown

    /// **모르는 값을 던지지 않고 삼킨다.** `[ChatMessage]` 배열은 한 건만 실패해도 전체가
    /// 실패하므로, 서버가 카드를 늘리는 날 옛 앱은 그 페이지를 통째로 잃는다.
    init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChatMessageType(rawValue: raw) ?? .unknown
    }
}

/// 카드도 `assistant`다 — 코치가 놓은 것이라 화면에서 왼쪽에 선다.
enum ChatRole: String, Codable, Hashable {
    case user = "USER"
    case assistant = "ASSISTANT"
}

// MARK: - 카드

/// 끼니 카드. **서버가 저장한 스냅샷이 아니라 조회 시점의 끼니에서 읽은 값이다** —
/// 확정 뒤에 끼니를 고쳐도 카드가 낡지 않는다.
struct ChatMealCard: Codable, Hashable {
    let mealId: Int
    let mealType: MealType
    let score: Int?
    /// **구성비 막대(`46% / 17% / 37%`)는 여기 `percent`를 그대로 쓴다.** 앱이 g에서 직접
    /// 나누면 안 된다 — 비율의 분모가 `totalKcal`이 아니라 매크로에서 역산한 값이라 순진하게
    /// 계산하면 다른 숫자가 나온다(`ScoreBasisCard`가 이미 같은 이유로 「앱은 계산하지 않는다」다).
    let scoreBasis: MealScoreBasis?
    let totalKcal: Double
    let carbsG: Double
    let proteinG: Double
    let fatG: Double
    /// 사진 한 장. presigned URL이라 매 조회 새로 발급된다. 사진 없이 기록한 끼니는 nil이다.
    let photoUrl: String?
    /// **생성 중이거나 실패했으면 nil** — 그 자리를 「코치가 보고 있어요」로 채운다. 폴링하지 않는다.
    let feedback: String?
}

/// 총평 카드. 끼니 카드와 같은 이유로 조회 시점 값이다.
struct ChatDayCard: Codable, Hashable {
    let dayScore: Int
    let totalKcal: Double
    /// 그날 **첫 끼니의 스냅샷**이다. 프로필의 현재 목표가 아니라서 몸무게를 바꿔도 과거
    /// 카드의 분모가 흔들리지 않는다.
    let targetKcal: Int
    /// 재생성 중이면 nil — 「마감 피드백을 만들고 있어요」를 띄운다.
    let feedback: String?
}

// MARK: - 메시지

/// 타임라인 한 줄.
///
/// **날짜가 두 축이다.** `createdAt`은 「언제 그 일이 있었나」, `date`는 「어느 날 밥 얘기인가」다.
/// 스트림은 `createdAt` 순이라 8월 6일에 8월 1일을 물으면 그 말풍선은 8월 6일 자리에 앉는다.
/// 날짜 구분선은 `createdAt`, 말풍선 배지는 `date`다(`DietChatViewModel.rows`).
struct ChatMessage: Codable, Hashable, Identifiable {
    let id: Int
    let type: ChatMessageType
    /// "2026-08-01"
    let date: String
    let role: ChatRole
    /// 서버 `LocalDateTime`("2026-08-06T21:14:03.123456").
    ///
    /// **`Date`가 아니라 문자열이다.** `APIClient`의 디코더는 날짜 전략을 세우지 않아
    /// `Date`로 받으면 숫자를 기대하다 실패한다 — 이 저장소가 서버 시각을 문자열로 받아
    /// `Date.fromISO`로 푸는 관례(`StudySession.startedAt`)를 그대로 따른다. 구분선이 필요한
    /// 것은 「무슨 날인가」뿐이라 앞 10자로 충분하고(`createdAtDay`), 그 편이 시간대 변환을
    /// 거치지 않아 서버가 보낸 날짜와 어긋날 여지도 없다.
    let createdAt: String
    /// **`text`일 때만 있다.** 카드 행은 nil이다 — 「없다」와 「비어 있다」를 같은 값으로
    /// 만들지 않으려고 서버가 빈 문자열 대신 null을 내린다.
    let content: String?
    let meal: ChatMealCard?
    let day: ChatDayCard?

    /// 날짜 구분선이 쓰는 값. "2026-08-06"
    var createdAtDay: String { String(createdAt.prefix(10)) }
}

/// 한 장. **`nextCursor`가 null이면 더 없다** — 그때 무한 스크롤을 멈춘다.
/// 최신이 먼저 오므로(`id DESC`) 앱이 뒤집어 아래에 붙인다.
struct ChatPage: Codable, Hashable {
    let messages: [ChatMessage]
    let nextCursor: Int?
}

// MARK: - Request

struct ChatAskRequest: Encodable {
    let message: String
}

// MARK: - 정책 상수

enum ChatPolicy {
    /// 서버 기본값과 같다. 상한은 100이다.
    static let pageSize = 30
}
