import SwiftUI
import Testing
@testable import WooriHaru

@MainActor
@Suite("차량 다크 테마")
struct VehicleThemeTests {

    /// **이 단계에서 가장 중요한 테스트다.** 기본값이 `true`로 새면 가계부·식단·일정
    /// 55개 파일이 통째로 어두워진다. 리뷰의 첫 항목이기도 하다.
    @Test func 다크_환경값의_기본값은_꺼짐이다() {
        #expect(EnvironmentValues().vehicleDark == false)
    }

    /// 띠는 다섯 상태를 색으로만 구분한다. 둘이 같은 색이면 띠가 거짓말을 한다 —
    /// 복사·붙여넣기로 한 줄을 안 고치면 정확히 그렇게 된다.
    @Test func 타임라인_다섯_상태가_서로_다른_색이다() {
        let kinds: [TimelineKind] = [.asleep, .offline, .online, .driving, .charging]
        let colors = kinds.map { VehicleTheme.color(for: $0) }
        #expect(Set(colors).count == kinds.count)
    }

    /// 충전만 색을 가진다 — 밤새 충전이 눈에 띄어야 한다는 것이 설계의 요구다.
    @Test func 충전_구간은_강조_글로우_색이다() {
        #expect(VehicleTheme.color(for: .charging) == VehicleTheme.accentGlow)
    }

    /// 잔량과 열화는 **같은 축**을 쓴다. 한쪽만 고치면 같은 화면의 두 링이
    /// 같은 뜻을 다른 색으로 말하게 된다.
    @Test func 잔량과_열화가_같은_축의_색을_쓴다() {
        #expect(VehicleTheme.color(for: BatteryBand.high) == VehicleTheme.color(for: HealthBand.good))
        #expect(VehicleTheme.color(for: BatteryBand.mid) == VehicleTheme.color(for: HealthBand.fair))
        #expect(VehicleTheme.color(for: BatteryBand.low) == VehicleTheme.color(for: HealthBand.low))
    }

    @Test func 잔량_세_구간이_서로_다른_색이다() {
        let colors = [VehicleTheme.color(for: BatteryBand.high),
                      VehicleTheme.color(for: BatteryBand.mid),
                      VehicleTheme.color(for: BatteryBand.low)]
        #expect(Set(colors).count == 3)
    }

    /// 값을 모르는 것은 「좋다」도 「나쁘다」도 아니다 — 판정 색을 쓰면 안 된다.
    @Test func 값이_없으면_판정_색을_쓰지_않는다() {
        let none = VehicleTheme.color(for: BatteryBand?.none)
        #expect(none == VehicleTheme.textTertiary)
        #expect(none != VehicleTheme.accent)
        #expect(none != VehicleTheme.warning)
        #expect(none != VehicleTheme.danger)
        #expect(VehicleTheme.color(for: HealthBand?.none) == VehicleTheme.textTertiary)
    }

    /// WCAG 상대 휘도. **눈으로 보고 「더 밝다」를 판정하지 않는다** — 민트(`accentBright`)는
    /// 채도가 높아 밝아 보이지만 휘도는 옅은 청백(`textSecondary`)보다 낮다.
    private func luminance(_ color: Color) -> Double {
        let c = color.resolve(in: EnvironmentValues())
        // `Color.white.opacity(x)`는 `resolve(in:)`으로 풀면 알파가 성분에 접히지 않고
        // 흰색 성분이 그대로 나온다. 이 화면들은 전부 거의 검은 바탕 위에 얹히므로
        // 알파를 곱한 값이 실제로 보이는 밝기에 가깝다.
        return (0.2126 * Double(c.linearRed)
              + 0.7152 * Double(c.linearGreen)
              + 0.0722 * Double(c.linearBlue)) * Double(c.opacity)
    }

    /// 선택·비선택 짝은 **선택된 쪽이 더 밝아야 한다.** 이 관계가 뒤집히면 알약 배경을
    /// 못 보는 상황에서 어느 것이 골라져 있는지 거꾸로 읽힌다.
    @Test func 선택된_쪽이_비선택보다_밝다() {
        #expect(luminance(VehicleTheme.accentBright) > luminance(VehicleTheme.textTertiary))
        #expect(luminance(VehicleTheme.accentBright) > luminance(VehicleTheme.accentMuted))
    }

    /// **`textSecondary`는 선택 짝의 비선택 쪽으로 쓸 수 없다.** 통계 탭 기간 칩에서 실제로
    /// 났던 사고이고, 리뷰 여섯 바퀴를 통과했다 — 민트가 채도 때문에 밝아 **보이지만**
    /// 휘도는 옅은 청백보다 낮기 때문이다.
    ///
    /// 호출부의 토큰 선택을 단위 테스트가 읽을 수는 없다. 대신 그 사고를 만든 **사실**을
    /// 여기 박아 둔다 — 이 단언이 깨지는 날은 팔레트가 움직인 날이고, 그때 칩과 탭바를
    /// 다시 봐야 한다.
    @Test func 옅은_청백이_민트보다_밝다() {
        #expect(luminance(VehicleTheme.textSecondary) > luminance(VehicleTheme.accentBright))
    }

    /// 밝기로만 갈리는 넷은 **고른 사다리**여야 한다 — 이웃끼리 최소 1.8배씩 벌어진다.
    ///
    /// **서로 다르기만 해서는 부족하다.** `타임라인_다섯_상태가_서로_다른_색이다`는 값이
    /// 다르다는 것만 보므로, `online`이 `offline`보다 1.5배 밝을 뿐인 상태를 통과시켰다 —
    /// 24pt짜리 띠에서는 그 정도로 안 갈린다. 한 칸만 좁아도 거기서 띠가 뭉개진다.
    ///
    /// 충전은 뺀다. 그쪽은 밝기가 아니라 **색**으로 갈리는 유일한 상태다.
    @Test func 밝기로_갈리는_넷이_고른_사다리다() {
        let ladder: [TimelineKind] = [.asleep, .offline, .online, .driving]
        let levels = ladder.map { luminance(VehicleTheme.color(for: $0)) }.sorted()
        for (dim, bright) in zip(levels, levels.dropFirst()) {
            #expect(bright >= dim * 1.8)
        }
    }

    /// 막대 트랙은 가장 어두운 상태보다 **뚜렷하게** 어두워야 한다.
    ///
    /// **단순한 대소 비교로는 이 결함을 표현할 수 없다.** 사고 당시 트랙(`tileFill`, 흰 7%)도
    /// `asleep`(흰 8%)보다 어둡기는 했다 — 문제는 순서가 아니라 **너무 가까운 것**이었고,
    /// 그래서 자고 있던 구간과 기록이 없는 구간이 띠에서 안 갈렸다. 배수로 못 박는다.
    @Test func 트랙이_가장_어두운_상태보다_충분히_어둡다() {
        let kinds: [TimelineKind] = [.asleep, .offline, .online, .driving, .charging]
        let darkestState = kinds.map { luminance(VehicleTheme.color(for: $0)) }.min() ?? 0
        #expect(darkestState >= luminance(VehicleTheme.timelineTrack) * 1.8)
    }
}
