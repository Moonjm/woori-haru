# 캘린더 Glass + 년/월 바텀시트 피커 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 캘린더 상단 제목 탭의 년/월 이동을 "어두운 드롭다운 즉시적용"에서 "밝은 네이티브 바텀시트 + 취소/확인 확정"으로 교체하고, 캘린더 크롬(상세 시트/배경/헤더)에 Liquid Glass를 적용한다.

**Architecture:** 신규 `MonthPickerSheet`(SwiftUI 휠 2단 + 취소/확인)를 `.sheet`+`presentationDetents`로 띄운다. 확인 시에만 기존 이동 로직(`rebuildMonthsIfNeeded`+`forceScrollTo`+`ensureDataLoaded`)을 호출. 기존 `YearMonthPickerView`(다크 UIKit)와 헤더 다크 토글은 제거. Glass는 Foundation 컴포넌트(`glassScreenBackground`/`glassEffect`/`appGlassProminentButton`)를 크롬에만 적용.

**Tech Stack:** SwiftUI, iOS 26 Liquid Glass, `.sheet`/`presentationDetents`, `Picker(.wheel)`.

## Global Constraints

- 최소 배포 타깃 iOS 26.0. 가용성 가드 불필요.
- 텍스트/마크 색은 기존 `Color+Extensions.swift` 팔레트. glass는 재질 레이어.
- 테스트 타깃 없음 → 검증은 빌드 성공:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.
- SourceKit/IDE 진단은 무시(xcodebuild가 정답). 메인 타깃은 pbxproj 명시적 참조 → 신규 `.swift`는 등록, 삭제 파일은 참조 제거. `plutil -lint`로 검증, `WooriHaru.SwiftFileList`로 실제 컴파일 확인.
- Glass는 시각 요소 → 최종 Task에서 시뮬레이터 육안 확인.
- 확정 동작: 피커는 년/월 2단, **확인 시에만** 해당 월로 이동, **취소/드래그 닫기**는 변경 없음.

---

## File Structure

신규:
- `WooriHaru/Views/Calendar/MonthPickerSheet.swift` — 바텀시트 내용(년/월 휠 + 취소/확인).

수정:
- `WooriHaru/Views/Calendar/CalendarView.swift` — 드롭다운 제거, `.sheet` 추가, 확인 시 이동 로직, `onChange(of: showPicker)` 정리.
- `WooriHaru/Views/Calendar/CalendarHeaderView.swift` — 다크 토글 제거(항상 밝은 헤더).
- `WooriHaru.xcodeproj/project.pbxproj` — MonthPickerSheet 등록, YearMonthPickerView 참조 제거.

삭제:
- `WooriHaru/Views/Calendar/YearMonthPickerView.swift` — 사용 안 함(캘린더 외 참조 없음 확인됨).

---

## Task 1: MonthPickerSheet 컴포넌트

**Files:**
- Create: `WooriHaru/Views/Calendar/MonthPickerSheet.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (등록 — 컨트롤러가 수행)

**Interfaces:**
- Produces: `struct MonthPickerSheet: View` — `init(initialYear: Int, initialMonth: Int, onConfirm: @escaping (Int, Int) -> Void)`. 확인 시 `onConfirm(year, month)` 후 dismiss, 취소 시 dismiss만.

- [ ] **Step 1: 파일 작성**

```swift
import SwiftUI

