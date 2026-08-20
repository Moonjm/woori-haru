# 차량 화면 다크 테마 구현 계획 (B단계)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 차량 세 탭과 충전 상세·금액 입력 화면을 **거의 검정 바탕 + 흰색 몇 %짜리 카드 + 민트 강조**의 다크 테마로 바꾼다. 다른 미니앱은 한 픽셀도 바뀌지 않는다.

**Architecture:** 색 하나를 바꾸는 일이 아니라 **의미의 사전을 하나 새로 두는 일**이다. `VehicleTheme`이 역할 이름(`textSecondary`·`cardStroke`)으로 색을 들고, 공유 컴포넌트 둘(`GlassCard`·`GlassBackground`)이 환경값 `\.vehicleDark`를 읽어 갈래를 고른다. 기본값이 `false`이고 그 갈래가 지금 코드와 **완전히 같으므로** 나머지 55개 파일의 렌더 결과는 그대로다.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26), `@Entry` 환경값, Swift Testing(`import Testing`), 손그림 차트(`GeometryReader`+`Rectangle`, Swift Charts 미사용)

**Spec:** `docs/superpowers/specs/2026-08-19-vehicle-dark-theme-design.md` — **B단계 부분만**(146행 이후). A단계(24시간 띠·평균 타일)는 이미 `develop`에 있다(`30a6259`).

**앞선 작업:** `develop` = `30a6259`. 이 브랜치(`feat/vehicle-dark-palette`)는 거기서 갈라진다.

## Global Constraints

- **새 파일은 `ruby scripts/xcode-add-files.rb <경로...>`로 앱 타겟에 등록한다.** `WooriHaru/` 아래는 폴더 동기화가 없어 파일을 만들어 두기만 하면 **컴파일 대상에 잡히지 않는다.** `WooriHaruTests/`는 자동으로 잡힌다. **이 계획은 앱 타겟에 새 파일 하나(`VehicleTheme.swift`)를 만든다 — Task 1에서 반드시 등록한다.**
- 전체 테스트: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. 단일 스위트는 뒤에 `-only-testing:WooriHaruTests/<스위트>`를 붙인다. **포그라운드로 돌린다** — 백그라운드로 띄우고 기다리면 턴이 끝나 버린다. 몇 분 걸리는 것이 정상이다.
- 출력이 길다. `2>&1 | grep -E "Test run with|failed|error:|warning:|TEST SUCCEEDED|TEST FAILED" | tail -30`으로 거른다.
- **`xcodebuild test`는 `-only-testing`을 줘도 테스트 번들 전체를 컴파일한다.** 어느 태스크도 컴파일이 깨진 채로 끝나면 안 된다.
- **SWBBuildService가 가끔 죽는다.** 이 프로젝트에서 알려진 Xcode 빌드 시스템 불안정이고, **같은 명령을 다시 돌리면 지나간다.** 원인을 찾으러 가지 않는다.
- 편집기의 SourceKit 진단(`No such module 'Testing'`, `Cannot find type X in scope`)은 이 프로젝트의 알려진 색인 잡음이다. **`xcodebuild`가 권위다.**
- **`Color+Extensions.swift`에서 아무것도 지우지 않는다.** 55개 파일이 그 토큰을 쓰고 있다. 차량 화면이 안 쓸 뿐이다.
- **차량·충전 화면에서는 `Color.slate*`·`blue*`·`green*`·`orange*`·`red*`·`navy*`를 쓰지 않는다.** 한 화면에 두 색 체계가 섞이면 어느 쪽도 일관되지 않는다. 이 계획이 끝나면 `WooriHaru/Views/Vehicle/`과 `WooriHaru/Views/Charge/`에 `Color.slate` 같은 문자열이 **하나도 남지 않아야 한다.**
- **`GlassTokens`(모서리·여백)는 그대로 쓴다.** 어두워지는 것은 색이지 치수가 아니다.
- **다크 갈래에서 `glassEffect`를 쓰지 않는다.** Liquid Glass의 굴절은 뒤에 밝은 것이 있을 때만 드러난다. 거의 검은 배경 위에서는 보이는 것 없이 색만 예측하기 어려워진다. 대신 `cardFill` + `cardStroke`로 명시적으로 그린다 — **테두리가 형태를 만든다.**
- **Swift Charts를 쓰지 않는다.** `GeometryReader`·`Rectangle`로 그린다.
- 주석과 테스트 함수 이름은 한국어 평서형(`~한다`, `~다`)이며 설계 근거를 담는 산출물의 일부다. **Swift 식별자는 숫자로 시작할 수 없다** — `@Test func 24시간_...`은 컴파일되지 않는다.
- 커밋 메시지는 한국어 평서형.
- **어느 문서에도 참고한 앱의 이름을 적지 않는다.**

## 팔레트 (스펙에서 그대로 옮긴 값)

| 토큰 | 값 | 쓰임 |
|---|---|---|
| `background` | `#0b0c0e` | 화면 바탕 위쪽 |
| `surface` | `#141619` | 예비(지금 계획은 안 쓴다) |
| `surfaceTint` | `#0b1326` | 화면 바탕 아래쪽(옅은 남색 기) |
| `cardFill` | 흰색 4% | 카드 채움 |
| `cardStroke` | 흰색 18% | 카드 테두리 — 형태를 만든다 |
| `tileFill` | 흰색 7% | 카드 **안**의 타일·입력칸 |
| `trackFill` | 흰색 10% | 「비었다」를 뜻하는 트랙·막대 |
| `accent` | `#2dd4bf` | 강조(민트) |
| `accentBright` | `#5eead4` | 선택된 것 |
| `accentGlow` | `#4edea3` | 링 후광·충전 구간 |
| `accentMuted` | `accent` 35% | 선택 안 된 막대 |
| `textPrimary` | `#eef1f4` | 값·제목 |
| `textSecondary` | `#dae2fd` | 라벨 |
| `textTertiary` | 흰색 40% | 보조 설명·눈금 |
| `warning` | `#ffce00` | 경고 |
| `danger` | `#ff3b30` | 오류·위험 |

