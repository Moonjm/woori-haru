# 공부·통계 영역 Glass 롤아웃 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 공부(Study) 영역의 화면 배경·흰 카드·주요 버튼에 Foundation Liquid Glass를 적용하고, 이미 글래스가 적용된 통계(StatsView)는 일관성만 확인한다.

**Architecture:** 전부 기존 파일 리스타일(신규 파일/pbxproj 없음). Foundation 컴포넌트(`glassScreenBackground()`, `glassEffect(.regular, in:)`, `appGlassProminentButton()`)를 화면 배경·카드 컨테이너·주요 CTA에 적용. 진행바/그래프 막대/주간 확장 행/입력 칩 등 촘촘한 콘텐츠는 통째 글래스화하지 않고 가독성을 유지한다.

**Tech Stack:** SwiftUI, iOS 26 Liquid Glass.

## Global Constraints

- 최소 배포 타깃 iOS 26.0. 텍스트/마크 색은 기존 `Color+Extensions.swift` 팔레트 유지. glass는 재질 레이어일 뿐 색을 바꾸지 않는다.
- 테스트 타깃 없음 → 검증은 빌드 성공:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.
- SourceKit/IDE 진단은 무시(xcodebuild가 정답). 신규 파일 없음 → pbxproj 작업 없음.
- **glass-on-glass 금지**: 글래스 카드 안에 또 글래스를 중첩하지 않는다. 한 화면에서만 쓰이는 하위뷰는 부모가 글래스면 자식은 plain.
- **촘촘한 콘텐츠는 가독성 유지**: 진행바/그래프 막대(`RoundedRectangle`/`UnevenRoundedRectangle`), 주간 확장 행, 통계 막대, 입력 칩(`Color.slate50`/`Color.white` 입력칸)은 통째 글래스화 금지.
- **버튼 색감 교훈(직전 보관함 추가 버튼)**: 파란 채움 prominent + 어두운 아이콘 색감이 충돌하면 glass 대신 solid 유지. 의미 색(주황=일시정지, 초록=재개, 빨강=종료)을 가진 버튼은 solid 유지.
- Foundation 컴포넌트는 머지됨:
  - `View.glassScreenBackground()` — 화면 루트 배경.
  - `glassEffect(.regular, in: RoundedRectangle(cornerRadius:))` — 흰 카드 대체.
  - `GlassCard(cornerRadius:padding:alignment:content:)` — 흰 카드 래퍼(기본 radius 16).
  - `View.appGlassProminentButton()` — 주요 CTA(`.glassProminent` + `GlassTokens.accentTint` = blue500).
  - `View.appGlassButton()` — 보조 액션(`.glass`).
- Glass는 시각 요소 → 최종 Task에서 시뮬레이터 라이트/다크 + 투명도 줄이기 육안 확인.

---

## File Structure (전부 수정, 신규 없음)

- `WooriHaru/Views/Study/StudyTimerView.swift` (643줄) — 공부 타이머 메인. 루트 배경 + 흰 카드 4개 + 공부 시작 CTA.
- `WooriHaru/Views/Study/StudyRecordView.swift` (245줄) — 전체 기록. 루트 배경 + 흰 카드 3개.
- `WooriHaru/Views/Study/WeeklyStudyRecordSection.swift` (327줄) — 주간 기록 섹션 카드. 두 화면(타이머/기록)에서 **형제로** 임베드됨 → 자체 글래스 카드 안전.
- `WooriHaru/Views/Stats/StatsView.swift` (123줄) — 이미 글래스 적용됨. 검토만.

### 배치 확인 (glass-on-glass 사전 검증)

- `StudyTimerView` body: `ScrollView > VStack` 안에 `timerCard`, `todaySummaryCard`, `weeklyGoalCard`, `todayTimelineSection`, `WeeklyStudyRecordSection`이 **모두 형제**다(StudyTimerView.swift:21-27). 중첩 아님 → 각자 글래스 가능.
- `StudyRecordView` body: `ScrollView > VStack` 안에 `monthNavigationHeader`(카드 아님), `monthlyHeatmap`, `monthlySummaryCard`, `subjectBreakdown`, `WeeklyStudyRecordSection`이 **모두 형제**다(StudyRecordView.swift:9-19). 중첩 아님 → 각자 글래스 가능.
- 따라서 `WeeklyStudyRecordSection`의 자체 글래스 카드는 두 화면 모두에서 glass-on-glass가 아니다.

