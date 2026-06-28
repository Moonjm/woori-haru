# 캘린더 영역 — iOS 26 Glass 롤아웃 + 년/월 바텀시트 피커 설계

작성일: 2026-06-28

## 목적

Foundation(머지 완료)에서 만든 Liquid Glass 디자인 시스템을 캘린더(홈) 영역에 적용한다. 동시에, 상단 제목을 눌러 년/월을 이동하는 현재의 "어두운 드롭다운 + 즉시 적용" 피커를, **아래에서 올라오는 밝은 바텀시트 + 취소/확인 확정** 방식으로 교체한다.

## 확정 사항 (사용자 결정)

- **피커 구성**: 년/월 2단(일 칸 없음). **확인** 시에만 해당 월로 이동, **취소**는 변경 없이 닫기.
- **피커 구현**: 접근 방식 A — iOS 26 네이티브 `.sheet` + `presentationDetents` + SwiftUI `Picker(.wheel)`. (슬라이드업·드래그 닫기·딤·Liquid Glass 시트가 자동)
- **캘린더 Glass 범위**: 크롬/컨트롤만. 상세 시트 + 화면 배경 + 헤더. **월 그리드·날짜셀은 그대로**(촘촘한 콘텐츠 가독성 우선).
- 기존 커스텀 UIKit 다크 피커(`NaverStylePicker`)와 헤더 다크 토글 로직은 제거.

## 현재 구조 (조사 결과)

- `CalendarView.swift`(482줄): 커스텀 UIScrollView 브리징, 월 그리드(`MonthGridView`/`DayCellView`), 커스텀 하단 상세 시트(`Color.black.opacity(0.3)` 딤 + 높이 비율 시트), `@State showPicker`.
- 제목 탭(`onMonthTap`) → `showPicker.toggle()`. `showPicker`면 헤더가 다크(`pickerDarkBg`)로 바뀌고(`CalendarHeaderView`), 헤더 아래에 `YearMonthPickerView`(다크, 년/월 2단, `onSelect`로 **스크롤 즉시 적용**)가 드롭다운으로 표시되며 하단 투명 영역 탭으로 닫힘.
- 이동 로직: `onSelect`에서 `calendarVM.rebuildMonthsIfNeeded(year:month:)` + `forceScrollTo("YYYY-MM")` + 백그라운드 `ensureDataLoaded`.
- `pickerTargetYear` / `pickerTargetMonth`: 현재 캘린더 위치(피커 초기값).

## 아키텍처 — 년/월 바텀시트 피커

신규 `WooriHaru/Views/Calendar/MonthPickerSheet.swift`:

- `struct MonthPickerSheet: View` — 입력: `initialYear`, `initialMonth`, `onConfirm: (Int, Int) -> Void`, 그리고 dismiss(`@Environment(\.dismiss)` 또는 `isPresented` 바인딩).
- 내부 `@State selectedYear`, `selectedMonth`(초기값 = initial). 휠을 돌려도 **즉시 적용하지 않음**.
- 레이아웃: 상단 간단한 그래버/타이틀(선택), 가운데 `HStack { Picker(년).pickerStyle(.wheel); Picker(월).pickerStyle(.wheel) }`, 하단 `취소`/`확인` 버튼 행.
  - `확인`: `onConfirm(selectedYear, selectedMonth)` 호출 후 dismiss.
  - `취소`: 그냥 dismiss(변경 없음).
- 년 범위: `currentYear-10 ... currentYear+10`(기존과 동일). 월: 1...12.
- 한국어 라벨("…년", "…월"), 기존 팔레트.

`CalendarView` 연결:
- `@State showPicker`는 유지하되, 드롭다운 오버레이 블록(현재 `if showPicker { VStack { YearMonthPickerView … } }`)을 제거하고, 루트에 `.sheet(isPresented: $showPicker) { MonthPickerSheet(initialYear: calendarVM.pickerTargetYear, initialMonth: calendarVM.pickerTargetMonth) { year, month in <기존 이동 로직> } .presentationDetents([.height(320)]) .presentationDragIndicator(.visible) }` 추가.
- `onConfirm` 클로저에 **기존 이동 로직**(`rebuildMonthsIfNeeded` + `forceScrollTo` + `ensureDataLoaded`)을 그대로 이식.
- `CalendarHeaderView`: `isPickerOpen` 기반 **다크 테마 토글 제거**(항상 밝은 헤더, chevron은 down 고정 또는 sheet 표시 중 up). `pickerDarkBg` 상수 제거.
- 제거: `YearMonthPickerView.swift`(및 그 안의 `NaverStylePicker`) — 더 이상 사용 안 함. (호출처가 CalendarView뿐인지 확인 후 삭제)
- `stopScroll(when: showPicker)` 등 showPicker 의존 로직은 시트 표시와 호환되게 유지/정리.

## 아키텍처 — 캘린더 Glass 적용

- **화면 배경**: 캘린더 루트에 `.glassScreenBackground()`(Foundation의 은은한 그라데이션) 적용. 그리드가 그 위에 뜨도록. 헤더/그리드가 불투명 흰색을 강제하면 완화.
- **하단 상세 시트**: 현재 `.background(.white...)`/`.fill(.white)`로 그리는 시트 패널을 Foundation 컴포넌트(`GlassCard` 또는 `glassEffect`)로 교체. 단, 시트 내부는 기록 목록(콘텐츠)이라 **패널 자체만 글래스**, 내부 행/텍스트는 가독성 유지.
- **헤더 바**: 배경을 글래스 또는 투명+배경 비침으로(현재 다크 토글 제거하며 정리).
- **월 그리드·날짜셀(`MonthGridView`/`DayCellView`)**: 변경 없음(가독성).

## 검증

- 테스트 타깃 없음 → `xcodebuild ... build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`. 신규 파일(`MonthPickerSheet.swift`)은 pbxproj 등록 필요(명시적 참조 방식; 미등록 시 false-positive) + `SwiftFileList`로 컴파일 확인.
- **시각 확인(시뮬레이터/실기기)**: 제목 탭 → 바텀시트가 아래에서 올라오는지, 휠로 년/월 선택 후 확인 시 해당 월로 이동, 취소 시 변경 없음, 드래그로 닫힘. 상세 시트/배경 글래스 가독성. 라이트/다크 모드.

## 리스크 / 엣지 케이스

1. **이동 로직 회귀** — `onSelect`(즉시) → `onConfirm`(확정)으로 옮길 때 `forceScrollTo`/`rebuildMonthsIfNeeded`/스크롤 억제 카운터 동작이 그대로 유지돼야 함. 확인 시 한 번만 호출.
2. **showPicker 의존 코드** — `stopScroll(when:)`, 헤더 chevron, 엣지 로딩 억제 등 `showPicker` 참조부가 시트 방식과 어긋나지 않게 정리.
3. **YearMonthPickerView 삭제** — 다른 화면에서 참조 없는지 확인 후 파일 삭제(+ pbxproj에서 제거).
4. **presentationDetents 높이** — 휠 2개 + 버튼이 잘리지 않게 높이(약 320) 조정, 기기별 확인.
5. **글래스 가독성** — 상세 시트/헤더 텍스트(slate 계열) 대비. 과하면 일부 불투명 유지.
6. **pbxproj** — 신규 파일 등록, 삭제 파일 참조 제거, `plutil -lint` 검증.

## 비범위

- 다른 영역(기록/공부/커플 등) Glass — 후속 사이클.
- 날짜셀/그리드 비주얼 변경, 일(日) 단위 네비게이션.
