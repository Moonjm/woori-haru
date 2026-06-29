# Record·보관함 영역 Glass 롤아웃 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record·Storage 영역의 시트/카드/배경에 Foundation Liquid Glass를 적용하고, 캘린더에서 보류했던 `RecordSheetView` 글래스를 완성한다.

**Architecture:** 전부 기존 파일 리스타일(신규 파일/ pbxproj 없음). Foundation 컴포넌트(`GlassCard`, `glassEffect`, `glassScreenBackground()`, `appGlassProminentButton()`)를 시트 패널·카드 컨테이너·주요 버튼·화면 배경에 적용. 촘촘한 리스트 행 내용은 가독성 유지.

**Tech Stack:** SwiftUI, iOS 26 Liquid Glass.

## Global Constraints

- 최소 배포 타깃 iOS 26.0. 텍스트/마크 색은 기존 `Color+Extensions.swift` 팔레트. glass는 재질 레이어.
- 테스트 타깃 없음 → 검증은 빌드 성공:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.
- SourceKit/IDE 진단은 무시(xcodebuild가 정답). 신규 파일 없음 → pbxproj 작업 없음.
- **glass-on-glass 금지**: 글래스 시트/패널 안에 또 GlassCard를 중첩하지 않는다(패널만 글래스, 내부는 일반).
- **촘촘한 리스트 행은 가독성 유지**: 행 통째 글래스화 금지(StorageItemRow 내용·진행바, 기록 행 텍스트/이모지).
- Glass는 시각 요소 → 최종 Task에서 시뮬레이터 육안 확인.
- Foundation 컴포넌트는 머지됨(`GlassCard(cornerRadius:padding:alignment:content:)`, `View.glassScreenBackground()`, `View.appGlassProminentButton()`, `View.appGlassButton()`, `glassEffect(.regular, in:)`).

---

## File Structure (전부 수정)

Part A — Record:
- `WooriHaru/Views/Record/RecordSheetView.swift`
- `WooriHaru/Views/Record/RecordFormView.swift`
- `WooriHaru/Views/Record/RecordListView.swift`
- `WooriHaru/Views/Record/OvereatSelectorView.swift`

Part B — Storage:
- `WooriHaru/Views/Storage/StorageMainView.swift`
- `WooriHaru/Views/Storage/StorageItemSheet.swift`
- `WooriHaru/Views/Storage/ItemCategoryPickerView.swift`
- (`StorageItemRow.swift` — 행 내용 유지, 변경 없음)

---

## Task 1: RecordSheetView 글래스 (보류분 완성)

**Files:**
- Modify: `WooriHaru/Views/Record/RecordSheetView.swift`

> 파일을 먼저 읽을 것. 핵심 편집은 패널 배경(현재 157–162행 부근)이다.

- [ ] **Step 1: 패널 배경을 글래스로 교체**

`RecordSheetView`의 루트 패널 배경:
```swift
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
```
를 다음으로 교체(상단만 둥근 시트 형태):
```swift
        .glassEffect(.regular, in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
```
내부 기록 행/텍스트/액션/헤더는 그대로 둔다. (그림자는 글래스가 대체)

- [ ] **Step 2: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Record/RecordSheetView.swift
git commit -m "feat: RecordSheetView Liquid Glass 패널 적용 (캘린더 상세 시트 보류분 완성)"
```

---

## Task 2: RecordFormView 글래스 (폼 카드 + 버튼)

**Files:**
- Modify: `WooriHaru/Views/Record/RecordFormView.swift`

> 파일을 먼저 읽을 것. 폼 카드(흰 `RoundedRectangle(cornerRadius: 20)` 배경)와 주요 버튼을 찾는다.

- [ ] **Step 1: 폼 카드 배경을 글래스로**

폼 내용을 감싸는 흰 카드 배경(`RoundedRectangle(cornerRadius: 20)` 흰색 fill/배경 + clipShape)을 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))`으로 교체. 입력 필드 자체의 슬레이트 배경(예: `RoundedRectangle(cornerRadius: 10)` 입력칸)은 가독성 위해 **유지**.

- [ ] **Step 2: 주요 버튼 글래스화**

저장/확인 등 주요 CTA 버튼(현재 불투명/채움 스타일)에 `.appGlassProminentButton()` 적용(라벨의 수동 배경/clipShape 제거). 보조 버튼이 있으면 `.appGlassButton()`. 비주요(취소 등)는 기존 유지 가능. 버튼 동작/disabled 로직은 변경 없음.

- [ ] **Step 3: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Record/RecordFormView.swift
git commit -m "feat: RecordFormView 폼 카드/버튼 Liquid Glass 적용"
```

---

## Task 3: RecordListView + OvereatSelectorView 글래스

**Files:**
- Modify: `WooriHaru/Views/Record/RecordListView.swift`
- Modify: `WooriHaru/Views/Record/OvereatSelectorView.swift`

> 두 파일을 먼저 읽을 것.

- [ ] **Step 1: RecordListView — 배경 + 카드**

화면 루트(최상위 컨테이너/ScrollView 또는 List 컨테이너)에 `.glassScreenBackground()` 적용. 기록 항목 카드 컨테이너(현재 `clipShape(RoundedRectangle(cornerRadius: 12))`로 그리는 흰 카드)를 `GlassCard { ... }`로 감싸거나 카드 배경을 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))`으로 교체. **행 내부 텍스트/이모지/액션은 유지.** 카드 안에 또 GlassCard를 중첩하지 말 것.

- [ ] **Step 2: OvereatSelectorView — 컨테이너만 가볍게**

