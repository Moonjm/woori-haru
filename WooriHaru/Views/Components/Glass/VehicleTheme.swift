import SwiftUI

/// 차량 미니앱 전용 색. **`Color+Extensions.swift`의 밝은 팔레트와 섞어 쓰지 않는다** —
/// 한 화면에 두 체계가 섞이면 어느 쪽도 일관되지 않는다.
///
/// **이름을 역할로 짓는다.** `slate500` 같은 밝기 번호가 아니라 `textSecondary`·`cardStroke`다.
/// 이 층은 팔레트가 아니라 **의미의 사전**이어야 하고, 그래야 색 참조 170곳을 옮길 때
/// 「어떤 회색이었지」가 아니라 「무슨 역할이었지」로 옮길 수 있다.
enum VehicleTheme {

    // MARK: - 바탕

    static let background   = Color(red: 0.043, green: 0.047, blue: 0.055) // #0b0c0e
    static let surface      = Color(red: 0.078, green: 0.086, blue: 0.098) // #141619
    /// 바탕 아래쪽에 아주 옅게 도는 남색 기.
    static let surfaceTint  = Color(red: 0.043, green: 0.075, blue: 0.149) // #0b1326

    // MARK: - 면

    /// 카드 채움. **아주 옅다** — 형태를 만드는 것은 채움이 아니라 테두리다.
    static let cardFill  = Color.white.opacity(0.04)
    static let cardStroke = Color.white.opacity(0.18)
    /// 카드 **안**에 놓이는 타일·입력칸. 카드 채움 위에 한 단 더 올라앉아야 갈린다.
    static let tileFill  = Color.white.opacity(0.07)
    /// 「값이 없다·0이다」를 뜻하는 트랙과 막대. 강조 색을 쓰면 없는 값이 있는 척한다.
    static let trackFill = Color.white.opacity(0.10)
    /// 24시간 띠의 바닥. **`trackFill`보다 어둡다** — 여기는 막대가 **위에 겹쳐** 칠해지는
    /// 자리라, 바닥이 가장 어두운 상태(`asleep`)에 가까우면 자고 있던 구간과 기록이 없는
    /// 구간이 안 갈린다. 역할을 따로 세운 이유는 그 관계를 테스트가 붙잡을 수 있게 하려는 것이다.
    static let timelineTrack = cardFill

    // MARK: - 강조

    static let accent       = Color(red: 0.176, green: 0.831, blue: 0.749) // #2dd4bf
    static let accentBright = Color(red: 0.369, green: 0.918, blue: 0.831) // #5eead4
    static let accentGlow   = Color(red: 0.306, green: 0.871, blue: 0.639) // #4edea3
    /// 선택되지 않은 막대. **강조와 같은 색을 옅게** 써서 「같은 축의 덜한 값」임을 보인다.
    static let accentMuted  = accent.opacity(0.35)

    // MARK: - 글자

    static let textPrimary   = Color(red: 0.933, green: 0.945, blue: 0.957) // #eef1f4
    static let textSecondary = Color(red: 0.855, green: 0.886, blue: 0.992) // #dae2fd
    static let textTertiary  = Color.white.opacity(0.40)

    // MARK: - 상태

    /// 경고·위험만 iOS 표준 색을 쓴다 — 이 둘은 앱의 취향보다 사람의 습관이 먼저다.
    static let warning = Color(red: 1.0, green: 0.808, blue: 0.0)   // #ffce00
    static let danger  = Color(red: 1.0, green: 0.231, blue: 0.188) // #ff3b30
}

// MARK: - 역할별 색

extension VehicleTheme {

    /// 잔량 색 구간. **판정은 `BatteryBand`가 하고 여기서는 색만 고른다** —
    /// 경계값(50/20)이 두 곳에 적히면 한쪽만 고치는 사고가 난다.
    static func color(for band: BatteryBand?) -> Color {
        switch band {
        case .high: accent
        case .mid: warning
        case .low: danger
        case nil: textTertiary
        }
    }

    /// 열화 색 구간 — 잔량과 **같은 축**을 쓴다. 같은 화면에 링이 둘 있는데
    /// 좋음의 색이 서로 다르면 무엇이 좋은 것인지 읽히지 않는다.
    static func color(for band: HealthBand?) -> Color {
        switch band {
        case .good: accent
        case .fair: warning
        case .low: danger
        case nil: textTertiary
        }
    }

    /// 24시간 띠의 상태 색. **다섯이 서로 달라야 한다.**
    ///
    /// **충전만 색을 가진다.** 나머지 넷은 밝기로만 갈린다 — 그래서 밤새 충전이 있었던 날
    /// 초록 구간 하나가 띠에서 바로 눈에 띈다. 다섯을 다 다른 색으로 칠하면 그 대비가 사라진다.
    ///
    /// **밝기로만 가르는 넷은 고른 사다리여야 한다.** 휘도가 대략 두 배씩 벌어진다
    /// (0.08 → 0.18 → 0.38 → 0.76). 처음에 `online`을 35%로 뒀더니 `offline`과 1.5배밖에
    /// 안 벌어져 24pt짜리 띠에서 「깨어 있음」과 「연결 끊김」이 안 갈렸다 — 한 칸만 좁으면
    /// 거기서 띠가 뭉개진다. 이 관계는 `VehicleThemeTests`가 붙잡는다.
    static func color(for kind: TimelineKind) -> Color {
        switch kind {
        case .asleep: Color.white.opacity(0.08)
        case .offline: Color.white.opacity(0.18)
        case .online: textSecondary.opacity(0.50)
        case .driving: textSecondary
        case .charging: accentGlow
        }
    }
}

// MARK: - 환경값

extension EnvironmentValues {
    /// 차량 미니앱 다크 테마. **기본값은 `false`이므로 다른 미니앱은 아무 영향이 없다.**
    /// 이 기본값이 새면 55개 파일이 통째로 어두워진다 — 테스트가 지키는 유일한 불변이다.
    @Entry var vehicleDark: Bool = false
}

extension View {
    /// 차량·충전 화면의 루트에 한 번 얹는다.
    ///
    /// **`.toolbar`를 붙이는 바로 그 뷰에 얹어야 한다** — `NavigationStack` 바깥에 얹으면
    /// `toolbarColorScheme`이 막대까지 닿지 않는다.
    ///
    /// **`preferredColorScheme`을 쓰지 않는 이유:** 그쪽은 창 전체에 걸린다. 차량 화면이
    /// 밀려 올라오는 0.3초 동안 뒤에 남은 홈 화면까지 같이 뒤집힌다.
    ///
    /// **`colorScheme`을 굳이 건드리는 이유:** `ContentUnavailableView`·`ProgressView`·
    /// `TextField`·`.borderedProminent`는 우리가 색을 줄 수 없는 시스템 부품이다.
    /// 이것만 밝게 남으면 화면이 반쯤 뒤집힌 꼴이 된다.
    func vehicleDarkTheme() -> some View {
        environment(\.vehicleDark, true)
            .environment(\.colorScheme, .dark)
            .tint(VehicleTheme.accent)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