---

## Task 1: StudyTimerView 글래스 (배경 + 카드 4개 + 시작 CTA)

**Files:**
- Modify: `WooriHaru/Views/Study/StudyTimerView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`, `appGlassProminentButton()` (Foundation, 머지됨).
- Produces: 없음(화면 리스타일).

> 643줄 큰 파일. 편집 지점은 5곳뿐이다(배경 1 + 카드 4 + 버튼 1). 아래 정확한 라인을 읽고 신중히 교체. 칩/입력칸/진행바/타임라인 막대는 **건드리지 않는다**.

- [ ] **Step 1: 루트 배경을 글래스 배경으로 교체**

`StudyTimerView.swift:30` 의 `ScrollView` 수정자:
```swift
        .background(Color.slate50)
```
를 다음으로 교체:
```swift
        .glassScreenBackground()
```

- [ ] **Step 2: timerCard 배경을 글래스로 교체**

`StudyTimerView.swift:130-133` 의 `timerCard` 말미:
```swift
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
```
를 다음으로 교체:
```swift
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
```

- [ ] **Step 3: 공부 시작 CTA를 glassProminent로 교체**

`StudyTimerView.swift:204-218` 의 `.idle` 케이스 시작 버튼:
```swift
        case .idle:
            Button {
                isAlarmFieldFocused = false
                vm.notificationScheduler.saveAlarmInterval()
                Task { await vm.start() }
            } label: {
                Label("공부 시작", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(vm.selectedSubject != nil ? Color.blue500 : Color.slate200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(vm.selectedSubject == nil || vm.isLoading)
```
를 다음으로 교체(수동 배경/색 제거, 글래스 prominent + 액센트 틴트가 채움 담당, disabled 시 시스템이 dim 처리):
```swift
        case .idle:
            Button {
                isAlarmFieldFocused = false
                vm.notificationScheduler.saveAlarmInterval()
                Task { await vm.start() }
            } label: {
                Label("공부 시작", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .appGlassProminentButton()
            .disabled(vm.selectedSubject == nil || vm.isLoading)
```

> 일시정지/다시 시작/종료 버튼(`StudyTimerView.swift:220-285`)은 의미 색(주황/초록/빨강)을 유지해야 하므로 **solid 그대로 둔다**(버튼 색감 교훈). `timerStatusBadge`(캡슐), `subjectChip`/`pauseTypeChip`(칩), `alarmIntervalSection`(입력칸)도 그대로.

- [ ] **Step 4: todaySummaryCard 배경을 글래스로 교체**

`StudyTimerView.swift:364-366` 의 `todaySummaryCard` 말미:
```swift
        .padding(.vertical, 14)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
```
를 다음으로 교체:
```swift
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
```

- [ ] **Step 5: weeklyGoalCard 배경을 글래스로 교체**

`StudyTimerView.swift:402-404` 의 `weeklyGoalCard` 말미:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 카드 내부의 `goalProgressBar`(진행바, `StudyTimerView.swift:409-439`)는 콘텐츠라 **유지**.

- [ ] **Step 6: todayTimelineSection 배경을 글래스로 교체**

`StudyTimerView.swift:498-500` 의 `todayTimelineSection` 말미:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 내부 `timelineSegments` 막대(`StudyTimerView.swift:517-553`)는 콘텐츠라 **유지**.

- [ ] **Step 7: 빌드 검증**

Run:
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: 커밋**

```bash
git add WooriHaru/Views/Study/StudyTimerView.swift
git commit -m "feat: StudyTimerView Liquid Glass 적용 (배경·카드·시작 버튼)"
```

---

## Task 2: StudyRecordView 글래스 (배경 + 카드 3개)

**Files:**
- Modify: `WooriHaru/Views/Study/StudyRecordView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`.
- Produces: 없음.

