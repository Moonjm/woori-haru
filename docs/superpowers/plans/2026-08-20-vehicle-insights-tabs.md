# 차량 탭 개편 · 통계 화면 1단계 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 차량 미니앱의 탭을 `개요 / 통계 / 충전`으로 바꾸고, 서버를 전혀 건드리지 않은 채 차트를 5장에서 14장으로 늘린다.

**Architecture:** 손으로 그리는 차트를 카드마다 새로 짜는 대신 `Views/Vehicle/Charts/`에 원형 넷(막대·선·이중축·도넛)을 두고, 각 카드가 자기 도메인 타입을 `ChartPoint` 배열로 바꿔 넘긴다. 통계 탭은 `/tesla/drive-insights`와 `/tesla/summary`를 **병렬로 둘 다** 받아 「주행」·「충전」·「배터리」 세 섹션을 채운다.

**Tech Stack:** SwiftUI (iOS 26), `@Observable` 뷰모델, Swift Testing(`import Testing`·`@Test`·`#expect`), `Path`/`GeometryReader` 직접 그리기.

**Spec:** `docs/superpowers/specs/2026-08-20-vehicle-insights-tabs-design.md`

## Global Constraints

모든 태스크의 요구사항에 아래가 암묵적으로 포함된다.

- **Swift Charts를 들이지 않는다.** `Path`·`GeometryReader`·`RoundedRectangle`로 그린다.
- **탭은 셋이 상한이다.** `VehicleView`의 `Tab` 열거형에 네 번째를 더하지 않는다.
- **`nil`과 `0`을 갈라 그린다.** `nil`은 「기록이 없다」라 막대를 안 그리고(트랙만 남긴다), `0`은 「안 탔다」라 높이 3pt의 막대를 그린다.
- **차트 탭 제스처는 콜아웃만 바꾼다.** 달을 옮기거나 화면을 이동시키지 않는다.
- **나눗셈은 뷰가 아니라 `VehicleMath`나 뷰모델에서 한다.** 뷰에서 다시 계산하면 테스트하는 값과 화면 값이 갈린다.
- **기간 칩은 1단계에서 3개월/12개월 둘 그대로 둔다.** 넷으로 늘리는 것은 서버가 `months=0`을 받는 2단계다.
- **지도·차계부·자율주행(FSD)·주유비 절감액을 넣지 않는다.**
- 테스트 실행:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head`
- 커밋 메시지는 저장소 관례대로 **한국어 현재형 서술**이다(`feat: …를 …한다`).

---

## 파일 구조

**새로 만드는 것**

| 파일 | 책임 |
|---|---|
| `WooriHaru/Views/Vehicle/Charts/ChartPoint.swift` | 원형이 받는 한 점. 도메인 타입과 원형 사이의 경계 |
| `WooriHaru/Views/Vehicle/Charts/MonthlyBarChart.swift` | 월별 막대 한 줄 |
| `WooriHaru/Views/Vehicle/Charts/MonthlyLineChart.swift` | 월별 선 하나 |
| `WooriHaru/Views/Vehicle/Charts/MonthlyBarLineChart.swift` | 막대 + 선 이중축 |
| `WooriHaru/Views/Vehicle/Charts/DonutChart.swift` | 두 조각 비율 도넛 |
| `WooriHaru/Views/Vehicle/StatsDriveSection.swift` | 통계 탭 「주행」 섹션 |
| `WooriHaru/Views/Vehicle/StatsChargeSection.swift` | 통계 탭 「충전」 섹션 |
| `WooriHaru/Views/Vehicle/CostBreakdownCard.swift` | 「이번 달 충전비, 왜 달라졌을까」 |
| `WooriHaruTests/ChartPointTests.swift` | 원형 계산(비율·도메인) 테스트 |
| `WooriHaruTests/CostBreakdownTests.swift` | 충전비 3분해 테스트 |

**이름을 바꾸는 것** (`git mv`)

| 지금 | 바뀐 뒤 |
|---|---|
| `Views/Vehicle/VehicleStatusTab.swift` | `VehicleOverviewTab.swift` |
| `Views/Vehicle/VehicleDriveTab.swift` | `VehicleStatsTab.swift` |
| `Views/Vehicle/VehicleSummaryTab.swift` | `VehicleChargeTab.swift` |
| `ViewModels/VehicleDriveViewModel.swift` | `VehicleStatsViewModel.swift` |
| `WooriHaruTests/VehicleDriveTests.swift` | `VehicleStatsTests.swift` |

`VehicleStatusViewModel`·`VehicleSummaryViewModel`은 **이름을 바꾸지 않는다** — 각각 `/tesla/status`·`/tesla/summary` 응답을 그대로 반영하는 이름이고, 서버 계약이 바뀌지 않았다.

**고치는 것**

`Views/Vehicle/VehicleView.swift` · `Views/Vehicle/VehicleTrendChart.swift` · `Models/VehicleModels.swift`(`VehicleMath` 확장) · `Services/VehicleService.swift`는 손대지 않는다.

---

## Task 1: 탭 이름을 개요·통계·충전으로 바꾼다

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`
- Rename: `WooriHaru/Views/Vehicle/VehicleStatusTab.swift` → `VehicleOverviewTab.swift`
- Rename: `WooriHaru/Views/Vehicle/VehicleDriveTab.swift` → `VehicleStatsTab.swift`
- Rename: `WooriHaru/Views/Vehicle/VehicleSummaryTab.swift` → `VehicleChargeTab.swift`
- Rename: `WooriHaru/ViewModels/VehicleDriveViewModel.swift` → `VehicleStatsViewModel.swift`
- Rename: `WooriHaruTests/VehicleDriveTests.swift` → `VehicleStatsTests.swift`

**Interfaces:**
- Consumes: 없음 (첫 태스크)
- Produces: `enum Tab { case overview, stats, charge }`, `struct VehicleOverviewTab`, `struct VehicleStatsTab`, `struct VehicleChargeTab`, `final class VehicleStatsViewModel`. 이후 모든 태스크가 이 이름을 쓴다.

- [ ] **Step 1: 파일 이름을 바꾼다**

```bash
git mv WooriHaru/Views/Vehicle/VehicleStatusTab.swift  WooriHaru/Views/Vehicle/VehicleOverviewTab.swift
git mv WooriHaru/Views/Vehicle/VehicleDriveTab.swift   WooriHaru/Views/Vehicle/VehicleStatsTab.swift
git mv WooriHaru/Views/Vehicle/VehicleSummaryTab.swift WooriHaru/Views/Vehicle/VehicleChargeTab.swift
git mv WooriHaru/ViewModels/VehicleDriveViewModel.swift WooriHaru/ViewModels/VehicleStatsViewModel.swift
git mv WooriHaruTests/VehicleDriveTests.swift          WooriHaruTests/VehicleStatsTests.swift
```

- [ ] **Step 2: Xcode 타겟의 경로를 고친다**

`git mv`는 `project.pbxproj` 안의 경로를 못 고친다. 옛 참조를 지우고 새 경로를 등록한다.

```bash
# 옛 이름 참조가 남아 있는지 확인
grep -c "VehicleStatusTab\|VehicleDriveTab\|VehicleSummaryTab\|VehicleDriveViewModel" WooriHaru.xcodeproj/project.pbxproj
```

`sed`로 파일명만 바꾼다 — 경로 문자열과 이름 문자열이 같은 형태라 한 번에 처리된다.

```bash
sed -i '' \
  -e 's/VehicleStatusTab\.swift/VehicleOverviewTab.swift/g' \
  -e 's/VehicleDriveTab\.swift/VehicleStatsTab.swift/g' \
  -e 's/VehicleSummaryTab\.swift/VehicleChargeTab.swift/g' \
  -e 's/VehicleDriveViewModel\.swift/VehicleStatsViewModel.swift/g' \
  WooriHaru.xcodeproj/project.pbxproj
grep -c "VehicleOverviewTab.swift\|VehicleStatsTab.swift\|VehicleChargeTab.swift\|VehicleStatsViewModel.swift" WooriHaru.xcodeproj/project.pbxproj
```

기대: 마지막 `grep -c`가 **0이 아닐 것**(파일 하나가 `PBXFileReference`·`PBXBuildFile` 두 곳에 나오므로 보통 8이지만, 그룹 구조에 따라 다를 수 있다. 0이면 `sed`가 아무것도 못 바꾼 것이니 멈추고 `project.pbxproj`를 직접 본다).

- [ ] **Step 3: 타입 이름을 바꾼다**

각 파일 안의 `struct`/`class` 선언과 호출부를 전부 바꾼다.

```bash
grep -rl "VehicleStatusTab\|VehicleDriveTab\|VehicleSummaryTab\|VehicleDriveViewModel" WooriHaru WooriHaruTests \
| xargs sed -i '' \
  -e 's/VehicleStatusTab/VehicleOverviewTab/g' \
  -e 's/VehicleDriveTab/VehicleStatsTab/g' \
  -e 's/VehicleSummaryTab/VehicleChargeTab/g' \
  -e 's/VehicleDriveViewModel/VehicleStatsViewModel/g'
```

- [ ] **Step 4: `VehicleView`의 탭 열거형과 라벨을 고친다**

`WooriHaru/Views/Vehicle/VehicleView.swift`에서 `private enum Tab { case status, drive, summary }`를 바꾼다.

```swift
    private enum Tab { case overview, stats, charge }
```

`@State private var tab: Tab = .status`를 바꾼다.

```swift
    @State private var tab: Tab = .overview
```