**`tileFill`·`trackFill`·`accentMuted` 셋은 스펙 표에 없고 이 계획이 더한다.** 스펙의 팔레트는 카드 한 겹만 상정했는데 실제 화면에는 「카드 안의 타일」(`Color.slate100` 자리, 10곳)과 「값이 없는 막대」(`Color.slate200` 자리, 4곳)가 있다. 셋 다 스펙이 뽑아 둔 범위(흰색 2.2~7%, 강조 계열) 안에 있다.

## 색 대응표 (기계적 치환)

아래는 **자리를 안 보고 그대로 바꿔도 되는** 대응이다. 예외는 태스크마다 따로 적었다.

| 기존 | 새 값 | 역할 |
|---|---|---|
| `Color.slate900` | `VehicleTheme.textPrimary` | 값·제목 |
| `Color.slate700` | `VehicleTheme.textPrimary` | 〃 |
| `Color.slate500` | `VehicleTheme.textSecondary` | 라벨 |
| `Color.slate400` | `VehicleTheme.textTertiary` | 보조 설명·눈금 |
| `Color.slate100` (배경으로 쓰인 것) | `VehicleTheme.tileFill` | 카드 안 타일·입력칸 |
| `Color.slate50` (`#Preview` 배경) | `VehicleTheme.background` | 미리보기 |
| `Color.blue600` / `Color.blue500` | `VehicleTheme.accent` | 강조 선·글자 |
| `Color.blue300` | `VehicleTheme.accentMuted` | 선택 안 된 막대 |
| `Color.green600` / `Color.green300` | `VehicleTheme.accent` | 정상·양호 |
| `Color.orange700` / `orange500` / `orange300` | `VehicleTheme.warning` | 경고 |
| `Color.orange100` (배경) | `VehicleTheme.warning.opacity(0.15)` | 경고 배너 바탕 |
| `Color.red500` | `VehicleTheme.danger` | 오류 |
| `.white` (글자) | `VehicleTheme.textPrimary` | |
| `.white.opacity(0.5~0.6)` (글자) | `VehicleTheme.textTertiary` | |
| `Color.navy800` / `navy900` | **삭제** | 진한 패널이 사라진다 |

**`isSelected ? A : B` 꼴은 `VehicleTheme.accentBright : VehicleTheme.accentMuted`로 간다** — 선택된 것이 더 밝다는 관계가 유지돼야 한다.

## 이 계획이 내리는 판정 (스펙이 답하지 않은 것)

1. **`preferredColorScheme`을 쓰지 않는다.** 그쪽은 창 전체에 걸려, 차량 화면이 `NavigationStack`에 밀어 올려질 때 **뒤에 남은 홈 화면까지 같이 뒤집힌다**(전환 애니메이션 0.3초 동안 보인다). 대신 `.environment(\.colorScheme, .dark)`로 하위 트리에만 걸고, 막대는 `.toolbarColorScheme(.dark, for: .navigationBar)`로 따로 맞춘다. 둘 다 iOS 16+ API이고 iOS 26.5 SDK에서 폐기되지 않았다.
2. **`colorScheme`을 왜 굳이 건드리나.** `ContentUnavailableView`·`ProgressView`·`TextField`·`.borderedProminent`는 우리가 색을 줄 수 없는 시스템 부품이다. 이것만 밝게 남으면 화면이 반쯤 뒤집힌 꼴이 된다.
3. **세 루트가 각자 테마를 선언한다.** 시트·풀스크린커버로 환경값이 전달되는지에 기대지 않는다 — `ChargeDetailView`는 시트, `ChargeCostQueueView`는 풀스크린커버다. 한 줄짜리 보험이고, 그 대신 전달 여부를 확인할 일이 없어진다.
4. **`ChargeCostEditSheet`도 범위에 넣는다.** 스펙은 파일 이름(`ChargeDetailView.swift`)으로 범위를 적었고 이 시트는 그 파일 안에 있으며 그 화면에서만 열린다. 빼면 어두운 상세에서 「금액 수정」을 눌렀을 때 새하얀 시트가 올라온다 — 스펙의 「한 화면만 밝으면 눈이 아프다」에 정면으로 걸린다.
5. **`MonthPickerSheet`는 건드리지 않는다.** 가계부·일정·달력 등 다섯 화면이 함께 쓰는 공용 시트다. 요약 탭에서 연월을 고를 때만 밝은 바텀시트가 잠깐 올라온다 — **알려진 잔여물이고, 고치려면 그 다섯 화면의 몫을 먼저 정해야 한다.** 이 계획의 범위 밖이다.
6. **링 후광 색은 `accentGlow`가 아니라 링 색을 따른다.** 스펙은 후광을 `accentGlow`로 못 박았지만, 잔량 20% 미만이면 링이 `danger`(빨강)가 된다 — 거기 초록 후광이 지면 색이 서로를 부정한다. `ringColor.opacity(0.55)`로 둔다. 잔량이 높을 때(가장 흔한 상태)는 링이 `accent`이므로 스펙이 의도한 그림과 같다.

---

## 파일 구조

**새로 만든다**

- `WooriHaru/Views/Components/Glass/VehicleTheme.swift` — 팔레트, 역할별 색 함수(`color(for:)` 셋), `\.vehicleDark` 환경값, `vehicleDarkTheme()` 수정자. **한 파일에 넣는 이유:** 넷이 서로를 전제한다. 나누면 「토큰만 바꾸고 수정자는 안 바꾼」 커밋이 가능해진다.
- `WooriHaruTests/VehicleThemeTests.swift` — 기본값과 색 구분 테스트.

**고친다**

