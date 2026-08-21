import Foundation

// MARK: - 응답

/// 개요 화면의 배터리 카드 하나. **시각은 전부 KST다.**
struct BatteryWindowResponse: Codable, Equatable {
    let hours: Int
    /// **`String`이다** — 디코더에 날짜 전략이 없다(`TimeSegment`와 같다, `StateTimelineModels.swift:32`).
    let from: String
    /// **요청 시각이다**, 자정이 아니다 — 화면 오른쪽 끝이 「지금」이어야 한다.
    let to: String
    /// 오래된 것부터, **5분마다 최대 하나로 솎여 온다**(앱이 다시 솎지 않음). 없으면 빈 배열.
    let samples: [BatterySample]
    /// 이 범위 안의 충전 구간, 범위 경계로 잘려 온다. `TimeSegment`를 그대로 쓴다(`StateTimelineModels.swift:32`).
    let charges: [TimeSegment]
    /// **`hours`와 무관하게 최근 7일 고정이다** — 48시간 범위면 순수 주차 구간이 없는 날이 흔하다.
    let parkDrain: ParkDrain
}

struct BatterySample: Codable, Identifiable, Equatable {
    /// **그 슬롯의 실제 표본 시각이다** — 5분 눈금으로 옮기지 않는다(없는 시각의 값이 된다).
    let at: String
    let batteryLevel: Int
    /// **실측 채움율 3.0%(11,575/392,054)뿐이다** — 선으로 이으면 끊긴다, 있을 때만 점을 찍는다.
    let usableBatteryLevel: Int?

    /// 5분마다 최대 하나라 시각이 유일하다.
    var id: String { at }

    var date: Date? { VehicleFormat.parseKST(at) }
}

/// 주차 중 정격거리가 얼마나 샜나(팬텀 드레인). **나눗셈은 앱이 한다** — `VehicleMath.drainPerHour`.
struct ParkDrain: Codable, Equatable {
    /// **음수 구간도 부호 그대로 들어 있다**(BMS 재보정).
    let ratedKm: Decimal
    let hours: Decimal
    /// **0이면 줄을 감춘다** — 0km/시간은 「안 샜다」는 거짓말이다.
    let samples: Int
}