스와이프 마스크의 조건을 바꾼다.

```swift
        .simultaneousGesture(monthSwipeGesture, including: tab == .charge ? .all : .subviews)
```

`content`의 `switch`에서 `case .status:` → `case .overview:`, `case .drive:` → `case .stats:`, `case .summary:` → `case .charge:`로 바꾸고, `driveViewModel`을 `statsViewModel`로 바꾼다(선언부 `@State private var driveViewModel = VehicleStatsViewModel()`도 함께).

`principalTitle`의 글자를 바꾼다.

```swift
    @ViewBuilder private var principalTitle: some View {
        switch tab {
        case .overview:
            Text("개요").font(.subheadline).fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textPrimary)
        case .stats:
            Text("통계").font(.subheadline).fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textPrimary)
        case .charge: monthSwitcher
        }
    }
```

- [ ] **Step 5: 탭바 라벨을 고친다**

`VehicleView.swift`의 `tabBar`에서 세 버튼의 글자와 `case`를 바꾼다. 지금 「상태 / 주행 / 요약」인 자리를 「개요 / 통계 / 충전」으로 바꾼다. SF Symbol도 뜻에 맞춘다 — 개요는 `car.fill`, 통계는 `chart.bar.fill`, 충전은 `bolt.fill`.

- [ ] **Step 6: 옛 이름이 남지 않았는지 확인한다**

```bash
grep -rn "VehicleStatusTab\|VehicleDriveTab\|VehicleSummaryTab\|VehicleDriveViewModel\|case \.status\|case \.drive\|case \.summary" WooriHaru WooriHaruTests
```

기대: 결과 없음. (`VehicleStatusViewModel`·`VehicleSummaryViewModel`은 그대로 남아야 하므로 위 패턴에 안 걸린다.)

- [ ] **Step 7: 빌드와 테스트가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`. 이 태스크는 이름만 바꾸므로 **기존 테스트가 하나도 깨지면 안 된다.**

- [ ] **Step 8: 커밋**

```bash
git add -A
git commit -m "refactor: 차량 탭을 개요·통계·충전으로 바꾼다"
```

---

## Task 2: 열화 추세를 개요에서 통계로 옮긴다

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleOverviewTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`

**Interfaces:**
- Consumes: Task 1의 `VehicleOverviewTab`·`VehicleStatsTab`
- Produces: `VehicleStatsTab`가 `healthViewModel: VehicleHealthViewModel`을 받는다. Task 8이 같은 초기화 구문을 쓴다.

- [ ] **Step 1: 개요 탭에서 열화 추세를 뗀다**

`VehicleOverviewTab.swift`의 `healthSection`에서 `DegradationTrendChart(...)` 호출과, 그 자리를 대신하던 `BatteryHealthPlaceholderCard` 중 **추세용 하나**를 지운다. `BatteryHealthCard`와 그에 딸린 플레이스홀더는 남긴다.

지운 뒤 `healthSection`은 「잔존율 카드 하나 + 그 카드의 플레이스홀더 갈래들」만 남는다.

- [ ] **Step 2: 통계 탭이 건강 뷰모델을 받게 한다**

`VehicleStatsTab.swift`의 프로퍼티에 더한다.

```swift
struct VehicleStatsTab: View {
    @Bindable var viewModel: VehicleStatsViewModel
    /// 「배터리」 섹션의 열화 추세만 쓴다. 잔존율 카드는 개요 탭에 남는다.
    @Bindable var healthViewModel: VehicleHealthViewModel
```

- [ ] **Step 3: 통계 탭에 「배터리」 섹션을 붙인다**

`VehicleStatsTab.swift`의 `content` 아래(자주 가는 곳 카드 다음)에 넣는다. 섹션 헤더는 Task 8에서 전체를 정리하므로 여기서는 차트만 붙인다.

```swift
    /// 열화 추세 — 「지금 어떤가」가 아니라 「어떻게 변해왔나」라 개요가 아니라 여기다.
    /// **기간 칩을 따르지 않는다** — 열화는 전 기간을 봐야 기울기가 보인다.
    @ViewBuilder private var batterySection: some View {
        if !healthViewModel.trendSegments.isEmpty {
            DegradationTrendChart(segments: healthViewModel.trendSegments,
                                  selectedKey: selectedHealthKey,
                                  onSelect: { selectedHealthKey = $0 })
        }
    }
```

`@State private var selectedHealthKey: String?`을 프로퍼티에 더한다.

프로퍼티 이름은 **`trendSegments`다**(`segments`가 아니다) — `VehicleHealthViewModel.swift:53`. 개요 탭이 `DegradationTrendChart`에 넘기던 인자를 그대로 옮긴다.

- [ ] **Step 4: `VehicleView`가 두 탭에 같은 뷰모델을 넘기게 한다**

`content`의 `case .stats:`를 고친다.

```swift
        case .stats:
            VehicleStatsTab(viewModel: statsViewModel, healthViewModel: healthViewModel)
                .task {
                    async let stats: Void = statsViewModel.load()
                    async let health: Void = healthViewModel.load()
                    _ = await (stats, health)
                }
```

`healthViewModel.load()`는 값이 있으면 다시 받지 않으므로(전 기간 집계) 두 탭을 오가도 중복 호출이 아니다.

- [ ] **Step 5: 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "refactor: 열화 추세를 개요에서 통계 탭으로 옮긴다"
```

---

## Task 3: 차트 원형의 경계 타입 `ChartPoint`를 만든다

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/ChartPoint.swift`
- Create: `WooriHaruTests/ChartPointTests.swift`