| 파일 | 태스크 | 무엇이 |
|---|---|---|
| `Views/Components/Glass/GlassCard.swift` | 2 | 다크 갈래 |
| `Views/Components/Glass/GlassBackground.swift` | 2 | 다크 갈래 |
| `Views/Vehicle/VehicleView.swift` | 3 | 루트 테마·탭바·툴바 |
| `Views/Vehicle/ChargeCostQueueView.swift` | 3 | 루트 테마·색 |
| `Views/Vehicle/BatteryNowCard.swift` | 4 | 패널 제거·민트 링·색 |
| `Views/Vehicle/BatteryHealthCard.swift` | 4 | 색 |
| `Views/Vehicle/TirePressureCard.swift` | 4 | 색 |
| `Views/Vehicle/VehicleStatusTab.swift` | 4 | 색 |
| `Views/Vehicle/StateTimelineChart.swift` | 5 | 상태 색을 테마로 |
| `Views/Vehicle/VehicleDriveTab.swift` | 5 | 기간 칩·색 |
| `Views/Vehicle/DriveStatsCard.swift` | 5 | 색 |
| `Views/Vehicle/DriveBucketCards.swift` | 5 | 색 |
| `Views/Vehicle/DriveTimeHeatmap.swift` | 5 | 색 |
| `Views/Vehicle/DegradationTrendChart.swift` | 5 | 색 |
| `Views/Vehicle/VehicleSummaryTab.swift` | 6 | 히어로 그라디언트·색 |
| `Views/Vehicle/VehicleTrendChart.swift` | 6 | 색 |
| `Views/Vehicle/ChargeTotalsCard.swift` | 6 | 색 |
| `Views/Charge/ChargeRow.swift` | 6 | 색 |
| `Views/Charge/ChargeCurveChart.swift` | 6 | 색 |
| `Views/Charge/ChargeDetailView.swift` | 6 | 루트 테마·색·수정 시트 |

**손대지 않는다:** `Extensions/Color+Extensions.swift`, `Views/Components/Glass/GlassTokens.swift`, 다른 미니앱 전부.

---

## Task 1: `VehicleTheme` — 팔레트와 환경값

**Files:**
- Create: `WooriHaru/Views/Components/Glass/VehicleTheme.swift`
- Create: `WooriHaruTests/VehicleThemeTests.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (스크립트가 고친다)

**Interfaces:**
- Consumes: `BatteryBand`(`.high/.mid/.low`), `HealthBand`(`.good/.fair/.low`), `TimelineKind`(`.asleep/.offline/.online/.driving/.charging`) — 모두 이미 있다.
- Produces: `enum VehicleTheme`의 static 색 16개, `VehicleTheme.color(for: BatteryBand?)`, `VehicleTheme.color(for: HealthBand?)`, `VehicleTheme.color(for: TimelineKind)`, `EnvironmentValues.vehicleDark: Bool`, `View.vehicleDarkTheme() -> some View`. Task 2~6이 전부 이 이름들을 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleThemeTests.swift`:

```swift
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
}
```

- [ ] **Step 2: 실패를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleThemeTests 2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | tail -10`

Expected: 컴파일 실패 — `Cannot find 'VehicleTheme' in scope`, `Value of type 'EnvironmentValues' has no member 'vehicleDark'`.

- [ ] **Step 3: `VehicleTheme.swift`를 쓴다**

```swift
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
```

- [ ] **Step 4: 앱 타겟에 등록한다**

```bash
ruby scripts/xcode-add-files.rb WooriHaru/Views/Components/Glass/VehicleTheme.swift
```

등록하지 않으면 테스트 번들만 컴파일되고 **본 코드가 없어** `Cannot find 'VehicleTheme' in scope`가 그대로 남는다. `gem install --user-install xcodeproj`가 필요할 수 있다.

- [ ] **Step 5: 테스트 통과를 확인한다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:WooriHaruTests/VehicleThemeTests 2>&1 | grep -E "error:|TEST FAILED|TEST SUCCEEDED" | tail -10`

Expected: TEST SUCCEEDED

- [ ] **Step 6: 전체 테스트로 아무것도 안 깨졌는지 본다**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED. 이 단계까지는 화면이 아무것도 안 바뀐다 — 아무도 `VehicleTheme`을 아직 안 쓴다.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Views/Components/Glass/VehicleTheme.swift WooriHaruTests/VehicleThemeTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차량 화면 다크 팔레트와 테마 환경값을 둔다"
```

---

## Task 2: 공유 카드·배경의 다크 갈래

**Files:**
- Modify: `WooriHaru/Views/Components/Glass/GlassCard.swift`
- Modify: `WooriHaru/Views/Components/Glass/GlassBackground.swift`

**Interfaces:**
- Consumes: `VehicleTheme.cardFill`, `.cardStroke`, `.background`, `.surfaceTint`, `EnvironmentValues.vehicleDark` (Task 1)
- Produces: `GlassCard`·`GlassBackground`가 `\.vehicleDark`를 읽는다는 사실. Task 3~6은 카드 안쪽 색만 신경 쓰면 된다.

**이 태스크의 리뷰 첫 항목:** **`vehicleDark == false`인 갈래가 지금 코드와 글자 그대로 같아야 한다.** 42개 파일이 `GlassCard`를, 27개 화면이 `glassScreenBackground()`를 쓴다. 밝은 갈래를 한 글자라도 바꾸면 이 계획의 범위를 벗어난 화면이 바뀐다.

- [ ] **Step 1: `GlassCard.swift`를 고친다**

`glassEffect`를 조건부로 붙여야 하는데 `if/else`가 뷰 타입을 가르므로 `ViewModifier`로 감싼다. 파일 전체를 아래로 바꾼다:

```swift
import SwiftUI

/// 앱 공용 Liquid Glass 카드. 기존 흰 카드(RoundedRectangle.fill(.white).stroke) 대체용.
///
/// **차량 미니앱에서는 유리를 쓰지 않는다.** `\.vehicleDark`가 켜지면 `cardFill` + `cardStroke`로
/// 명시적으로 그린다 — Liquid Glass의 굴절은 뒤에 밝은 것이 있을 때만 드러나는 효과라,
/// 거의 검은 배경 위에서는 보이는 것 없이 색만 예측하기 어려워진다.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassTokens.cardCornerRadius
    var padding: CGFloat = GlassTokens.cardPadding
    var alignment: Alignment = .leading
    @ViewBuilder var content: () -> Content

    @Environment(\.vehicleDark) private var vehicleDark

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .modifier(GlassCardSurface(cornerRadius: cornerRadius, dark: vehicleDark))
            // 카드처럼 생긴 것은 어디를 눌러도 눌려야 한다. 이게 없으면 `NavigationLink`
            // 안에서 글씨·아이콘 픽셀만 탭에 닿고 그 사이 여백은 통과한다.
            // **모서리를 유리 모양과 맞춘다** — `.rect`로 두면 보이지 않는 귀퉁이가 눌린다.
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

