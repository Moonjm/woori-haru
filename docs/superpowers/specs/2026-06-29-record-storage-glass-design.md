# Record·보관함 영역 — iOS 26 Glass 롤아웃 설계

작성일: 2026-06-29

## 목적

Foundation의 Liquid Glass 디자인 시스템(`GlassCard` / `glassEffect` / `glassScreenBackground` / glass 버튼)을 Record·Storage 영역에 적용한다. 캘린더 사이클에서 보류했던 **`RecordSheetView` 글래스 완성**을 포함한다.

## 확정 사항 (사용자 결정)

- **적용 범위**: 시트 + 카드 + 배경. 캘린더와 일관.
- 시트 패널 글래스화, 카드 컨테이너 `GlassCard`/`glassEffect`, 주요 버튼 glass, 화면 배경 `glassScreenBackground`.
- **촘촘한 리스트 행 내용은 가독성 유지** — 행을 통째 글래스화하지 않음(StorageItemRow, 기록 행 텍스트/진행바).
- 한 사이클, 구현 계획은 **Part A: Record / Part B: Storage**로 분리해 순차 진행.

## 대상 파일 (조사 결과)

Record:
- `RecordSheetView`(199줄, 157–162행 `RoundedRectangle(20).fill(.white).shadow` 패널) — 캘린더 하단 상세 시트. 캘린더 오버레이로 표시되며, 캘린더의 `GlassBackground`가 뒤에 있음.
- `RecordFormView`(124줄) — 기록 추가/수정 폼. 흰 카드(RoundedRectangle 20) + 버튼.
- `RecordListView`(200줄) — 기록 카드 리스트(clipShape 12 항목들).
- `OvereatSelectorView`(79줄) — 과식 선택(RoundedRectangle 12).

Storage:
- `StorageMainView`(700줄) — 메인 + `.sheet`(보관함 추가/수정, 아이템 추가) + 하단 시트 패널(387행 `UnevenRoundedRectangle`). 흰 배경 다수(78/193/276/383행).
- `StorageItemSheet`(108줄), `ItemCategoryPickerView`(64줄), `StorageItemRow`(146줄, 진행바 `RoundedRectangle 2.5`).

테스트 타깃 없음 → 검증은 `xcodebuild` 빌드. 신규 파일 없음(전부 기존 파일 수정) → pbxproj 작업 없음.

## 아키텍처 — Record (Part A)

- **`RecordSheetView`**: 패널 배경 `RoundedRectangle(20).fill(.white).shadow(...)` + `clipShape` → `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))`(상단만 둥근 시트가 자연스러우면 `UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20)`). 내부 기록 행/텍스트/액션은 그대로.
- **`RecordFormView`**: 폼 카드(흰 RoundedRectangle 20) → `GlassCard`/`glassEffect`. 저장 등 주요 버튼 → `appGlassProminentButton()`. 입력 필드 슬레이트 배경은 가독성 위해 유지.
- **`RecordListView`**: 기록 항목 카드 컨테이너 → `GlassCard`(또는 `glassEffect`). 행 내부 텍스트/이모지 유지. 화면 배경에 `glassScreenBackground()`.
- **`OvereatSelectorView`**: 선택 컨테이너만 가볍게(작은 토글류). 과하면 불투명 유지.

## 아키텍처 — Storage (Part B)

- **`StorageMainView`**: 화면 배경 `glassScreenBackground()`; 흰 카드/패널 컨테이너(78/193/276/383행 등) → `GlassCard`/`glassEffect`; 하단 시트 패널(387행) → 글래스(상단 둥근); 주요 버튼 → glass. `.sheet` 3개는 시스템 시트(iOS 26 자동 글래스)이므로 내부 카드 패널만 정리.
- **`StorageItemSheet`**: 시트 내용 카드/입력 영역 패널 글래스, 주요 버튼 glass. 입력 배경(`Color.slate100`) 유지.
- **`ItemCategoryPickerView`**: 선택 카드만 가볍게, 행 내용 유지.
- **`StorageItemRow`**: 행 내용·진행바 그대로(촘촘한 콘텐츠). 행 통째 글래스화 금지.

## 검증

- `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- **시뮬레이터/실기기 육안**: 각 시트(상세/폼/보관함/아이템) 글래스 패널 가독성, 카드 글래스, 배경 위 콘텐츠 가독성. **핵심: RecordSheetView 글래스가 캘린더 `GlassBackground` 위에서 보이는지.** 라이트/다크 모드, 투명도 줄이기.

## 리스크 / 엣지 케이스

1. **시트 위 글래스 가독성** — slate 텍스트 대비. 과하면 일부 불투명 유지.
2. **glass-on-glass 금지** — 시트 패널 글래스 안에 또 GlassCard를 중첩하지 않음. 시트는 패널만 글래스, 내부는 일반.
3. **StorageMainView 규모(700줄)** — 흰 배경이 여러 곳. 누락/과적용 주의, 읽고 신중히.
4. **RecordSheetView 표시 경로** — 캘린더 커스텀 오버레이로 뜸. 글래스가 백드롭 위에서 보이는지 확인(핵심 검증).
5. 라이트/다크 모드, 투명도 줄이기 fallback.

## 비범위

- 다른 영역(공부/통계/커플/검색/프로필/인증/관리) — 후속 사이클.
- 기능/로직 변경, 리스트 행 내부 리디자인.