/// 캘린더 상단 제목 탭 시 아래에서 올라오는 년/월 선택 바텀시트.
/// 확인 시에만 onConfirm 호출(즉시 적용 아님), 취소는 변경 없이 닫기.
struct MonthPickerSheet: View {
    let initialYear: Int
    let initialMonth: Int
    let onConfirm: (Int, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedYear: Int
    @State private var selectedMonth: Int

    private static var years: [Int] {
        let y = Calendar.current.component(.year, from: Date())
        return Array((y - 10)...(y + 10))
    }

    init(initialYear: Int, initialMonth: Int, onConfirm: @escaping (Int, Int) -> Void) {
        self.initialYear = initialYear
        self.initialMonth = initialMonth
        self.onConfirm = onConfirm
        _selectedYear = State(initialValue: initialYear)
        _selectedMonth = State(initialValue: initialMonth)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Picker("연도", selection: $selectedYear) {
                    ForEach(Self.years, id: \.self) { y in
                        Text("\(String(y))년").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker("월", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text("\(m)월").tag(m)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
            .frame(height: 200)

            HStack(spacing: 12) {
                Button("취소") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(Color.slate700)

                Button("확인") {
                    onConfirm(selectedYear, selectedMonth)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .appGlassProminentButton()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .padding(.top, 12)
    }
}
```

- [ ] **Step 2: pbxproj 등록 (컨트롤러)**

`MonthPickerSheet.swift`를 메인 타깃에 등록한다(PBXBuildFile/PBXFileReference/Calendar 그룹 children/Sources phase). 기존 Calendar 파일(예: `DayCellView.swift`)의 항목을 패턴 참조. `plutil -lint` → OK.

- [ ] **Step 3: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`. 이어서:
```bash
DERIVED=$(xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null | grep -m1 OBJROOT | awk '{print $3}')
find "$DERIVED" -path "*WooriHaru.build*" -name "WooriHaru.SwiftFileList" | head -1 | xargs grep -o "MonthPickerSheet.swift"
```
기대: `MonthPickerSheet.swift` 출력.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Calendar/MonthPickerSheet.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 년/월 선택 바텀시트(MonthPickerSheet) 추가"
```

---

## Task 2: CalendarView/Header 연결 + 기존 드롭다운 제거

**Files:**
- Modify: `WooriHaru/Views/Calendar/CalendarView.swift`
- Modify: `WooriHaru/Views/Calendar/CalendarHeaderView.swift`
- Delete: `WooriHaru/Views/Calendar/YearMonthPickerView.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (YearMonthPickerView 참조 제거 — 컨트롤러)

**Interfaces:**
- Consumes: `MonthPickerSheet(initialYear:initialMonth:onConfirm:)` (Task 1).

> `CalendarView.swift` 전체를 먼저 읽을 것. 아래는 정확한 편집 지시다.

- [ ] **Step 1: 기존 드롭다운 피커 오버레이 제거**

`CalendarView.swift`의 `// Picker overlay` 블록(현재 `if showPicker { VStack(spacing: 0) { YearMonthPickerView(...) ; Color.clear...onTapGesture { showPicker = false } } .transaction { ... } }`) 전체를 삭제한다.

- [ ] **Step 2: 루트에 바텀시트 추가 + 확인 시 이동 로직 이식**

루트 `ZStack { ... }`에 모디파이어로 추가(예: `.onChange(of: showPicker)`를 대체할 위치). 기존 `onSelect`에 있던 이동 로직을 `onConfirm`으로 옮긴다:
```swift
        .sheet(isPresented: $showPicker) {
            MonthPickerSheet(
                initialYear: calendarVM.pickerTargetYear,
                initialMonth: calendarVM.pickerTargetMonth
            ) { year, month in
                let target = String(format: "%04d-%02d", year, month)
                calendarVM.rebuildMonthsIfNeeded(year: year, month: month)
                Task {
                    suppressEdgeLoadingCount += 1
                    defer { suppressEdgeLoadingCount -= 1 }
                    await forceScrollTo(target)
                    dataLoadTask?.cancel()
                    dataLoadTask = Task { await calendarVM.ensureDataLoaded(around: target) }
                }
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
```

- [ ] **Step 3: 기존 `onChange(of: showPicker)` 정리**

피커가 닫힐 때 데이터를 로드하던 `.onChange(of: showPicker) { _, show in if !show { ... ensureDataLoaded ... } }` 블록은 이제 이동/로드가 `onConfirm`에서 일어나므로 **제거**한다(취소로 닫을 때 이동하면 안 됨). 블록 전체 삭제.

- [ ] **Step 4: 헤더 다크 토글 제거**

`CalendarHeaderView.swift`에서:
- 파일 상단 `private let pickerDarkBg = ...` 제거.
- `.background(isPickerOpen ? pickerDarkBg : .white)` → `.background(.white)`.
- 메뉴/검색 아이콘·제목·chevron의 `isPickerOpen ? .white... : ...` 삼항을 비-피커(밝은) 색으로 단순화: 메뉴/검색 `Color.slate700`, 제목 `Color.slate900`, chevron은 `isPickerOpen ? "chevron.up" : "chevron.down"` 유지하고 색은 `Color.slate400`.
- `isPickerOpen` 파라미터는 chevron 방향에만 쓰이므로 유지(시트 표시 중 위쪽 화살표).

- [ ] **Step 5: YearMonthPickerView 삭제 + pbxproj 참조 제거 (컨트롤러)**

```bash
git rm WooriHaru/Views/Calendar/YearMonthPickerView.swift
```
그리고 pbxproj에서 해당 PBXBuildFile/PBXFileReference/그룹 children/Sources phase 4곳의 YearMonthPickerView 항목 제거. `plutil -lint` → OK.

- [ ] **Step 6: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`. `grep -rn "YearMonthPickerView" WooriHaru` → 결과 없음.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Views/Calendar/CalendarView.swift WooriHaru/Views/Calendar/CalendarHeaderView.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: 년/월 이동을 바텀시트로 교체 (드롭다운/다크 피커 제거)"
```

---

## Task 3: 캘린더 Glass 적용 (크롬)

**Files:**
- Modify: `WooriHaru/Views/Calendar/CalendarView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect`(Foundation).

> `CalendarView.swift`를 읽고 아래 규칙으로 적용. 월 그리드/날짜셀(`MonthGridView`/`DayCellView`)은 건드리지 않는다.

- [ ] **Step 1: 화면 배경 레이어**

캘린더 루트 `ZStack`(또는 그 내부 콘텐츠 컨테이너)에 `.glassScreenBackground()`를 적용해 그리드가 은은한 배경 위에 뜨게 한다. 헤더/그리드가 강제하는 불투명 흰 배경이 배경 레이어를 가리면, 그 부분만 투명/완화. (그리드 셀 자체 색은 유지)

- [ ] **Step 2: 하단 상세 시트 패널 glass화**

`// Bottom sheet overlay` 블록의 `RecordSheetView`를 감싸는 시트 패널 배경(현재 흰색 계열)을 glass로. `RecordSheetView` 호출부 컨테이너에 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))`를 적용(상단만 둥근 느낌이 필요하면 `UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)` 사용). 시트 내부 기록 목록/텍스트는 가독성 위해 그대로. 만약 `RecordSheetView` 내부에서 자체 흰 배경을 그린다면 이 Task에서는 외곽 패널만 처리하고, 내부는 비범위(후속).

- [ ] **Step 3: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "feat: 캘린더 크롬(배경/상세 시트) Liquid Glass 적용"
```

---

## Task 4: 육안 검증 (수동)

**Files:** 없음.

- [ ] **Step 1: 바텀시트 동작**

iOS 26 시뮬레이터에서 캘린더 → 상단 "YYYY. M. ▾" 탭 → **아래에서 바텀시트가 올라오는지**, 년/월 휠 선택 후 **확인** 시 해당 월로 이동, **취소/드래그 닫기** 시 변경 없음 확인.

- [ ] **Step 2: 이동/로딩 회귀 확인**

확인 후 캘린더가 올바른 월로 스크롤되고 데이터가 로드되는지(과거/미래 월 모두). 빠르게 여러 번 열고 확인해도 스크롤/로딩이 깨지지 않는지.

- [ ] **Step 3: Glass 시각 확인**

상세 시트(날짜 탭) 글래스 패널 가독성, 화면 배경 위 그리드 가독성, 헤더가 더 이상 다크로 바뀌지 않는지. 라이트/다크 모드, 투명도 줄이기.

---

## Self-Review 결과

- **Spec 커버리지**: 바텀시트 피커(년/월, 확인 확정) → Task 1·2; 다크 드롭다운/UIKit 피커 제거 → Task 2; 헤더 다크 토글 제거 → Task 2 Step 4; 캘린더 Glass(배경/상세 시트/헤더) → Task 2(헤더)·Task 3; 그리드 유지 → Task 3 명시; 검증/리스크 → Task 4. YearMonthPickerView 삭제 → Task 2 Step 5.
- **Placeholder 스캔**: 신규 컴포넌트는 완전 코드. CalendarView는 복잡 파일이라 "읽고 편집" + 이식할 코드 블록·삭제 대상 명시.
- **타입 일관성**: `MonthPickerSheet(initialYear:initialMonth:onConfirm:)`가 Task 1 정의와 Task 2 사용에서 일치. `appGlassProminentButton`/`glassScreenBackground`/`glassEffect`는 Foundation(머지됨)에서 제공.
- **주의**: 이동 로직은 `onConfirm`에서만 1회 실행(취소 시 미실행). `onChange(of: showPicker)` 제거 필수. `presentationDetents([.height(320)])` 높이는 Task 4에서 육안 조정 가능.