/// **밝은 갈래는 예전 코드 그대로다.** 42개 파일이 이 카드를 쓰고 있고,
/// 다크는 차량·충전 화면에서만 켜진다.
private struct GlassCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let dark: Bool

    func body(content: Content) -> some View {
        if dark {
            content
                .background(VehicleTheme.cardFill, in: RoundedRectangle(cornerRadius: cornerRadius))
                // **테두리가 형태를 만든다.** 채움이 흰색 4%뿐이라 선이 없으면 배경과 안 갈린다.
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(VehicleTheme.cardStroke, lineWidth: 1)
                )
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
```

- [ ] **Step 2: `GlassBackground.swift`를 고친다**

```swift
import SwiftUI

/// 화면 배경 레이어. glass 요소가 비쳐 보이도록 은은한 그라데이션을 깐다.
///
/// **차량 미니앱에서는 거의 검정에 아주 옅은 푸른 기를 깐다.** 위가 완전한 검정에 가깝고
/// 아래로 갈수록 남색 기가 돈다 — 단색으로 두면 화면이 평평해 보인다.
struct GlassBackground: View {
    @Environment(\.vehicleDark) private var vehicleDark

    var body: some View {
        LinearGradient(
            colors: vehicleDark
                ? [VehicleTheme.background, VehicleTheme.surfaceTint]
                : [Color.slate50, Color.blue50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// 화면 루트 배경으로 GlassBackground를 깐다.
    ///
    /// **`vehicleDarkTheme()`보다 안쪽에 붙여야 한다** — 환경값은 바깥에서 안으로 흐른다.
    func glassScreenBackground() -> some View {
        background { GlassBackground() }
    }
}
```

- [ ] **Step 3: 전체 테스트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED. **아직 아무 화면도 다크를 켜지 않았으므로 화면은 그대로다.**

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Components/Glass/GlassCard.swift WooriHaru/Views/Components/Glass/GlassBackground.swift
git commit -m "feat: 공용 카드와 배경에 차량 다크 갈래를 더한다"
```

---

## Task 3: 세 루트 중 둘 — 차량 화면과 금액 등록

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`
- Modify: `WooriHaru/Views/Vehicle/ChargeCostQueueView.swift`

**Interfaces:**
- Consumes: `vehicleDarkTheme()`, `VehicleTheme.*` (Task 1), 다크 갈래 카드·배경 (Task 2)
- Produces: 없음 — 아래 태스크들은 이 두 파일을 건드리지 않는다.

### VehicleView.swift

- [ ] **Step 1: 루트에 테마를 얹는다**

30행 `.glassScreenBackground()` **바로 다음 줄**에 넣는다:

```swift
        .glassScreenBackground()
        .vehicleDarkTheme()
```

**순서가 중요하다.** `glassScreenBackground()`가 안쪽이어야 `GlassBackground`가 환경값을 받는다. 그리고 `.toolbar`(36행)와 같은 체인 위에 있어야 `toolbarColorScheme`이 막대에 닿는다.

- [ ] **Step 2: 툴바 제목과 월 전환기 색을 준다**

`principalTitle`(98~104행)의 두 `Text`에 색을 붙인다 — 지금은 색을 안 줘서 `.primary`(검정)로 그려진다:

```swift
    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .status:
            Text("차량 상태").font(.subheadline).fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textPrimary)
        case .drive:
            Text("주행").font(.subheadline).fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textPrimary)
        case .summary: monthSwitcher
        }
    }
```

137행 `.foregroundStyle(Color.slate700)` → `.foregroundStyle(VehicleTheme.textPrimary)`

- [ ] **Step 3: 탭바에서 유리를 걷어내고 민트로 바꾼다**

`tabBar`(151~164행)의 158행:

```swift
        .padding(6)
        // 다크에서는 유리를 쓰지 않는다 — 테두리가 형태를 만든다.
        .background(VehicleTheme.cardFill, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(VehicleTheme.cardStroke, lineWidth: 1))