> 편집 지점 4곳(배경 1 + 카드 3). 내부 `Color.slate50` 서브카드(`summaryItem`)·진행바·히트맵 셀은 콘텐츠라 **유지**.

- [ ] **Step 1: 루트 배경을 글래스 배경으로 교체**

`StudyRecordView.swift:23` 의 `ScrollView` 수정자:
```swift
        .background(Color.slate50)
```
를 다음으로 교체:
```swift
        .glassScreenBackground()
```

- [ ] **Step 2: monthlyHeatmap 배경을 글래스로 교체**

`StudyRecordView.swift:124-126` 의 `monthlyHeatmap` 말미:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 히트맵 셀(`heatmapCell`, `StudyRecordView.swift:129-152`)과 범례 사각형은 콘텐츠라 **유지**.

- [ ] **Step 3: monthlySummaryCard 배경을 글래스로 교체**

`StudyRecordView.swift:174-176` 의 `monthlySummaryCard` 말미:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 내부 `summaryItem`의 `Color.slate50` 서브카드(`StudyRecordView.swift:197-199`)는 콘텐츠라 **유지**(glass-on-glass 회피).

- [ ] **Step 4: subjectBreakdown 배경을 글래스로 교체**

`StudyRecordView.swift:241-243` 의 `subjectBreakdown` 말미:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 내부 과목별 진행바(`StudyRecordView.swift:224-228`)는 콘텐츠라 **유지**.

- [ ] **Step 5: 빌드 검증**

Run:
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: 커밋**

```bash
git add WooriHaru/Views/Study/StudyRecordView.swift
git commit -m "feat: StudyRecordView Liquid Glass 적용 (배경·카드)"
```

---

## Task 3: WeeklyStudyRecordSection 글래스 (부모 카드만)

**Files:**
- Modify: `WooriHaru/Views/Study/WeeklyStudyRecordSection.swift`

**Interfaces:**
- Consumes: `glassEffect(.regular, in:)`.
- Produces: 없음.

> 배치 확인 완료(File Structure 참조): 두 화면 모두 형제로 임베드 → glass-on-glass 아님. **부모 카드 한 곳만** 글래스. 확장 행(`weeklyRow`/`dailyRecordRow`)의 `Color.blue50`/`Color.slate50` 배경과 막대(`UnevenRoundedRectangle`)는 콘텐츠라 **유지**.

- [ ] **Step 1: 섹션 카드 배경을 글래스로 교체**

`WeeklyStudyRecordSection.swift:42-44` 의 `body` 카드 배경:
```swift
        .padding(16)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
```
를 다음으로 교체:
```swift
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
```

> 확장 행 내부의 `Color.slate50`/`Color.blue50` 배경(`WeeklyStudyRecordSection.swift:153`, `263`)과 `dailyBreakdownDetail`의 `.background(.white)`(`WeeklyStudyRecordSection.swift:285-287`)는 콘텐츠/툴팁이라 **그대로 둔다**.

- [ ] **Step 2: 빌드 검증 (두 화면 모두 컴파일 경유)**

