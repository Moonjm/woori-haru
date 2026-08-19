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
    /// 못 보는 상황에서 어느 것이 골라져 있는지 거꾸로 읽힌다 — 주행 탭 기간 칩에서 실제로 났던 일이다.
    @Test func 선택된_쪽이_비선택보다_밝다() {
        #expect(luminance(VehicleTheme.accentBright) > luminance(VehicleTheme.textTertiary))
        #expect(luminance(VehicleTheme.accentBright) > luminance(VehicleTheme.accentMuted))
    }

    /// 막대 트랙은 **어느 상태보다도 어두워야 한다.** 막대가 트랙 위에 겹쳐 칠해지므로,
    /// 트랙이 가장 어두운 상태만큼 밝으면 「기록 없음」과 그 상태가 안 갈린다.
    @Test func 트랙이_가장_어두운_상태보다_어둡다() {
        let kinds: [TimelineKind] = [.asleep, .offline, .online, .driving, .charging]
        let darkestState = kinds.map { luminance(VehicleTheme.color(for: $0)) }.min() ?? 0
        #expect(luminance(VehicleTheme.cardFill) < darkestState)
    }
}