```

`tabButton`(166~189행)의 177~185행:

```swift
            .foregroundStyle(selected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
            .background {
                if selected {
                    // **파란 그라디언트와 그림자를 버린다.** 이 화면에서 빛나는 것은
                    // 잔량 링 하나뿐이어야 하고, 탭바가 두 번째로 빛나면 그 규칙이 깨진다.
                    RoundedRectangle(cornerRadius: 18)
                        .fill(VehicleTheme.accent.opacity(0.20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(VehicleTheme.accent.opacity(0.45), lineWidth: 1)
                        )
                }
            }
```

### ChargeCostQueueView.swift

- [ ] **Step 4: 루트에 테마를 얹고 색을 옮긴다**

29행 `.glassScreenBackground()` 바로 다음 줄에 `.vehicleDarkTheme()`를 넣는다 — `.navigationTitle`·`.toolbar`와 같은 체인이고 `NavigationStack` 안쪽이다.

색 치환(대응표대로):

| 행 | 기존 | 새 값 |
|---|---|---|
| 44 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 67 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 73 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 81 | `Color.slate100` | `VehicleTheme.tileFill` |
| 86 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 91 | `Color.red500` | `VehicleTheme.danger` |

- [ ] **Step 5: 입력칸 글자색을 못 박는다**

74~78행 `TextField`에 색을 붙인다. `colorScheme`이 다크라 기본값도 흰색이 되지만, **이 화면의 주인공이 시스템 기본값에 기대게 두지 않는다:**

```swift
                TextField("금액", text: $text)
                    .keyboardType(.numberPad)
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(VehicleTheme.textPrimary)
                    .focused($focused)
```

- [ ] **Step 6: 빌드와 전체 테스트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED. **이 시점부터 화면이 반쯤 어둡다** — 바탕과 카드는 어두운데 카드 속 글자는 아직 진한 회색이다. Task 4~6이 그것을 메운다. 중간 상태가 보기 흉한 것은 정상이다.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Views/Vehicle/VehicleView.swift WooriHaru/Views/Vehicle/ChargeCostQueueView.swift
git commit -m "feat: 차량 화면과 금액 등록 화면을 다크로 켠다"
```

---

## Task 4: 상태 탭 — 링을 다시 세운다

**Files:**
- Modify: `WooriHaru/Views/Vehicle/BatteryNowCard.swift`
- Modify: `WooriHaru/Views/Vehicle/BatteryHealthCard.swift`
- Modify: `WooriHaru/Views/Vehicle/TirePressureCard.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatusTab.swift`

**Interfaces:**
- Consumes: `VehicleTheme.*`, `VehicleTheme.color(for: BatteryBand?)`, `VehicleTheme.color(for: HealthBand?)` (Task 1)
- Produces: 없음.

**이 태스크의 핵심은 색 치환이 아니라 강조를 다시 세우는 것이다.** 4단계는 「진한 남색 패널이 화면에서 유일하다」로 `BatteryNowCard`를 강조했다. 배경이 검정이 되면 그 장치가 통째로 무너진다 — 어두운 판이 더 이상 특별하지 않다. **강조가 민트 링과 후광으로 옮겨간다.**

### BatteryNowCard.swift

- [ ] **Step 1: 진한 패널을 없앤다**

180~201행의 `batteryPanelBackground()`와 `BatteryPanelBackground`를 아래로 갈아끼운다. **모디파이어 자체는 남긴다** — `BatteryNowCard`와 `BatteryNowPlaceholderCard`가 같은 자리에 번갈아 서는 같은 패널이라 스타일이 갈라지면 화면 상태가 바뀔 때 색이 미묘하게 달라져 보인다.

```swift
// MARK: - 공용 패널 배경

extension View {
    /// 히어로 패널 배경. **더 이상 「진한 판」이 아니다** — 배경이 검정이 되면서
    /// 어두운 판은 특별할 수 없게 됐다. 다른 카드와 같은 면을 쓰고, 강조는 링이 맡는다.
    ///
    /// `BatteryNowCard`와 `BatteryNowPlaceholderCard`가 같은 자리에 번갈아 서는 같은
    /// 패널이라, 스타일이 갈라지면 화면 상태가 바뀔 때 색이 미묘하게 달라져 보인다.
    fileprivate func batteryPanelBackground() -> some View {
        modifier(BatteryPanelBackground())
    }
}

private struct BatteryPanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VehicleTheme.cardFill, in: RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(VehicleTheme.cardStroke, lineWidth: 1)
            )
    }
}
```

그림자(`.shadow(color: Color.navy900...)`)는 **지운다.** 검정 위의 검은 그림자는 보이지 않으면서 렌더 비용만 든다.

- [ ] **Step 2: 링에 후광을 넣는다**

`ring`(37~61행)의 `ZStack` 앞 두 줄을 바꾼다:

```swift
    private var ring: some View {
        ZStack {
            Circle().stroke(VehicleTheme.trackFill, lineWidth: 9)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // **화면에서 빛나는 것은 이것 하나뿐이다.** 후광 색은 링 색을 따라간다 —
                // 잔량 20% 미만이면 링이 빨강이 되는데 거기 초록 후광이 지면 색이
                // 서로를 부정한다.
                .shadow(color: ringColor.opacity(0.55), radius: 12)
```

- [ ] **Step 3: `ringColor`를 테마에 넘긴다**

69~76행을 통째로:

```swift
    /// 50% 이상 민트, 20~50% 노랑, 20% 미만 빨강. **문구는 붙이지 않는다** — 색만 바뀐다.
    /// 판정은 `BatteryBand`, 색은 `VehicleTheme`. 둘 다 여기서 하지 않는다.
    private var ringColor: Color {
        VehicleTheme.color(for: BatteryBand.of(status.batteryLevel))
    }
```

- [ ] **Step 4: 남은 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 49 | `.white` | `VehicleTheme.textPrimary` |
| 55 | `.white.opacity(0.6)` | `VehicleTheme.textTertiary` |
| 84 | `.fill(.white.opacity(0.8))` | `.fill(VehicleTheme.accent)` — 살아 있는 상태를 가리키는 점이다 |
| 90 | `.white` | `VehicleTheme.textPrimary` |
| 95 | `.white.opacity(0.6)` | `VehicleTheme.textTertiary` |
| 117 | `.white.opacity(0.55)` | `VehicleTheme.textTertiary` |
| 123 | `.white` | `VehicleTheme.textPrimary` |
| 143 | `.white.opacity(0.5)` | `VehicleTheme.textTertiary` |
| 151 | `.white` | `VehicleTheme.textPrimary` |
| 154 | `.white.opacity(0.6)` | `VehicleTheme.textTertiary` |
| 164 | `.white` (다시 시도 버튼) | `VehicleTheme.accentBright` |
| 167 | `.white.opacity(0.18)` | `VehicleTheme.accent.opacity(0.18)` |
| 220 | `Color.slate50` (`#Preview`) | `VehicleTheme.background` |

- [ ] **Step 5: `#Preview`에 다크를 켠다**

219~220행:

```swift
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
```

**이 계획이 고치는 모든 파일의 `#Preview`에 같은 두 줄을 넣는다.** 켜지 않으면 미리보기가 밝은 카드에 흰 글씨를 그려 아무것도 안 보인다.

### BatteryHealthCard.swift

- [ ] **Step 6: 색을 옮긴다**

68~77행의 `remainingColor`를 통째로 아래로 바꾼다:

```swift
    /// 90% 이상 민트, 80~90% 노랑, 80% 미만 빨강. 판정은 `HealthBand`가 한다 —
    /// **반올림한 값으로 갈라야** 옆에 찍히는 숫자와 색이 어긋나지 않는다.
    /// 색은 `VehicleTheme`이 고른다 — 잔량 링과 같은 축을 쓰기 위해서다.
    private var remainingColor: Color {
        VehicleTheme.color(for: HealthBand.of(remainingPercent))
    }
```

나머지:

| 행 | 기존 | 새 값 |
|---|---|---|
| 25, 38, 83, 120 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 30, 109 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 89, 117 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 130 | `.white` | `VehicleTheme.accentBright` |
| 133 | `Color.blue600` | `VehicleTheme.accent.opacity(0.18)` |
| 156 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### TirePressureCard.swift

- [ ] **Step 7: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 29, 35 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 50 | `.fill(Color.slate100)` | `.fill(VehicleTheme.tileFill)` |
| 55 | `Color.slate300` | `VehicleTheme.textTertiary` |
| 72, 90, 94 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 88 | `Color.orange700` | `VehicleTheme.warning` |
| 96 | `Color.green600` | `VehicleTheme.accent` |
| 151 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### VehicleStatusTab.swift

- [ ] **Step 8: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 40, 116, 167, 246 | `Color.red500` | `VehicleTheme.danger` |
| 85 | `Color.orange700` / `Color.slate500` | `VehicleTheme.warning` / `VehicleTheme.textSecondary` |
| 99 | `Color.orange700` | `VehicleTheme.warning` |
| 101 | `Color.orange100` | `VehicleTheme.warning.opacity(0.15)` |
| 257, 268, 276, 314, 325 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 309, 331 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 318 | `Color.slate100` | `VehicleTheme.tileFill` |

- [ ] **Step 9: 남은 밝은 토큰이 없는지 확인한다**

Run: `grep -n 'Color\.slate\|Color\.blue\|Color\.green\|Color\.orange\|Color\.red\|Color\.navy' WooriHaru/Views/Vehicle/BatteryNowCard.swift WooriHaru/Views/Vehicle/BatteryHealthCard.swift WooriHaru/Views/Vehicle/TirePressureCard.swift WooriHaru/Views/Vehicle/VehicleStatusTab.swift`

Expected: 출력 없음.

- [ ] **Step 10: 전체 테스트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED

- [ ] **Step 11: 커밋**

```bash
git add WooriHaru/Views/Vehicle/BatteryNowCard.swift WooriHaru/Views/Vehicle/BatteryHealthCard.swift WooriHaru/Views/Vehicle/TirePressureCard.swift WooriHaru/Views/Vehicle/VehicleStatusTab.swift
git commit -m "feat: 상태 탭 강조를 진한 패널에서 민트 링으로 옮긴다"
```

---

## Task 5: 타임라인과 주행 탭

**Files:**
- Modify: `WooriHaru/Views/Vehicle/StateTimelineChart.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleDriveTab.swift`
- Modify: `WooriHaru/Views/Vehicle/DriveStatsCard.swift`
- Modify: `WooriHaru/Views/Vehicle/DriveBucketCards.swift`
- Modify: `WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift`
- Modify: `WooriHaru/Views/Vehicle/DegradationTrendChart.swift`

**Interfaces:**
- Consumes: `VehicleTheme.*`, `VehicleTheme.color(for: TimelineKind)` (Task 1)
- Produces: 없음.

### StateTimelineChart.swift

- [ ] **Step 1: 상태 색을 테마로 넘긴다**

155~163행의 `private static func color(_ kind: TimelineKind) -> Color`를 통째로 바꾼다:

```swift
    /// **색을 여기서 고르지 않는다.** 띠와 범례가 같은 함수를 부르므로 한 곳에만 적혀야 하고,
    /// 다섯이 서로 다른지는 `VehicleThemeTests`가 지킨다.
    private static func color(_ kind: TimelineKind) -> Color {
        VehicleTheme.color(for: kind)
    }
```

- [ ] **Step 2: 남은 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 34, 114 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 49 | `Rectangle().fill(Color.slate100)` | `Rectangle().fill(VehicleTheme.tileFill)` |
| 94 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 209 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### VehicleDriveTab.swift

- [ ] **Step 3: 기간 칩을 민트로 바꾸고 색을 옮긴다**

56~66행:

```swift
                .foregroundStyle(selected ? VehicleTheme.accentBright : VehicleTheme.textSecondary)
```

63행 `Capsule().fill(Color.blue600)` → 채움을 옅게 하고 테두리를 준다. **탭바와 같은 어휘를 쓴다** — 두 곳이 「선택됨」을 다른 모양으로 말하면 안 된다:

```swift
                        Capsule()
                            .fill(VehicleTheme.accent.opacity(0.20))
                            .overlay(Capsule().strokeBorder(VehicleTheme.accent.opacity(0.45), lineWidth: 1))
```

65행 `Capsule().fill(Color.slate100)` → `Capsule().fill(VehicleTheme.tileFill)`

| 행 | 기존 | 새 값 |
|---|---|---|
| 19 | `Color.red500` | `VehicleTheme.danger` |
| 121, 137 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 131 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 141 | `Color.slate400` | `VehicleTheme.textTertiary` |

### DriveStatsCard.swift

- [ ] **Step 4: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 37 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 42 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 46 | `Color.slate100` | `VehicleTheme.tileFill` |
| 60 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### DriveBucketCards.swift

- [ ] **Step 5: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 25, 129 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 50, 96, 124 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 54 | `isBest ? Color.blue600 : Color.blue300` | `isBest ? VehicleTheme.accentBright : VehicleTheme.accentMuted` |
| 63, 109 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 101 | `bucket.driveCount == 0 ? Color.slate200 : Color.green600` | `bucket.driveCount == 0 ? VehicleTheme.trackFill : VehicleTheme.accent` |
| 173 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### DriveTimeHeatmap.swift

- [ ] **Step 6: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 30 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 35, 108 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 55 | `weekday == 0 \|\| weekday == 6 ? Color.orange700 : Color.slate500` | `... ? VehicleTheme.warning : VehicleTheme.textSecondary` |
| 97 | `return Color.slate100` (0인 칸) | `return VehicleTheme.tileFill` |
| 99 | `Color.blue600.opacity(0.15 + 0.85 * ratio)` | `VehicleTheme.accent.opacity(0.15 + 0.85 * ratio)` |
| 134 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

97행의 빈 칸은 `trackFill`(10%)이 아니라 `tileFill`(7%)이다 — **168칸이 격자로 깔리므로 트랙 하나짜리보다 옅어야 화면이 안 시끄럽다.**

### DegradationTrendChart.swift

- [ ] **Step 7: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 26, 62, 165 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 54 | `Color.blue600` | `VehicleTheme.accent` |
| 67, 157, 161 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 85 | `Color.slate300` (점선 격자) | `VehicleTheme.cardStroke` |
| 94 | `Color.blue500` (선) | `VehicleTheme.accent` |
| 100 | `isSelected ? Color.blue600 : Color.blue300` | `isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted` |
| 192 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

- [ ] **Step 8: 남은 밝은 토큰이 없는지 확인한다**

Run: `grep -nE '(^|[^A-Za-z0-9_])(Color)?\.(slate|blue|green|orange|red|navy)[0-9]+' WooriHaru/Views/Vehicle/StateTimelineChart.swift WooriHaru/Views/Vehicle/VehicleDriveTab.swift WooriHaru/Views/Vehicle/DriveStatsCard.swift WooriHaru/Views/Vehicle/DriveBucketCards.swift WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift WooriHaru/Views/Vehicle/DegradationTrendChart.swift`

Expected: 출력 없음.

- [ ] **Step 9: 전체 테스트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED

- [ ] **Step 10: 커밋**

```bash
git add WooriHaru/Views/Vehicle/StateTimelineChart.swift WooriHaru/Views/Vehicle/VehicleDriveTab.swift WooriHaru/Views/Vehicle/DriveStatsCard.swift WooriHaru/Views/Vehicle/DriveBucketCards.swift WooriHaru/Views/Vehicle/DriveTimeHeatmap.swift WooriHaru/Views/Vehicle/DegradationTrendChart.swift
git commit -m "feat: 타임라인과 주행 탭을 다크 팔레트로 옮긴다"
```

---

## Task 6: 요약 탭과 충전 화면

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleSummaryTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleTrendChart.swift`
- Modify: `WooriHaru/Views/Vehicle/ChargeTotalsCard.swift`
- Modify: `WooriHaru/Views/Charge/ChargeRow.swift`
- Modify: `WooriHaru/Views/Charge/ChargeCurveChart.swift`
- Modify: `WooriHaru/Views/Charge/ChargeDetailView.swift`

**Interfaces:**
- Consumes: `VehicleTheme.*`, `vehicleDarkTheme()` (Task 1)
- Produces: 없음 — 마지막 태스크다.

### VehicleSummaryTab.swift

- [ ] **Step 1: 히어로 카드를 다시 칠한다**

113~119행. 초록→파랑 그라디언트와 파란 그림자를 버리고 민트 기 도는 어두운 판으로 바꾼다. **요약 탭에서는 이 카드가 눈이 먼저 가는 자리이므로 다른 카드와 다르게 그린다** — 다만 상태 탭의 링만큼 빛나지는 않는다:

```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [VehicleTheme.accent.opacity(0.22), VehicleTheme.surfaceTint],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(VehicleTheme.cardStroke, lineWidth: 1)
        )
```

- [ ] **Step 2: 남은 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 37 | `Color.red500` | `VehicleTheme.danger` |
| 88 | `.white.opacity(0.8)` | `VehicleTheme.textSecondary` |
| 101 | `.white` | `VehicleTheme.textPrimary` |
| 129 | `.white` (칩 글자) | `VehicleTheme.textPrimary` |
| 133 | `.white.opacity(0.2)` (칩 바탕) | `VehicleTheme.cardStroke` |
| 151 | `delta >= 0 ? Color.red500 : Color.green600` | `delta >= 0 ? VehicleTheme.danger : VehicleTheme.accent` |
| 155 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 164, 196 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 169 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 184 | `Color.orange700` | `VehicleTheme.warning` |
| 186 | `Color.orange100` | `VehicleTheme.warning.opacity(0.15)` |

### VehicleTrendChart.swift

- [ ] **Step 3: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 22, 38, 41 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 29 | `Color.blue600` | `VehicleTheme.accent` |
| 69 | `AnyShapeStyle(Color.slate200)` (값 없음) | `AnyShapeStyle(VehicleTheme.trackFill)` |
| 70 | `AnyShapeStyle(isSelected ? Color.blue600 : Color.blue300)` | `AnyShapeStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)` |
| 74 | `isSelected ? Color.blue600 : Color.slate400` | `isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary` |

### ChargeTotalsCard.swift

- [ ] **Step 4: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 25, 57, 72, 83 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 31, 93 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 52, 88 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 61, 76 | `Color.slate100` | `VehicleTheme.tileFill` |
| 127 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### ChargeRow.swift

- [ ] **Step 5: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 16 | `Capsule().fill(Color.slate200)` (트랙) | `Capsule().fill(VehicleTheme.trackFill)` |
| 19 | `.fill(Color.slate300)` | `.fill(VehicleTheme.textTertiary)` |
| 23 | `.fill(Color.green600)` | `.fill(VehicleTheme.accent)` |
| 43 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 57, 75 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 67 | `item.cost == nil ? Color.orange700 : Color.slate900` | `item.cost == nil ? VehicleTheme.warning : VehicleTheme.textPrimary` |

### ChargeCurveChart.swift

- [ ] **Step 6: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 70, 137 | `Color.slate400` | `VehicleTheme.textTertiary` |
| 90 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 97 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 118 | `[Color.blue300.opacity(0.55), Color.blue300.opacity(0.05)]` | `[VehicleTheme.accent.opacity(0.45), VehicleTheme.accent.opacity(0.03)]` |
| 125 | `Color.blue600` | `VehicleTheme.accent` |
| 153 | `Color.slate50` | `VehicleTheme.background` + `.environment(\.vehicleDark, true)` |

### ChargeDetailView.swift

- [ ] **Step 7: 루트에 테마를 얹는다**

56행 `.glassScreenBackground()` 바로 다음 줄에 `.vehicleDarkTheme()`를 넣는다.

**이 화면은 시트로 열린다.** 환경값이 시트로 전달되는지에 기대지 않고 스스로 선언한다 — 한 줄 보험이고, 그 대신 전달 여부를 확인할 일이 없어진다.

- [ ] **Step 8: `ChargeCostEditSheet`도 어둡게 한다**

같은 파일의 `ChargeCostEditSheet`(282행 근처의 `body`). 이 시트는 **배경을 아예 안 깔고 있다** — 시스템 기본 흰 바탕이다. `.navigationTitle` 앞줄(`.padding(16)` 다음)에 두 줄을 더한다:

```swift
            .padding(16)
            .glassScreenBackground()
            .vehicleDarkTheme()
            .navigationTitle("금액 수정")