선택 컨테이너(`RoundedRectangle(cornerRadius: 12)`)가 큰 패널이면 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))` 적용. 작은 토글/칩 수준이면 가독성 위해 **그대로 둔다**(판단해서 과하면 미적용, 보고서에 명시).

- [ ] **Step 3: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Record/RecordListView.swift WooriHaru/Views/Record/OvereatSelectorView.swift
git commit -m "feat: RecordListView/OvereatSelector Liquid Glass 적용"
```

---

## Task 4: StorageMainView 글래스 (메인 + 하단 시트)

**Files:**
- Modify: `WooriHaru/Views/Storage/StorageMainView.swift`

> 700줄 파일. **전체를 신중히 읽고** 흰 배경/카드/시트 패널을 식별한 뒤 적용한다. 흰 배경 위치 참고: 78/193/276/383행 부근, 하단 시트 패널 387행 부근 `UnevenRoundedRectangle`.

- [ ] **Step 1: 화면 배경**

메인 화면 루트에 `.glassScreenBackground()` 적용. 루트가 강제하는 불투명 흰 배경이 백드롭을 가리면 그 부분만 완화.

- [ ] **Step 2: 카드/패널 컨테이너 글래스화**

흰색(`.background(.white)` / `.background(Color.white)` / 흰 `RoundedRectangle` fill)으로 그리는 **큰 카드/패널 컨테이너**를 `GlassCard` 또는 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: <기존 반경>))`으로 교체. 하단 시트 패널(387행 부근 `UnevenRoundedRectangle`)은 그 모양 그대로 `.glassEffect(.regular, in: UnevenRoundedRectangle(...))`. **리스트 행(StorageItemRow 사용처)·작은 토글·진행바는 유지.** glass-on-glass 중첩 금지.

- [ ] **Step 3: 주요 버튼**

주요 CTA 버튼 → `.appGlassProminentButton()`(라벨 수동 배경 제거). `.buttonStyle(.plain)` 탭 영역은 필요한 것만 선별. 동작 변경 없음.

- [ ] **Step 4: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Storage/StorageMainView.swift
git commit -m "feat: StorageMainView Liquid Glass 적용 (배경/카드/하단 시트/버튼)"
```

---

## Task 5: StorageItemSheet + ItemCategoryPickerView 글래스

**Files:**
- Modify: `WooriHaru/Views/Storage/StorageItemSheet.swift`
- Modify: `WooriHaru/Views/Storage/ItemCategoryPickerView.swift`

> 두 파일을 먼저 읽을 것.

- [ ] **Step 1: StorageItemSheet — 패널/버튼**

시트 내용 카드/입력 영역의 큰 패널 배경을 `.glassEffect`/`GlassCard`로. 입력 배경(`Color.slate100`)은 가독성 위해 유지. 주요 버튼 → `.appGlassProminentButton()`. 동작 변경 없음.

- [ ] **Step 2: ItemCategoryPickerView — 선택 카드만 가볍게**

카테고리 선택 컨테이너/카드가 큰 패널이면 `.glassEffect` 적용. 행/칩 수준이면 그대로 둔다(가독성). 행 내부 내용 유지.

- [ ] **Step 3: 빌드 검증**

공통 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Storage/StorageItemSheet.swift WooriHaru/Views/Storage/ItemCategoryPickerView.swift
git commit -m "feat: StorageItemSheet/ItemCategoryPicker Liquid Glass 적용"
```

---

## Task 6: 육안 검증 (수동)

**Files:** 없음.

- [ ] **Step 1: Record 시각 확인**

캘린더 → 날짜 탭 → **RecordSheetView 글래스가 백드롭 위에서 보이는지**(이번 핵심). 기록 추가/수정 폼(RecordFormView) 카드·버튼, 기록 리스트 카드·배경.

- [ ] **Step 2: Storage 시각 확인**

보관함 메인 카드/하단 시트/배경, 아이템 추가 시트, 카테고리 선택. 리스트 행 가독성 유지 확인.

- [ ] **Step 3: 모드/접근성 + 가독성**

라이트/다크 모드, 투명도 줄이기(Reduce Transparency). 글래스 위 slate 텍스트 대비가 충분한지(과하면 해당 패널 불투명 조정 — 후속 메모).

- [ ] **Step 4: glass-on-glass 점검**

시트 패널 글래스 안에 또 글래스 카드가 겹쳐 뿌옇게 보이는 곳이 없는지.

---

## Self-Review 결과

- **Spec 커버리지**: RecordSheetView(보류분) → Task 1; RecordFormView → Task 2; RecordListView/OvereatSelector → Task 3; StorageMainView → Task 4; StorageItemSheet/ItemCategoryPicker → Task 5; StorageItemRow 유지 → Global Constraints + Task 4 명시; 검증/리스크 → Task 6. Part A=Task 1-3, Part B=Task 4-5.
- **Placeholder 스캔**: Task 1은 RecordSheetView의 정확한 패널 코드(조사 확인) 제시. 나머지는 복잡/대형 파일이라 "읽고 적용" + 적용 규칙·대상 위치·수용 기준 명시(완전 축자 대신 컴포넌트 적용 지시) — UI 리스타일에 적합한 입도.
- **타입 일관성**: `GlassCard`/`glassEffect(.regular, in:)`/`glassScreenBackground()`/`appGlassProminentButton()`/`appGlassButton()`는 Foundation(머지됨) 제공 명칭과 일치.
- **주의**: glass-on-glass 금지, 촘촘한 행 유지는 전 태스크 공통 제약. RecordSheetView는 캘린더 오버레이로 표시되므로 글래스 가시성은 육안(Task 6)에서 확인.