Run:
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Study/WeeklyStudyRecordSection.swift
git commit -m "feat: WeeklyStudyRecordSection Liquid Glass 카드 적용"
```

---

## Task 4: StatsView 일관성 검토 (변경 없으면 그대로)

**Files:**
- Review (변경 가능성 낮음): `WooriHaru/Views/Stats/StatsView.swift`

**Interfaces:**
- Consumes: 없음(검토 전용).
- Produces: 없음.

> StatsView는 Foundation 사이클에서 이미 `GlassCard`×2 + `glassScreenBackground()`가 적용됨(StatsView.swift:10, 64, 89). 공부 영역과 시각 일관성만 확인한다.

- [ ] **Step 1: 일관성 체크 (코드 변경 없음)**

`StatsView.swift`를 읽고 다음을 확인:
- 화면 배경이 `.glassScreenBackground()`인가 (StatsView.swift:89) — ✅ 예상.
- 카드가 `GlassCard {}`인가 (StatsView.swift:10, 64) — ✅ 예상.
- 내부 필터 칩(StatsView.swift:50-54)·통계 막대(`StatBarView`, StatsView.swift:101-123)는 콘텐츠라 plain 유지 — ✅ 예상.

위가 모두 충족되면 **변경하지 않는다**. 공부 카드는 `glassEffect`(radius 14/16/20), 통계 카드는 `GlassCard`(radius 16) — 둘 다 Foundation `.glassEffect(.regular,...)` 기반이라 재질이 동일하므로 일관성 OK.

- [ ] **Step 2: (필요 시에만) 미세 조정**

육안 검토에서 통계 화면 카드 모서리/패딩이 공부 화면과 눈에 띄게 어긋나면, `GlassCard`의 기본값(radius 16, padding 16)을 유지한 채 조정. **어긋남이 없으면 이 단계는 건너뛰고 커밋 없음.**

> 변경이 없으면 Task 4에는 커밋이 없다. 변경했다면:
> ```bash
> git add WooriHaru/Views/Stats/StatsView.swift
> git commit -m "style: StatsView 글래스 일관성 미세 조정"
> ```

---

## Task 5: 최종 빌드 + 육안 검증

**Files:**
- 없음(검증 전용).

- [ ] **Step 1: 전체 클린 빌드**

Run:
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: 시뮬레이터 육안 확인 체크리스트**

시뮬레이터(또는 실기기)에서 아래를 확인:
- **공부 타이머**: 타이머 카드 배경 글래스, 숫자/상태 배지 가독성. `공부 시작` 버튼 글래스 prominent(파란 채움) + 흰 글자 충돌 없음. 일시정지/종료 버튼 의미 색 유지. 칩·알림 입력칸·진행바 선명.
- **공부 타이머 하단 / 전체 기록**: 주간 공부 기록 섹션 카드 글래스, 확장 행 막대·퍼센트 라벨 가독성(glass-on-glass 없음).
- **전체 기록**: 히트맵/요약/과목별 카드 글래스, 히트맵 셀·진행바 선명.
- **통계**: 공부 화면과 카드 재질/모서리 일관.
- **라이트/다크 모드** 모두, **설정 > 손쉬운 사용 > 투명도 줄이기** ON일 때 fallback 가독성.

- [ ] **Step 3: 리스크 재확인**

- 타이머 시작 버튼 색감 충돌 시 → `.appGlassProminentButton()`을 `.appGlassButton()`(plain glass)으로 낮추거나 기존 solid 복원(버튼 색감 교훈). 변경 시 커밋: `fix: 타이머 시작 버튼 색감 조정`.
- glass-on-glass 의심 지점(주간 섹션이 다른 글래스 카드 안에 들어가지 않음)은 File Structure에서 형제 배치로 확정됨 — 추가 조치 불필요.

---

## 비범위 (이번 플랜에서 다루지 않음)

- 커플·검색, 프로필·인증·관리 영역 — 후속 사이클.
- StatsView 대규모 변경(이미 적용됨), 기능/로직 변경, 그래프·진행바 리디자인.
- 진행바/타임라인 막대/주간 확장 행/입력 칩의 글래스화(콘텐츠 가독성 위해 의도적 제외).

---

## Self-Review (스펙 대비 점검)

- **적용 범위(시트+카드+배경)**: Task 1·2(배경+카드), Task 3(카드), 버튼은 Task 1 Step 3. 공부 영역에 시트 화면은 없음(타이머/기록/주간은 카드 기반) → 시트 항목은 N/A. ✅
- **촘촘한 콘텐츠 유지**: 각 Task의 인용 블록 아래 "유지" 주석으로 진행바/막대/칩/확장 행 명시. ✅
- **glass-on-glass 금지**: File Structure의 배치 확인 + Task 2 Step 3(slate50 서브카드 유지) + Task 3(부모만). ✅
- **타이머 버튼 색감 교훈**: Task 1 Step 3 주석 + Task 5 Step 3 fallback. ✅
- **StatsView 검토만**: Task 4(변경 없으면 커밋 없음). ✅
- **검증=빌드+육안**: 각 Task 빌드 Step + Task 5 육안 체크리스트(라이트/다크/투명도 줄이기). ✅
- 라인 번호는 작성 시점 스냅샷 — 실행 시 파일을 먼저 읽고 해당 수정자 블록을 매칭해 교체할 것.