```

빼면 어두운 상세에서 「금액 수정」을 눌렀을 때 새하얀 시트가 올라온다.

- [ ] **Step 9: 색을 옮긴다**

| 행 | 기존 | 새 값 |
|---|---|---|
| 50, 295 | `Color.red500` | `VehicleTheme.danger` |
| 97 | `cost == nil ? Color.orange700 : Color.slate900` | `cost == nil ? VehicleTheme.warning : VehicleTheme.textPrimary` |
| 106, 110, 189, 200, 299 | `Color.slate500` | `VehicleTheme.textSecondary` |
| 185, 206 | `Color.slate900` | `VehicleTheme.textPrimary` |
| 290 | `Color.slate100` | `VehicleTheme.tileFill` |

284~289행의 `TextField`에도 `.foregroundStyle(VehicleTheme.textPrimary)`를 붙인다 — `ChargeCostQueueView`와 같은 이유다.

- [ ] **Step 10: 범위 전체에 밝은 토큰이 하나도 안 남았는지 확인한다**

Run: `grep -rnE '(^|[^A-Za-z0-9_])(Color)?\.(slate|blue|green|orange|red|navy)[0-9]+' --include='*.swift' WooriHaru/Views/Vehicle/ WooriHaru/Views/Charge/`

Expected: **출력 없음.** 하나라도 남으면 그 자리는 검은 바탕에 검은 글씨이거나 어두운 카드에 밝은 회색 타일이다.

- [ ] **Step 11: 밝은 갈래가 안 바뀌었는지 확인한다**

Run: `git diff develop --name-only -- WooriHaru/Views/ | grep -v 'Views/Vehicle/\|Views/Charge/\|Views/Components/Glass/'`

Expected: **출력 없음.** 차량·충전·공용 글래스 밖의 뷰 파일이 하나라도 나오면 범위를 벗어난 것이다.

- [ ] **Step 12: 전체 테스트**

Run: `xcodebuild test -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "Test run with|failed|error:|TEST SUCCEEDED|TEST FAILED" | tail -30`

Expected: TEST SUCCEEDED

- [ ] **Step 13: 커밋**

```bash
git add WooriHaru/Views/Vehicle/VehicleSummaryTab.swift WooriHaru/Views/Vehicle/VehicleTrendChart.swift WooriHaru/Views/Vehicle/ChargeTotalsCard.swift WooriHaru/Views/Charge/ChargeRow.swift WooriHaru/Views/Charge/ChargeCurveChart.swift WooriHaru/Views/Charge/ChargeDetailView.swift
git commit -m "feat: 요약 탭과 충전 화면을 다크 팔레트로 옮긴다"
```

---

## 사람이 확인할 것 (구현이 끝난 뒤)

- [ ] 가계부·식단·일정·수영·공부 화면이 **한 픽셀도 안 바뀌었는지**
- [ ] 차량 세 탭, 충전 상세, 금액 수정 시트, 금액 등록 큐가 **모두** 어두운지
- [ ] 민트 링이 화면에서 유일하게 빛나는지 — 탭바·기간 칩·히어로가 링보다 튀면 안 된다
- [ ] 잔량 20% 미만일 때 링이 빨강이고 **후광도 빨강**인지
- [ ] 24시간 띠에서 다섯 상태가 갈리는지, 충전 구간만 색을 가지는지
- [ ] 홈에서 차량으로 밀어 올릴 때 **뒤에 남은 홈 화면이 안 뒤집히는지**
- [ ] 금액 입력 키보드와 커서가 어두운 화면에 어울리는지
- [ ] `ContentUnavailableView`(「채울 게 없어요」·「기록이 없어요」)가 어둡게 나오는지

**구현 뒤 고친 것:** `online`을 처음에 `textSecondary.opacity(0.35)`로 뒀는데, 실기에서 보니
`offline`(흰색 18%)과 휘도가 1.5배밖에 안 벌어져 24pt짜리 띠에서 「깨어 있음」과 「연결 끊김」이
안 갈렸다. `0.50`으로 올려 넷의 사다리를 대략 두 배씩(0.08 → 0.18 → 0.38 → 0.76)으로 고르게 맞췄다.
위 코드 블록은 고친 값으로 적어 두었다.

**알려진 잔여물:** 요약 탭에서 연월을 고를 때 올라오는 `MonthPickerSheet`는 이 계획이 손대지 않는다 — 가계부·일정·달력 등 다섯 화면이 함께 쓰는 공용 시트다.

**다만 밝은 채로 남지는 않는다.** 시트는 띄운 화면의 환경을 물려받으므로 `colorScheme`이 다크로 전해진다. 시트 바탕과 피커 글자(`UIColor.label`)는 따라서 어두워지고, 「취소」(흰 알약에 진회색 글자)와 「확인」(진남색 알약에 흰 글자)만 색이 박혀 있어 그대로 남는다 — **둘 다 읽히기는 한다.** 어두운 시트에 밝은 알약 하나가 뜨는 어색함이 남고, 그것이 이 계획이 감수하는 값이다. 고치려면 저 다섯 화면의 몫을 먼저 정해야 한다.