**Interfaces:**
- Consumes: 없음
- Produces: `struct ChartPoint: Identifiable, Equatable { let id: String; let label: String; let value: Decimal? }` 와 `enum ChartScale { static func ratio(_ value: Decimal?, max: Decimal) -> CGFloat }`. Task 4~6의 모든 원형이 이 둘을 쓴다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/ChartPointTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct ChartPointTests {
    /// 최댓값이 0이면 나누지 않는다 — 값이 전부 0인 기간에 0으로 나누는 길을 막는다.
    @Test func 최댓값이_0이면_비율도_0이다() {
        #expect(ChartScale.ratio(0, max: 0) == 0)
        #expect(ChartScale.ratio(5, max: 0) == 0)
    }

    /// nil은 「기록이 없다」라 막대를 그리지 않는다. 0은 「안 탔다」라 0 높이로 그린다.
    /// 둘 다 비율은 0이지만 그리는 쪽이 `value == nil`로 갈라 색을 다르게 준다.
    @Test func 기록이_없으면_비율이_0이다() {
        #expect(ChartScale.ratio(nil, max: 100) == 0)
        #expect(ChartScale.ratio(0, max: 100) == 0)
    }

    @Test func 값을_최댓값에_대한_비율로_바꾼다() {
        #expect(ChartScale.ratio(50, max: 100) == 0.5)
        #expect(ChartScale.ratio(100, max: 100) == 1.0)
    }

    /// 음수는 0으로 자른다 — 막대가 축 아래로 뻗으면 다른 막대와 높이를 견줄 수 없다.
    @Test func 음수는_0으로_자른다() {
        #expect(ChartScale.ratio(-10, max: 100) == 0)
    }

    /// 배열에서 최댓값을 뽑을 때 nil은 건너뛴다.
    @Test func 최댓값은_기록이_있는_달에서만_고른다() {
        let points = [
            ChartPoint(id: "2026-06", label: "6", value: nil),
            ChartPoint(id: "2026-07", label: "7", value: 42),
            ChartPoint(id: "2026-08", label: "8", value: 17),
        ]
        #expect(ChartScale.maxValue(points) == 42)
        #expect(ChartScale.maxValue([]) == 0)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `error: cannot find 'ChartScale' in scope` (컴파일 실패).

- [ ] **Step 3: 최소 구현을 쓴다**

`WooriHaru/Views/Vehicle/Charts/ChartPoint.swift`:

```swift
import SwiftUI

/// 차트 원형이 받는 한 점. **도메인 타입을 원형이 알지 않게 하는 경계다** —
/// 원형이 `VehiclePeriod`나 `TemperatureBucket`을 알면 그 원형은 한 곳에서만 쓰인다.
/// 각 카드가 자기 타입을 이 배열로 바꿔 넘긴다.
///
/// **`value`가 옵셔널인 것이 이 타입의 요점이다.** 「0은 안 탔다, nil은 기록이 없다」는
/// `VehiclePeriod`의 관례가 차트에서도 유지돼야 한다 — 기록이 없는 달을 건너뛰면
/// 계절 비교가 어긋나므로 자리는 지키되 막대를 안 그린다.
struct ChartPoint: Identifiable, Equatable {
    /// 고유 키. 월별 차트에서는 `yearMonth`("2026-08")다.
    let id: String
    /// x축에 적는 짧은 글자. 월별 차트에서는 달 번호("8")다.
    let label: String
    let value: Decimal?
}

/// 값 → 화면 비율. **원형 넷이 같은 규칙을 쓴다** — 규칙을 원형마다 두면
/// 한쪽만 고쳤을 때 나란히 놓인 차트 둘의 높이가 서로 다른 뜻을 갖는다.
enum ChartScale {
    /// 기록이 있는 점 중 최댓값. 하나도 없으면 0이다.
    static func maxValue(_ points: [ChartPoint]) -> Decimal {
        points.compactMap(\.value).max() ?? 0
    }

    /// 0…1. **분모가 0이면 나누지 않고, 음수는 0으로 자른다.**
    static func ratio(_ value: Decimal?, max: Decimal) -> CGFloat {
        guard let value, max > 0, value > 0 else { return 0 }
        return CGFloat(truncating: (value / max) as NSDecimalNumber)
    }
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Vehicle/Charts/ChartPoint.swift WooriHaruTests/ChartPointTests.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 차트 원형이 쓰는 경계 타입 ChartPoint를 둔다"
```

---

## Task 4: 월별 막대 원형을 뽑고 기존 차트를 그 위에 얹는다

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/MonthlyBarChart.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleTrendChart.swift`

**Interfaces:**
- Consumes: `ChartPoint`, `ChartScale` (Task 3)
- Produces: `struct MonthlyBarChart: View { let points: [ChartPoint]; let selectedID: String?; let onSelect: (String) -> Void; var barHeight: CGFloat = 72 }`. Task 8·9가 이 초기화 구문을 그대로 쓴다.

- [ ] **Step 1: 원형을 만든다**

`WooriHaru/Views/Vehicle/Charts/MonthlyBarChart.swift`:

```swift
import SwiftUI

/// 월별 막대 한 줄. **카드가 아니라 막대만 그린다** — 제목·콜아웃·`GlassCard`는 부르는 쪽이 얹는다.
/// 원형이 카드까지 그리면 카드 구성이 조금씩 다른 일곱 자리에서 전부 예외가 생긴다.
///
/// **탭은 콜아웃만 바꾼다**(`onSelect`). 화면을 옮기거나 달을 바꾸지 않는다 —
/// `VehicleTrendChart`가 세운 규칙이고, 차트가 열넷으로 늘어도 같아야 읽을 수 있다.
struct MonthlyBarChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var barHeight: CGFloat = 72

    var body: some View {
        let maxValue = ChartScale.maxValue(points)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(points) { point in
                bar(point, maxValue: maxValue)
            }
        }
        .frame(height: barHeight + 24)
    }

    private func bar(_ point: ChartPoint, maxValue: Decimal) -> some View {
        let isSelected = point.id == selectedID
        let ratio = ChartScale.ratio(point.value, max: maxValue)
        return VStack(spacing: 5) {
            Spacer(minLength: 0)
            // 기록이 없는 달도 자리를 지킨다 — 건너뛰면 계절 비교가 어긋난다.
            // 그 자리는 트랙 색이라 「0을 기록한 달」과 갈린다.
            RoundedRectangle(cornerRadius: 4)
                .fill(point.value == nil
                      ? AnyShapeStyle(VehicleTheme.trackFill)
                      : AnyShapeStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted))
                .frame(height: max(3, ratio * barHeight))
            Text(point.label)
                .font(.system(size: 9, weight: isSelected ? .heavy : .regular))
                .foregroundStyle(isSelected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { onSelect(point.id) }
    }
}

#Preview("월별 막대") {
    let values: [Decimal?] = [nil, 32700, 41200, 0, 38400, 52300, 47100, 39900, 44300, 51800, 36200, 42900]
    let points = values.enumerated().map { index, value in
        ChartPoint(id: String(format: "2026-%02d", index + 1), label: "\(index + 1)", value: value)
    }
    return VStack(spacing: 12) {
        MonthlyBarChart(points: points, selectedID: "2026-06") { _ in }
        // 값이 전부 0인 기간 — 0으로 나누지 않는지 본다.
        MonthlyBarChart(points: points.map { ChartPoint(id: $0.id, label: $0.label, value: 0) },
                        selectedID: nil) { _ in }
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
```

- [ ] **Step 2: `VehicleTrendChart`를 원형 위에 얹는다**

`WooriHaru/Views/Vehicle/VehicleTrendChart.swift`의 `body` 안 `HStack(alignment: .bottom, spacing: 5) { ... }.frame(height: 96)` 블록과 `private func bar(...)` 전체를 지우고 원형 호출로 바꾼다.

```swift
                MonthlyBarChart(
                    points: trend.map {
                        ChartPoint(id: $0.yearMonth, label: "\($0.monthNumber)", value: $0.cost)
                    },
                    selectedID: selectedKey,
                    onSelect: onSelect
                )
```

`import SwiftUI` 아래 KDoc에 한 줄 더한다.

```swift
/// **막대는 `MonthlyBarChart`가 그린다.** 이 파일에 남는 것은 제목과 콜아웃이다.
```

- [ ] **Step 3: 기존 동작이 그대로인지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`. 막대 높이가 `96`에서 `72 + 24`로 계산이 바뀌었지만 총 높이는 같다.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "refactor: 월별 막대를 MonthlyBarChart 원형으로 뽑는다"
```

---

## Task 5: 월별 선 원형을 만든다

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/MonthlyLineChart.swift`

**Interfaces:**
- Consumes: `ChartPoint`, `ChartScale` (Task 3)
- Produces: `struct MonthlyLineChart: View { let points: [ChartPoint]; let selectedID: String?; let onSelect: (String) -> Void; var height: CGFloat = 110 }`. Task 8·9가 쓴다.

`DegradationTrendChart`는 y축이 0에서 시작하지 않고 신차 기준선을 함께 그리는 특수한 차트라 **이 원형으로 갈아끼우지 않는다.** 이 원형은 0에서 시작하는 선(누적 주행거리·효율 추세·누적 충전비)용이다.

- [ ] **Step 1: 원형을 만든다**

`WooriHaru/Views/Vehicle/Charts/MonthlyLineChart.swift`:

```swift
import SwiftUI

/// 월별 선 하나. **y축이 0에서 시작한다** — 누적값과 추세를 그리는 자리라 0이 뜻을 갖는다.
/// 0에서 시작하지 않아야 하는 차트(열화 추세)는 `DegradationTrendChart`가 따로 그린다.
///
/// **기록이 없는 달에서 선을 끊는다.** 이어 버리면 없는 달을 지나간 선이 「그 달에도 이만큼」으로
/// 읽힌다. 끊긴 자리는 x 간격으로만 남는다.
struct MonthlyLineChart: View {
    let points: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var height: CGFloat = 110

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                plot(in: proxy.size)
            }
            .frame(height: height)

            HStack(spacing: 5) {
                ForEach(points) { point in
                    Text(point.label)
                        .font(.system(size: 9, weight: point.id == selectedID ? .heavy : .regular))
                        .foregroundStyle(point.id == selectedID
                                         ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 연속한 점들의 묶음. 기록이 없는 달에서 갈린다.
    private var segments: [[(index: Int, value: Decimal)]] {
        var result: [[(index: Int, value: Decimal)]] = []
        var current: [(index: Int, value: Decimal)] = []
        for (index, point) in points.enumerated() {
            if let value = point.value {
                current.append((index, value))
            } else if !current.isEmpty {
                result.append(current)
                current = []
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func plot(in size: CGSize) -> some View {
        let maxValue = ChartScale.maxValue(points)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                // 점이 하나뿐인 구간은 선이 안 되므로 점만 남는다(아래 ForEach가 그린다).
                Path { path in
                    for (order, item) in segment.enumerated() {
                        let point = position(index: item.index, value: item.value,
                                             maxValue: maxValue, in: size)
                        if order == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(VehicleTheme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(points) { point in
                if let value = point.value {
                    let isSelected = point.id == selectedID
                    Circle()
                        .fill(isSelected ? VehicleTheme.accentBright : VehicleTheme.accentMuted)
                        .frame(width: isSelected ? 9 : 5, height: isSelected ? 9 : 5)
                        .position(position(index: points.firstIndex(of: point) ?? 0,
                                           value: value, maxValue: maxValue, in: size))
                }
            }
        }
        .contentShape(.rect)
        .onTapGesture { location in
            guard !points.isEmpty else { return }
            let step = size.width / CGFloat(max(1, points.count - 1))
            let index = min(points.count - 1, max(0, Int((location.x / max(1, step)).rounded())))
            onSelect(points[index].id)
        }
    }

    private func position(index: Int, value: Decimal, maxValue: Decimal, in size: CGSize) -> CGPoint {
        // 점이 하나뿐이면 왼쪽 끝에 붙는 대신 가운데에 찍는다.
        let x = points.count <= 1
            ? size.width / 2
            : size.width * CGFloat(index) / CGFloat(points.count - 1)
        let ratio = ChartScale.ratio(value, max: maxValue)
        return CGPoint(x: x, y: size.height * (1 - ratio))
    }
}

#Preview("월별 선") {
    let values: [Decimal?] = [820, 910, nil, 1040, 980, 1120, 1310, 1180, 1240, 1090, 1350, 1280]
    let points = values.enumerated().map { index, value in
        ChartPoint(id: String(format: "2026-%02d", index + 1), label: "\(index + 1)", value: value)
    }
    return VStack(spacing: 12) {
        MonthlyLineChart(points: points, selectedID: "2026-07") { _ in }
        // 점이 하나뿐 — 가운데에 찍히는지 본다.
        MonthlyLineChart(points: [points[3]], selectedID: nil) { _ in }
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
```

- [ ] **Step 2: 빌드가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "feat: 월별 선 원형 MonthlyLineChart를 둔다"
```

---

## Task 6: 이중축 원형과 도넛 원형을 만든다

**Files:**
- Create: `WooriHaru/Views/Vehicle/Charts/MonthlyBarLineChart.swift`
- Create: `WooriHaru/Views/Vehicle/Charts/DonutChart.swift`

**Interfaces:**
- Consumes: `ChartPoint`, `ChartScale` (Task 3)
- Produces:
  - `struct MonthlyBarLineChart: View { let bars: [ChartPoint]; let line: [ChartPoint]; let selectedID: String?; let onSelect: (String) -> Void }`
  - `struct DonutChart: View { let slices: [DonutChart.Slice] }`, `struct DonutChart.Slice { let label: String; let value: Decimal; let color: Color }`

- [ ] **Step 1: 이중축 원형을 만든다**

`WooriHaru/Views/Vehicle/Charts/MonthlyBarLineChart.swift`:

```swift
import SwiftUI

/// 막대 + 선 이중축. **두 축의 눈금을 화면에 적지 않는다** — 단위가 다른 두 계열을 겹치는
/// 자리라 눈금 둘을 다 적으면 카드가 숫자로 덮인다. 정확한 값은 콜아웃이 말한다.
///
/// `bars`와 `line`은 **같은 순서·같은 id**여야 한다. 부르는 쪽이 같은 배열에서 만든다.
struct MonthlyBarLineChart: View {
    let bars: [ChartPoint]
    let line: [ChartPoint]
    let selectedID: String?
    let onSelect: (String) -> Void
    var height: CGFloat = 96

    var body: some View {
        let barMax = ChartScale.maxValue(bars)
        let lineMax = ChartScale.maxValue(line)
        VStack(spacing: 5) {
            // **탭 폭을 GeometryReader에서 받는다.** 화면 폭(`UIScreen`)으로 나누면
            // 카드 안쪽 여백만큼 어긋나 오른쪽 끝 달이 안 잡힌다.
            GeometryReader { proxy in
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(bars) { point in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(point.value == nil
                                      ? AnyShapeStyle(VehicleTheme.trackFill)
                                      : AnyShapeStyle(point.id == selectedID
                                                      ? VehicleTheme.accentBright : VehicleTheme.accentMuted))
                                .frame(height: max(3, ChartScale.ratio(point.value, max: barMax) * height))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: height, alignment: .bottom)

                    linePath(in: proxy.size, maxValue: lineMax)
                }
                .contentShape(.rect)
                .onTapGesture { location in
                    guard !bars.isEmpty else { return }
                    let slot = proxy.size.width / CGFloat(bars.count)
                    let index = min(bars.count - 1, max(0, Int(location.x / max(1, slot))))
                    onSelect(bars[index].id)
                }
            }
            .frame(height: height)

            HStack(spacing: 5) {
                ForEach(bars) { point in
                    Text(point.label)
                        .font(.system(size: 9, weight: point.id == selectedID ? .heavy : .regular))
                        .foregroundStyle(point.id == selectedID
                                         ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 선은 **기록이 있는 점만 잇는다.** 막대와 달리 자리를 비워 두지 않고 건너뛴다 —
    /// 두 계열 중 하나만 빈 달이 있을 수 있는데, 선을 0으로 떨어뜨리면 없는 값이 있는 값이 된다.
    private func linePath(in size: CGSize, maxValue: Decimal) -> some View {
        Path { path in
            var started = false
            for (index, point) in line.enumerated() {
                guard let value = point.value else { started = false; continue }
                let x = line.count <= 1
                    ? size.width / 2
                    : size.width * CGFloat(index) / CGFloat(line.count - 1)
                let y = size.height * (1 - ChartScale.ratio(value, max: maxValue))
                let cgPoint = CGPoint(x: x, y: y)
                if started { path.addLine(to: cgPoint) } else { path.move(to: cgPoint); started = true }
            }
        }
        .stroke(VehicleTheme.warning,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

#Preview("이중축") {
    let kwh: [Decimal?] = [120, 142, nil, 165, 151, 138, 172, 160, 149, 155, 168, 158]
    let cost: [Decimal?] = [26000, 31000, nil, 35800, 32700, 29900, 38400, 34100, 32000, 33500, 36900, 34700]
    let bars = kwh.enumerated().map { i, v in
        ChartPoint(id: String(format: "2026-%02d", i + 1), label: "\(i + 1)", value: v)
    }
    let line = cost.enumerated().map { i, v in
        ChartPoint(id: String(format: "2026-%02d", i + 1), label: "\(i + 1)", value: v)
    }
    return MonthlyBarLineChart(bars: bars, line: line, selectedID: "2026-07") { _ in }
        .padding(16)
        .background(VehicleTheme.background)
        .environment(\.vehicleDark, true)
}
```

`VehicleTheme.warning`은 이미 있다(`VehicleTheme.swift`). **새 색을 더하지 않는다** — 막대가 `accent` 계열이라 선은 확실히 갈리는 색이어야 하고, `warning`이 그 자리다.

- [ ] **Step 2: 도넛 원형을 만든다**

`WooriHaru/Views/Vehicle/Charts/DonutChart.swift`:

```swift
import SwiftUI

/// 두어 조각짜리 비율 도넛. **조각이 셋을 넘으면 쓰지 말 것** — 각도로 크기를 견주는 것은
/// 사람이 잘 못한다. 급속/완속처럼 「둘 중 어느 쪽이 큰가」에만 쓴다.
///
/// 가운데를 비우고 그 자리에 총계를 적는 것은 부르는 쪽이 `overlay`로 얹는다.
struct DonutChart: View {
    struct Slice: Identifiable, Equatable {
        let label: String
        let value: Decimal
        let color: Color
        var id: String { label }
    }

    let slices: [Slice]
    var lineWidth: CGFloat = 18
    var size: CGFloat = 96

    private var total: Decimal { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        ZStack {
            // 총합이 0이면 조각을 그리지 않고 트랙만 남긴다 — 0으로 나누는 길을 막는다.
            Circle()
                .strokeBorder(VehicleTheme.trackFill, lineWidth: lineWidth)

            if total > 0 {
                ForEach(Array(offsets.enumerated()), id: \.offset) { _, item in
                    Circle()
                        .trim(from: item.start, to: item.end)
                        .stroke(item.slice.color,
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90)) // 12시에서 시작한다
                        .padding(lineWidth / 2)
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var offsets: [(slice: Slice, start: CGFloat, end: CGFloat)] {
        var cursor: CGFloat = 0
        return slices.map { slice in
            let fraction = ChartScale.ratio(slice.value, max: total)
            let start = cursor
            cursor += fraction
            return (slice, start, min(1, cursor))
        }
    }
}

#Preview("도넛") {
    VStack(spacing: 16) {
        DonutChart(slices: [
            .init(label: "급속", value: 1840, color: VehicleTheme.accentBright),
            .init(label: "완속", value: 4620, color: VehicleTheme.accentMuted),
        ])
        // 총합 0 — 트랙만 남는지 본다.
        DonutChart(slices: [
            .init(label: "급속", value: 0, color: VehicleTheme.accentBright),
            .init(label: "완속", value: 0, color: VehicleTheme.accentMuted),
        ])
    }
    .padding(16)
    .background(VehicleTheme.background)
    .environment(\.vehicleDark, true)
}
```

- [ ] **Step 3: 빌드가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "feat: 이중축·도넛 차트 원형을 둔다"
```

---

## Task 7: `VehicleMath`에 누적합과 충전비 3분해를 더한다

**Files:**
- Modify: `WooriHaru/Models/VehicleModels.swift` (`enum VehicleMath`)
- Create: `WooriHaruTests/CostBreakdownTests.swift`

**Interfaces:**
- Consumes: `VehiclePeriod` (기존)
- Produces:
  - `static func runningTotals(_ values: [Decimal?]) -> [Decimal?]`
  - `struct CostBreakdown: Equatable { let total: Decimal; let distance: Decimal; let efficiency: Decimal; let unitPrice: Decimal }`
  - `static func costBreakdown(current: VehiclePeriod, previous: VehiclePeriod) -> CostBreakdown?`
  Task 8이 `runningTotals`를, Task 11이 `costBreakdown`을 쓴다.

**분해식.** 그 달 충전비는 `충전량 × 충전량당 단가`이고, 충전량은 `주행거리 ÷ 전비`다. 세 항의 곱이 정확히 비용이므로 **분해가 남김없이 맞아떨어진다.**

```
e = energyAddedKwh,  p = cost / e,  d = distanceKm,  eff = d / e   (km/kWh)

거리 효과   = (d₁ − d₀) / eff₀ × p₀
전비 효과   = (e₁ − d₁ / eff₀) × p₀
단가 효과   = e₁ × (p₁ − p₀)
합          = e₁p₁ − e₀p₀ = cost₁ − cost₀   ✔
```

**여기 단가는 `cost / energyAddedKwh`다.** 누적 카드의 `wonPerKwh`(분모가 `energyUsedKwh`, 벽에서 뽑아쓴 양)와 **다른 값이다** — 세 항의 곱이 비용이 되려면 분모가 `energyAdded`여야 하기 때문이다. 화면에는 「충전량 1kWh당」이라고 적어 구분한다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/CostBreakdownTests.swift`:

```swift
import Foundation
import Testing
@testable import WooriHaru

struct CostBreakdownTests {
    private func period(_ ym: String, km: Decimal?, kwh: Decimal?, cost: Decimal?) -> VehiclePeriod {
        VehiclePeriod(yearMonth: ym, distanceKm: km, drivingMin: nil, driveCount: nil,
                      energyAddedKwh: kwh, energyUsedKwh: nil, cost: cost, chargeCount: nil)
    }

    /// 누적합은 기록이 없는 달을 건너뛰고 직전 누적을 이어 간다 —
    /// **그 달을 nil로 두면 선이 끊긴다.** 누적은 안 탄 달에도 값이 있다.
    @Test func 누적합은_기록이_없는_달을_건너뛴다() {
        #expect(VehicleMath.runningTotals([100, nil, 50]) == [100, nil, 150])
        #expect(VehicleMath.runningTotals([nil, 40]) == [nil, 40])
        #expect(VehicleMath.runningTotals([]) == [])
        // 0은 「안 탔다」라 누적이 그대로 이어진다.
        #expect(VehicleMath.runningTotals([100, 0, 50]) == [100, 100, 150])
    }

    /// 세 효과의 합이 총 증감과 정확히 같아야 한다 — 어긋나면 화면이
    /// 「▲18,400원인데 항을 더하면 17,900원」이라고 말하게 된다.
    @Test func 세_효과의_합이_총_증감과_같다() throws {
        let prev = period("2026-07", km: 620, kwh: 115, cost: 22770)
        let curr = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let result = VehicleMath.costBreakdown(current: curr, previous: prev)
        let breakdown = try #require(result)

        #expect(breakdown.total == 32700 - 22770)
        let sum = breakdown.distance + breakdown.efficiency + breakdown.unitPrice
        // Decimal 나눗셈 오차를 감안해 1원 안쪽이면 같다고 본다.
        #expect(abs(sum - breakdown.total) < 1)
    }

    /// 재료가 하나라도 없거나 0이면 분해하지 않는다 — 0으로 나누는 길과
    /// 「기록 없는 달과 견줬다」는 두 함정을 여기서 막는다.
    @Test func 재료가_없으면_분해하지_않는다() {
        let ok = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let noPrevCost = period("2026-07", km: 620, kwh: 115, cost: nil)
        let zeroKwh    = period("2026-07", km: 620, kwh: 0, cost: 22770)
        let noDistance = period("2026-07", km: nil, kwh: 115, cost: 22770)

        #expect(VehicleMath.costBreakdown(current: ok, previous: noPrevCost) == nil)
        #expect(VehicleMath.costBreakdown(current: ok, previous: zeroKwh) == nil)
        #expect(VehicleMath.costBreakdown(current: ok, previous: noDistance) == nil)
        #expect(VehicleMath.costBreakdown(current: noPrevCost, previous: ok) == nil)
    }

    /// 아무것도 안 바뀌면 세 효과가 전부 0이다.
    @Test func 같은_달이면_효과가_전부_0이다() throws {
        let p = period("2026-08", km: 780, kwh: 153, cost: 32700)
        let breakdown = try #require(VehicleMath.costBreakdown(current: p, previous: p))
        #expect(breakdown.total == 0)
        #expect(breakdown.distance == 0)
        #expect(breakdown.efficiency == 0)
        #expect(breakdown.unitPrice == 0)
    }
}
```

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `error: type 'VehicleMath' has no member 'runningTotals'`.

- [ ] **Step 3: 최소 구현을 쓴다**

`WooriHaru/Models/VehicleModels.swift`의 `enum VehicleMath` 안, `avgYearlyDistanceKm` 아래에 더한다.

```swift
    /// 누적합. **기록이 없는 달(`nil`)은 자리를 지키되 누적을 끊지 않는다** —
    /// 그 달을 0으로 읽으면 누적선이 주저앉고, 건너뛰어 배열에서 빼면 x축이 어긋난다.
    /// 「값 없음」은 그 달의 점만 없는 것이지 그때까지 간 거리가 없어지는 것이 아니다.
    static func runningTotals(_ values: [Decimal?]) -> [Decimal?] {
        var sum: Decimal?
        return values.map { value in
            guard let value else { return nil }
            let next = (sum ?? 0) + value
            sum = next
            return next
        }
    }

    /// 그 달 충전비가 지난달과 달라진 이유를 셋으로 쪼갠다.
    ///
    /// **세 효과의 합이 총 증감과 정확히 같다.** 충전비 = 충전량 × 단가이고
    /// 충전량 = 주행거리 ÷ 전비이므로, 항을 차례로 고정해 가면 남김없이 갈린다.
    ///
    /// **여기 단가는 `cost ÷ energyAddedKwh`다** — 누적 카드의 `wonPerKwh`(분모가
    /// 벽에서 뽑아쓴 `energyUsedKwh`)와 다른 값이다. 세 항의 곱이 비용이 되려면
    /// 분모가 차에 들어간 양이어야 한다. 화면에는 「충전량 1kWh당」이라고 적어 구분한다.
    static func costBreakdown(current: VehiclePeriod, previous: VehiclePeriod) -> CostBreakdown? {
        guard let d1 = current.distanceKm, let e1 = current.energyAddedKwh, let c1 = current.cost,
              let d0 = previous.distanceKm, let e0 = previous.energyAddedKwh, let c0 = previous.cost,
              d1 > 0, e1 > 0, d0 > 0, e0 > 0
        else { return nil }

        let p0 = c0 / e0                 // 지난달 충전량당 단가
        let p1 = c1 / e1
        let eff0 = d0 / e0               // 지난달 전비(km/kWh)

        let distance   = (d1 - d0) / eff0 * p0
        let efficiency = (e1 - d1 / eff0) * p0
        let unitPrice  = e1 * (p1 - p0)

        return CostBreakdown(total: c1 - c0,
                             distance: distance,
                             efficiency: efficiency,
                             unitPrice: unitPrice)
    }
```

같은 파일의 `VehicleMath` **바깥**(파일 끝)에 타입을 더한다.

```swift
/// 충전비 증감의 세 갈래. 부호는 **비용 기준**이다 — 양수면 그만큼 더 썼다는 뜻이고,
/// `efficiency`가 양수면 전비가 나빠져 돈이 더 들었다는 말이다.
struct CostBreakdown: Equatable {
    /// 이번 달 − 지난달.
    let total: Decimal
    let distance: Decimal
    let efficiency: Decimal
    let unitPrice: Decimal
}
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: 누적합과 충전비 3분해를 VehicleMath에 더한다"
```

---

## Task 8: 통계 탭이 12개월 추이를 함께 받는다

**Files:**
- Modify: `WooriHaru/ViewModels/VehicleStatsViewModel.swift`
- Modify: `WooriHaruTests/VehicleStatsTests.swift`

**Interfaces:**
- Consumes: `VehicleService.fetchSummary(yearMonth:)` (기존), `VehicleMath.runningTotals` (Task 7)
- Produces: `VehicleStatsViewModel`의 파생 프로퍼티 여섯 — `distancePoints`·`driveCountPoints`·`drivingMinPoints`·`cumulativeDistancePoints`·`efficiencyPoints`·`energyPoints`·`costPoints`, 그리고 `var hasTrend: Bool`. Task 9·10이 쓴다.

**왜 `/tesla/summary`를 한 번 더 부르는가.** `VehicleSummaryViewModel`이 이미 `trend`를 갖고 있지만, 그 뷰모델의 `trend`는 **선택한 달 기준 12개월**이라 충전 탭에서 달을 옮기면 통계 탭의 창까지 따라 움직인다. 통계는 늘 「이번 달 기준 12개월」이어야 하므로 자기 응답을 따로 받는다. 2단계에서 이 자리가 `/tesla/insights`로 갈아끼워진다.

- [ ] **Step 1: 실패하는 테스트를 쓴다**

`WooriHaruTests/VehicleStatsTests.swift` 끝에 더한다.

```swift
    /// 세 달 — 가운데가 기록 없는 달이다.
    private nonisolated static func stubTrend(_ mock: MockAPIClient) {
        let june = VehiclePeriod(yearMonth: "2026-06", distanceKm: 620, drivingMin: 880,
                                 driveCount: 34, energyAddedKwh: 115, energyUsedKwh: 126,
                                 cost: 22770, chargeCount: 5)
        let july = VehiclePeriod(yearMonth: "2026-07", distanceKm: nil, drivingMin: nil,
                                 driveCount: nil, energyAddedKwh: nil, energyUsedKwh: nil,
                                 cost: nil, chargeCount: nil)
        let august = VehiclePeriod(yearMonth: "2026-08", distanceKm: 780, drivingMin: 1120,
                                   driveCount: 41, energyAddedKwh: 153, energyUsedKwh: 161,
                                   cost: 32700, chargeCount: 7)
        mock.stubGet("/tesla/summary", result: DataResponse<VehicleSummaryResponse>(
            data: VehicleSummaryResponse(month: august, previous: june,
                                         trend: [june, july, august], charges: [])
        ))
    }

    private nonisolated static func stubEmptyInsights(_ mock: MockAPIClient) {
        mock.stubGet("/tesla/drive-insights", result: DataResponse<DriveInsightsResponse>(
            data: DriveInsightsResponse(months: 12, efficiencyKwhPerKm: nil,
                                        temperatureBuckets: [], driveTimes: [],
                                        distanceBuckets: [], places: [], maxSpeedKmh: nil,
                                        totalDistanceKm: nil, recordedMonths: nil)
        ))
    }

    /// 통계 탭은 주행 인사이트와 12개월 추이를 **둘 다** 받는다.
    @Test func 추이를_받아_월별_점으로_바꾼다() async {
        let mock = MockAPIClient()
        Self.stubEmptyInsights(mock)
        Self.stubTrend(mock)
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(viewModel.hasTrend)
        #expect(viewModel.distancePoints.count == 3)
        #expect(viewModel.distancePoints[0].label == "6")
        #expect(viewModel.distancePoints[1].value == nil)      // 기록 없는 달은 nil로 남는다
        // 누적은 기록 없는 달을 건너뛰고 이어 간다.
        #expect(viewModel.cumulativeDistancePoints[2].value == 620 + 780)
        #expect(viewModel.cumulativeDistancePoints[1].value == nil)
    }

    /// 추이를 못 받아도 주행 카드는 그린다 —
    /// 「못 받음」을 「기록 없음」으로 뭉개지 않는 관례를 두 응답 사이에도 지킨다.
    @Test func 추이를_못_받아도_주행_섹션은_산다() async {
        let mock = MockAPIClient()
        Self.stubEmptyInsights(mock)
        mock.setError(MockAPIClient.MockAPIError.forced, for: "GET /tesla/summary")
        let viewModel = VehicleStatsViewModel(service: VehicleService(api: mock))

        await viewModel.load()

        #expect(!viewModel.hasTrend)
        #expect(viewModel.distancePoints.isEmpty)
        #expect(viewModel.insights != nil)
        // 추이 실패는 배너를 세우지 않는다.
        #expect(viewModel.errorMessage == nil)
    }
```

`DriveInsightsResponse`·`VehiclePeriod`의 인자 순서는 `Models/`의 선언과 정확히 맞춰야 한다 — 위 코드는 `DriveInsightsModels.swift`·`VehicleModels.swift`의 현재 선언 순서를 따랐다. 컴파일 오류가 나면 그 선언을 보고 맞춘다.

- [ ] **Step 2: 테스트가 실패하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `error: value of type 'VehicleStatsViewModel' has no member 'hasTrend'`.

- [ ] **Step 3: 뷰모델에 추이를 더한다**

`WooriHaru/ViewModels/VehicleStatsViewModel.swift`의 저장 프로퍼티에 더한다.

```swift
    /// **기간 칩을 따르지 않는다** — 늘 이번 달 기준 12개월이다.
    /// 충전 탭의 `VehicleSummaryViewModel`과 같은 엔드포인트를 보지만 창이 달라 따로 받는다.
    private(set) var trend: [VehiclePeriod] = []
```

`load()`/`reload()`가 두 요청을 병렬로 보내게 고친다. **하나가 실패해도 다른 하나는 산다.**

```swift
    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer { isLoading = false }

        async let insightsTask = service.fetchDriveInsights(months: period.rawValue)
        async let summaryTask = service.fetchSummary(yearMonth: LedgerYearMonth.current().apiValue)

        // **둘을 따로 잡는다** — 하나가 던져도 다른 하나는 산다.
        var loadedInsights: DriveInsightsResponse?
        var insightsError: (any Error)?
        do { loadedInsights = try await insightsTask } catch { insightsError = error }

        // 추이는 실패해도 배너를 세우지 않는다 — 주행 카드가 살아 있는데 빨간 줄이 서면
        // 「전부 못 받았다」로 읽힌다. 섹션이 조용히 빠질 뿐이다.
        // **실패해도 있던 값을 지우지 않는다**(당겨서 새로고침 관례).
        let loadedSummary = try? await summaryTask

        if insightsError is CancellationError { return }
        guard current == generation else { return }

        if let loadedInsights {
            insights = loadedInsights
            errorMessage = nil
        } else if insightsError != nil {
            errorMessage = "주행 인사이트를 불러오지 못했습니다."
        }
        trend = loadedSummary?.trend ?? trend
    }
```

`Result { try await … }`는 컴파일되지 않는다(`Result(catching:)`가 async 클로저를 받지 않는다) — 위처럼 `async let` 둘을 각각 `do/catch`·`try?`로 받는다.

`LedgerYearMonth.current()`는 `Models/LedgerModels.swift:222`에 이미 있고 `.apiValue`가 `"2026-08"`을 낸다. **새 헬퍼를 만들지 않는다.**

파생 프로퍼티를 `// MARK: - 파생 값` 절 아래에 더한다.

```swift
    var hasTrend: Bool { !trend.isEmpty }

    private func points(_ value: (VehiclePeriod) -> Decimal?) -> [ChartPoint] {
        trend.map { ChartPoint(id: $0.yearMonth, label: "\($0.monthNumber)", value: value($0)) }
    }

    var distancePoints: [ChartPoint] { points(\.distanceKm) }
    var driveCountPoints: [ChartPoint] { points { $0.driveCount.map(Decimal.init) } }
    var drivingMinPoints: [ChartPoint] { points { $0.drivingMin.map(Decimal.init) } }
    var energyPoints: [ChartPoint] { points(\.energyAddedKwh) }
    var costPoints: [ChartPoint] { points(\.cost) }
    var chargeCountPoints: [ChartPoint] { points { $0.chargeCount.map(Decimal.init) } }
    var efficiencyPoints: [ChartPoint] { points(\.efficiency) }

    /// **누적은 뷰가 아니라 여기서 낸다.** 뷰에서 다시 더하면 테스트하는 값과 화면 값이 갈린다.
    var cumulativeDistancePoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(trend.map(\.distanceKm))
        return zip(trend, totals).map { period, total in
            ChartPoint(id: period.yearMonth, label: "\(period.monthNumber)", value: total)
        }
    }

    var cumulativeCostPoints: [ChartPoint] {
        let totals = VehicleMath.runningTotals(trend.map(\.cost))
        return zip(trend, totals).map { period, total in
            ChartPoint(id: period.yearMonth, label: "\(period.monthNumber)", value: total)
        }
    }
```

- [ ] **Step 4: 테스트가 통과하는지 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: 통계 탭이 12개월 추이를 함께 받는다"
```

---

## Task 9: 통계 탭 「주행」 섹션을 조립한다

**Files:**
- Create: `WooriHaru/Views/Vehicle/StatsDriveSection.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift`

**Interfaces:**
- Consumes: `MonthlyBarChart`(Task 4)·`MonthlyLineChart`(Task 5)·`MonthlyBarLineChart`(Task 6)·`VehicleStatsViewModel`의 파생 점들(Task 8)
- Produces: `struct StatsDriveSection: View { @Bindable var viewModel: VehicleStatsViewModel }`

차트 넷을 새로 그리고, 기존 카드 넷(온도별 전비·시간대 히트맵·거리 분포·자주 가는 곳)을 이 섹션 안으로 옮긴다.

- [ ] **Step 1: 섹션 뷰를 만든다**

`WooriHaru/Views/Vehicle/StatsDriveSection.swift`:

```swift
import SwiftUI

/// 통계 탭 「주행」 섹션 — 새 차트 넷과 기존 카드 넷.
///
/// **새 차트 넷은 기간 칩을 따르지 않는다.** 12개월 추이(`trend`)에서 나오는 값이라
/// 늘 최근 12개월이고, 기존 카드 넷만 칩을 따른다. 2단계에서 서버가 `months`를 받는
/// `/tesla/insights`를 내면 둘이 같은 창을 보게 된다.
struct StatsDriveSection: View {
    @Bindable var viewModel: VehicleStatsViewModel

    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 12) {
            header

            if viewModel.hasTrend {
                monthlyDistanceCard
                drivingTimeCard
                cumulativeDistanceCard
                efficiencyCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🚗 주행")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - 카드

    private var selected: VehiclePeriod? {
        viewModel.trend.first { $0.yearMonth == selectedID } ?? viewModel.trend.last
    }

    private var monthlyDistanceCard: some View {
        chartCard("월별 주행거리 · 주행횟수",
                  callout: selected.map {
                      "\(VehicleFormat.distance($0.distanceKm)) · \(DriveFormat.count($0.driveCount ?? 0))"
                  }) {
            MonthlyBarLineChart(bars: viewModel.distancePoints,
                                line: viewModel.driveCountPoints,
                                selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                                onSelect: { selectedID = $0 })
        }
    }

    private var drivingTimeCard: some View {
        chartCard("월별 주행 시간",
                  callout: selected.map { ChargeFormat.duration($0.drivingMin) }) {
            MonthlyBarChart(points: viewModel.drivingMinPoints,
                            selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeDistanceCard: some View {
        chartCard("누적 주행거리",
                  callout: viewModel.cumulativeDistancePoints
                      .last(where: { $0.value != nil })
                      .map { VehicleFormat.distance($0.value) }) {
            MonthlyLineChart(points: viewModel.cumulativeDistancePoints,
                             selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                             onSelect: { selectedID = $0 })
        }
    }

    private var efficiencyCard: some View {
        chartCard("효율 추세",
                  callout: selected.map { VehicleFormat.efficiency($0.efficiency) }) {
            MonthlyLineChart(points: viewModel.efficiencyPoints,
                             selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                             onSelect: { selectedID = $0 })
        }
    }

    /// 카드 껍데기 — 제목 · 콜아웃 · 그림. **열네 장이 같은 껍데기를 쓴다.**
    private func chartCard<Content: View>(
        _ title: String,
        callout: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    if let callout {
                        Text(callout)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.accentBright)
                            .lineLimit(1)
                    }
                }
                content()
            }
        }
    }
}
```

- [ ] **Step 2: 통계 탭에 섹션을 끼운다**

`WooriHaru/Views/Vehicle/VehicleStatsTab.swift`의 `content`에서, 기존 카드 넷을 그리던 자리 **위에** 새 섹션을 놓는다. 기존 카드 넷은 그대로 아래에 남아 같은 「주행」 섹션에 속한다.

```swift
                StatsDriveSection(viewModel: viewModel)
```

`DriveStatsCard`(역대 최고 속도·평균 월/연 주행거리)는 **섹션 헤더 위**, 기간 칩 바로 아래에 그대로 둔다 — 기간 칩을 따르지 않는 값이라 이미 그 자리에 있다.

- [ ] **Step 3: 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 4: 시뮬레이터에서 눈으로 확인한다**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | grep -E "error:|BUILD" | head
```

앱을 띄워 차량 → 통계 탭에서 차트 넷이 그려지는지, 기록이 없는 달이 트랙 색으로 남는지, 막대를 탭하면 콜아웃만 바뀌는지 본다.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: 통계 탭에 주행 차트 넷을 더한다"
```

---

## Task 10: 통계 탭 「충전」 섹션을 조립한다

**Files:**
- Create: `WooriHaru/Views/Vehicle/StatsChargeSection.swift`
- Create: `WooriHaru/Views/Vehicle/Charts/ChartCard.swift` (Step 4)
- Modify: `WooriHaru/Views/Vehicle/VehicleStatsTab.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleView.swift`
- Modify: `WooriHaru/Views/Vehicle/StatsDriveSection.swift` (Step 4 — Task 9가 만든 파일의 `chartCard`를 `ChartCard`로 바꾼다)

**Interfaces:**
- Consumes: `MonthlyBarChart`·`MonthlyBarLineChart`·`MonthlyLineChart`·`DonutChart`(Task 4~6), `VehicleStatsViewModel`(Task 8), `ChargeTotalsViewModel`(기존)
- Produces: `struct StatsChargeSection: View { @Bindable var viewModel: VehicleStatsViewModel; @Bindable var totalsViewModel: ChargeTotalsViewModel }`

- [ ] **Step 1: 섹션 뷰를 만든다**

`WooriHaru/Views/Vehicle/StatsChargeSection.swift`:

```swift
import SwiftUI

/// 통계 탭 「충전」 섹션 — 월별 충전량·비용, 월별 충전횟수, 누적 충전비, 급속/완속 비율.
///
/// **급속/완속만 `/tesla/charges/totals`에서 온다**(전 기간 집계). 나머지 셋은 12개월 추이다.
/// 두 창이 다르므로 도넛 카드에 「전 기간」이라고 적어 둔다.
struct StatsChargeSection: View {
    @Bindable var viewModel: VehicleStatsViewModel
    @Bindable var totalsViewModel: ChargeTotalsViewModel

    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 12) {
            header
            if viewModel.hasTrend {
                monthlyEnergyCard
                chargeCountCard
                cumulativeCostCard
            }
            if totalsViewModel.hasTotals {
                fastSlowCard
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🔌 충전")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var selected: VehiclePeriod? {
        viewModel.trend.first { $0.yearMonth == selectedID } ?? viewModel.trend.last
    }

    private var monthlyEnergyCard: some View {
        chartCard("월별 충전량 · 비용",
                  callout: selected.map {
                      "\(ChargeFormat.energy($0.energyAddedKwh)) · \(VehicleFormat.won($0.cost))"
                  }) {
            MonthlyBarLineChart(bars: viewModel.energyPoints,
                                line: viewModel.costPoints,
                                selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                                onSelect: { selectedID = $0 })
        }
    }

    private var chargeCountCard: some View {
        chartCard("월별 충전 횟수",
                  callout: selected.map { "\($0.chargeCount ?? 0)회" }) {
            MonthlyBarChart(points: viewModel.chargeCountPoints,
                            selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                            onSelect: { selectedID = $0 })
        }
    }

    private var cumulativeCostCard: some View {
        chartCard("누적 충전비",
                  callout: viewModel.cumulativeCostPoints
                      .last(where: { $0.value != nil })
                      .map { VehicleFormat.won($0.value) }) {
            MonthlyLineChart(points: viewModel.cumulativeCostPoints,
                             selectedID: selectedID ?? viewModel.trend.last?.yearMonth,
                             onSelect: { selectedID = $0 })
        }
    }

    /// 급속/완속 — **에너지로 나눈다**(횟수가 아니라). 완속 100번과 급속 5번이 같은 kWh일 수 있고,
    /// 이 카드가 답하는 질문은 「어디서 얼마나 채웠나」다.
    private var fastSlowCard: some View {
        let fast = totalsViewModel.totals?.fast.energyAddedKwh ?? 0
        let slow = totalsViewModel.totals?.slow.energyAddedKwh ?? 0
        let total = fast + slow
        return chartCard("급속 / 완속", callout: "전 기간") {
            HStack(spacing: 16) {
                DonutChart(slices: [
                    .init(label: "급속", value: fast, color: VehicleTheme.accentBright),
                    .init(label: "완속", value: slow, color: VehicleTheme.accentMuted),
                ])
                VStack(alignment: .leading, spacing: 8) {
                    legend("급속", fast, of: total, color: VehicleTheme.accentBright,
                           price: totalsViewModel.fastWonPerKwh)
                    legend("완속", slow, of: total, color: VehicleTheme.accentMuted,
                           price: totalsViewModel.slowWonPerKwh)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func legend(_ name: String, _ value: Decimal, of total: Decimal,
                        color: Color, price: Decimal?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text(ChargeFormat.energy(value))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
            Text(ChargeFormat.unitPrice(price))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
        }
        .lineLimit(1)
    }

    private func chartCard<Content: View>(
        _ title: String,
        callout: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    if let callout {
                        Text(callout)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.accentBright)
                            .lineLimit(1)
                    }
                }
                content()
            }
        }
    }
}
```

> `chartCard`가 Task 9와 똑같다. **두 섹션을 다 만든 뒤 하나로 뽑는다** — 지금 뽑으면 Task 9와 10이 같은 파일을 건드려 서로를 기다려야 한다. Step 4에서 정리한다.

- [ ] **Step 2: 통계 탭에 끼운다**

`VehicleStatsTab.swift`에 프로퍼티를 더한다.

```swift
    @Bindable var totalsViewModel: ChargeTotalsViewModel
```

`content`의 「주행」 섹션(기존 카드 넷 포함) 아래에 놓는다.

```swift
                StatsChargeSection(viewModel: viewModel, totalsViewModel: totalsViewModel)
```

`VehicleView.swift`의 `case .stats:`에서 넘긴다.

```swift
        case .stats:
            VehicleStatsTab(viewModel: statsViewModel,
                            healthViewModel: healthViewModel,
                            totalsViewModel: totalsViewModel)
                .task {
                    async let stats: Void = statsViewModel.load()
                    async let health: Void = healthViewModel.load()
                    async let totals: Void = totalsViewModel.load()
                    _ = await (stats, health, totals)
                }
```

- [ ] **Step 3: 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 4: 두 섹션이 쓰는 카드 껍데기를 하나로 뽑는다**

`WooriHaru/Views/Vehicle/Charts/ChartCard.swift`를 만들고, 두 섹션의 `private func chartCard`를 지운 뒤 이것을 쓴다.

```swift
import SwiftUI

/// 통계 탭 차트 카드의 껍데기 — 제목 · 콜아웃 · 그림. **열네 장이 같은 껍데기를 쓴다.**
/// 껍데기가 섹션마다 다르면 스크롤하면서 카드 경계를 다시 배워야 한다.
struct ChartCard<Content: View>: View {
    let title: String
    /// 오른쪽 위에 붙는 한 줄. 선택한 달의 값이거나 「전 기간」 같은 범위 표시다.
    var callout: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    if let callout {
                        Text(callout)
                            .font(.caption)
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.accentBright)
                            .lineLimit(1)
                    }
                }
                content()
            }
        }
    }
}
```

두 섹션에서 `chartCard("제목", callout: X) { ... }` 호출을 `ChartCard(title: "제목", callout: X) { ... }`로 바꾼다.

- [ ] **Step 5: 다시 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 6: 커밋**

```bash
git add -A
git commit -m "feat: 통계 탭에 충전 차트 넷을 더한다"
```

---

## Task 11: 충전 탭 히어로에서 주행거리를 뺀다

**Files:**
- Modify: `WooriHaru/Views/Vehicle/VehicleChargeTab.swift`

**Interfaces:**
- Consumes: Task 1의 `VehicleChargeTab`
- Produces: 없음 (화면만 바뀐다)

- [ ] **Step 1: 히어로를 충전 셋으로 바꾼다**

`VehicleChargeTab.swift`의 `heroCard`에서 주행거리(`VehicleFormat.distance(...)`)를 지우고, 지금 칩에 있던 충전량·횟수를 본문으로 올린다.

```swift
    private var heroCard: some View {
        let month = viewModel.summary?.month
        return VStack(alignment: .leading, spacing: 0) {
            Text(heroTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(VehicleTheme.textSecondary)

            // **주행거리를 뺐다.** 탭 이름이 「충전」이 되면서 주행거리가 충전 장부의
            // 주인공 자리에 남을 이유가 없어졌고, 월별 주행거리는 통계 탭이 12개월
            // 맥락과 함께 더 잘 그린다.
            Text(loaded
                 ? ChargeFormat.summaryTotal(month?.cost, count: month?.chargeCount ?? 0, loaded: true)
                 : ChargeFormat.placeholder)
                .font(.system(size: heroSize, weight: .heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(VehicleTheme.textPrimary)
                .padding(.top, 4)

            if loaded {
                HStack(spacing: 6) {
                    chip("\(month?.chargeCount ?? 0)회 충전")
                    chip(ChargeFormat.energy(month?.energyAddedKwh))
                }
                .padding(.top, 12)
            }
        }
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
    }
```

`heroTitle`이 「이 달 주행·충전」 같은 글자면 「이 달 충전」으로 고친다.

- [ ] **Step 2: 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`. `VehicleSummaryTests.swift`가 히어로 글자를 검사하고 있으면 그 기대값을 함께 고친다.

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "refactor: 충전 탭 히어로에서 주행거리를 뺀다"
```

---

## Task 12: 「이번 달 충전비, 왜 달라졌을까」 카드를 더한다

**Files:**
- Create: `WooriHaru/Views/Vehicle/CostBreakdownCard.swift`
- Modify: `WooriHaru/Views/Vehicle/VehicleChargeTab.swift`

**Interfaces:**
- Consumes: `VehicleMath.costBreakdown`·`CostBreakdown`(Task 7)
- Produces: `struct CostBreakdownCard: View { let breakdown: CostBreakdown; let current: VehiclePeriod; let previous: VehiclePeriod }`

- [ ] **Step 1: 카드를 만든다**

`WooriHaru/Views/Vehicle/CostBreakdownCard.swift`:

```swift
import SwiftUI

/// 「이번 달 충전비, 왜 달라졌을까」 — 지난달 대비 증감을 거리·전비·단가 셋으로 쪼갠다.
///
/// **지표 줄의 `지난달보다 ▲ 12%`가 답하지 않던 것을 답한다.** 12%가 어디서 왔는지
/// 말하지 않으면 그 숫자로 할 수 있는 일이 없다.
///
/// 세 항의 합은 총 증감과 정확히 같다(`VehicleMath.costBreakdown` 참조).
/// 재료가 하나라도 없으면 부르는 쪽이 카드째 감춘다.
struct CostBreakdownCard: View {
    let breakdown: CostBreakdown
    let current: VehiclePeriod
    let previous: VehiclePeriod

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                row("더 탔다", breakdown.distance,
                    detail: "\(VehicleFormat.distance(previous.distanceKm)) → \(VehicleFormat.distance(current.distanceKm))")
                row("전비가 달라졌다", breakdown.efficiency,
                    detail: "\(VehicleFormat.efficiency(previous.efficiency)) → \(VehicleFormat.efficiency(current.efficiency))")
                row("단가가 달라졌다", breakdown.unitPrice,
                    detail: "\(unitPriceText(previous)) → \(unitPriceText(current))")

                // 여기 단가는 충전량(차에 들어간 양) 기준이다 — 누적 카드의 단가는
                // 벽에서 뽑아쓴 양이 분모라 값이 다르다. 그 차이를 화면에 남긴다.
                Text("단가는 충전량 1kWh당 금액이에요.")
                    .font(.caption2)
                    .foregroundStyle(VehicleTheme.textTertiary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("충전비가 달라진 이유")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 8)
            Text(signedWon(breakdown.total))
                .font(.caption)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(breakdown.total >= 0 ? VehicleTheme.danger : VehicleTheme.accent)
        }
    }

    private func row(_ label: String, _ value: Decimal, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(signedWon(value))
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(value >= 0 ? VehicleTheme.danger : VehicleTheme.accent)
        }
    }

    /// 부호를 반드시 붙인다 — 이 카드에서 「+9,200」과 「9,200」은 다른 뜻이다.
    private func signedWon(_ value: Decimal) -> String {
        let rounded = VehicleMath.rounded(value)
        let sign = rounded >= 0 ? "+" : "−"
        return sign + VehicleFormat.won(abs(rounded))
    }

    private func unitPriceText(_ period: VehiclePeriod) -> String {
        guard let cost = period.cost, let kwh = period.energyAddedKwh, kwh > 0 else { return "—" }
        return ChargeFormat.unitPrice(cost / kwh)
    }
}
```

`VehicleFormat.won(_:)`은 `Decimal?`을 받고 `ChargeTotalsModels.swift:64`에 있다 — 옵셔널 승격이 되므로 `won(abs(rounded))`가 그대로 컴파일된다. `abs(_:)`는 `Decimal`이 `SignedNumeric`이라 쓸 수 있다.

- [ ] **Step 2: 충전 탭에 끼운다**

`VehicleChargeTab.swift`의 `body`에서 `metricsCard` 바로 아래에 놓는다.

```swift
                if let summary = viewModel.summary,
                   let previous = summary.previous,
                   let breakdown = VehicleMath.costBreakdown(current: summary.month, previous: previous) {
                    CostBreakdownCard(breakdown: breakdown,
                                      current: summary.month,
                                      previous: previous)
                        .padding(.top, 12)
                }
```

**재료가 없으면 카드째 사라진다** — 기록이 없는 달과 견줘 「+32,700원 전부 거리 때문」 같은 거짓말을 하지 않는다.

- [ ] **Step 3: 빌드와 테스트**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | grep -E "error:|TEST (SUCCEEDED|FAILED)" | head
```

기대: `TEST SUCCEEDED`.

- [ ] **Step 4: 시뮬레이터에서 눈으로 확인한다**

차량 → 충전 탭에서 카드가 뜨는지, 세 줄의 합이 머리의 총 증감과 눈으로 맞는지, 지난달 기록이 없는 달로 옮기면 카드가 사라지는지 본다.

- [ ] **Step 5: 커밋**

```bash
git add -A
git commit -m "feat: 충전비가 달라진 이유를 세 갈래로 쪼갠다"
```

---

## Self-Review

**스펙 커버리지 (1단계 범위)**

| 스펙 요구 | 태스크 |
|---|---|
| 탭을 개요·통계·충전으로 | Task 1 |
| 열화 추세를 통계로 이동 | Task 2 |
| 차트 원형 추출 | Task 3~6, Task 10 Step 4(`ChartCard`) |
| #1 월별 주행거리·횟수 | Task 9 |
| #2 월별 주행시간(`drivingMin`) | Task 9 |
| #3 누적 주행거리 | Task 9 |
| #10 효율 추세 | Task 9 |
| #11 월별 충전량·비용 | Task 10 |
| #13 월별 충전 횟수 | Task 10 |
| #14 누적 충전비 | Task 10 |
| #18 급속/완속 비율 | Task 10 |
| 충전 탭 히어로 정리 | Task 11 |
| 충전비 3분해 | Task 7(계산) + Task 12(화면) |
| 기간 칩 3/12 유지 | Global Constraints |

**1단계 밖(2단계로 미룸):** #4 #7 #8 #12 #15 #16 #17 #19~#21 #23 #25 #26, 개요의 SOC 48시간·팬텀 드레인, 종합 효율, 기간 칩 넷으로 확장. 전부 서버 신규 필드가 필요하다.

**타입 일관성 확인**

- `ChartPoint(id:label:value:)` — Task 3에서 정의, Task 4·5·6·8·9·10이 같은 순서로 씀 ✔
- `ChartScale.ratio(_:max:)`·`maxValue(_:)` — Task 3 정의, Task 4·5·6에서 씀 ✔
- `MonthlyBarChart(points:selectedID:onSelect:)` — Task 4 정의, Task 9·10에서 씀 ✔
- `MonthlyLineChart(points:selectedID:onSelect:)` — Task 5 정의, Task 9·10에서 씀 ✔
- `MonthlyBarLineChart(bars:line:selectedID:onSelect:)` — Task 6 정의, Task 9·10에서 씀 ✔
- `DonutChart(slices:)`·`DonutChart.Slice(label:value:color:)` — Task 6 정의, Task 10에서 씀 ✔
- `VehicleMath.runningTotals(_:)` — Task 7 정의, Task 8에서 씀 ✔
- `VehicleMath.costBreakdown(current:previous:)`·`CostBreakdown` — Task 7 정의, Task 12에서 씀 ✔
- `VehicleStatsViewModel`의 점 프로퍼티 — Task 8 정의, Task 9·10에서 씀 ✔
- `VehicleStatsTab(viewModel:healthViewModel:totalsViewModel:)` — Task 2에서 인자 둘, Task 10에서 셋으로 늘어남. **Task 10이 `VehicleView` 호출부를 함께 고친다** ✔

**미확인 자리는 계획 확정 전에 전부 확인했다** — 아래는 그 결과이고, 계획 본문에는 실제 이름으로 적혀 있다.

| 확인한 것 | 결과 |
|---|---|
| `VehicleHealthViewModel`의 세그먼트 프로퍼티 | **`trendSegments`**(`segments` 아님) — `VehicleHealthViewModel.swift:53` |
| `MockAPIClient` 스텁 API | `stubGet(_:result:)`가 **타입 있는 `DataResponse<T>`**를 받는다(JSON 문자열 아님). 오류는 `setError(_:for: "GET /경로")` |
| 이번 달 `yearMonth` | `LedgerYearMonth.current().apiValue` — `LedgerModels.swift:222`. 새 헬퍼 불필요 |
| `VehicleTheme.warning` | **있다.** 이중축 선 색으로 쓴다 |
| `VehicleFormat.won(_:)` | **있다** — `Decimal?`을 받는다(`ChargeTotalsModels.swift:64`) |

**사전 점검에서 고친 계획 결함 셋**

1. `MonthlyBarLineChart`의 탭이 `UIScreen.main.bounds.width`로 나누고 있었다 — 카드 안쪽 여백만큼 어긋나 오른쪽 끝 달이 안 잡힌다. `GeometryReader`의 폭을 쓰도록 고쳤다.
2. `Result { try await … }`는 컴파일되지 않는다(`Result(catching:)`가 async 클로저를 안 받는다). `async let` 둘을 각각 `do/catch`·`try?`로 받도록 고쳤다.
3. Task 10 Step 4가 `StatsDriveSection.swift`(Task 9가 만든 파일)를 고치는데 Files 목록에 없었다. 더했다.
