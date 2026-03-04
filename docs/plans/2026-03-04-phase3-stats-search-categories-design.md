# Phase 3: 통계 & 검색 & 카테고리 관리 설계

## 목표

웹 앱의 통계(StatsPage), 검색(SearchPage), 카테고리 관리(CategoriesPage) 3개 화면을 iOS로 구현한다. 서비스 레이어(RecordService, CategoryService, PairService)는 이미 구축되어 있으므로 ViewModel + View만 추가한다.

## 아키텍처

기존 Phase 2 패턴 동일: `@Observable` ViewModel + SwiftUI View + 기존 Service 재사용. 사이드 드로어에서 각 화면으로 네비게이션.

---

## 1. 통계 (StatsView)

### 데이터 흐름
1. RecordService로 기간별 records 조회 (`fetchRecords(from:to:)`)
2. 페어링 상태면 PairService로 파트너 records 조회 (`fetchPartnerRecords(from:to:)`)
3. 필터(all/together/solo)에 따라 클라이언트 필터링
4. 카테고리별 그룹핑 → count/ratio 계산 → count 내림차순 정렬

### UI 구성
- **헤더**: "통계" 타이틀
- **기간 정보**: "2026년 3월" + "총 N건"
- **필터**: 연도 Picker + 월 Picker(전체/1~12)
- **커플 필터**: 전체/같이/혼자 세그먼트 (페어링 시에만 표시)
- **차트**: 카테고리별 가로 바
  - 각 행: 이모지 + 이름 | 횟수 + 비율(%)
  - GeometryReader로 바 너비를 비율에 맞게 렌더
- **빈 상태**: "해당 기간에 기록이 없습니다"

### StatsViewModel
- `selectedYear`, `selectedMonth` (0 = 전체)
- `filterType`: all / together / solo
- `stats`: [CategoryStat] (카테고리별 count, ratio)
- `totalCount`: Int
- `isPaired`: Bool
- `loadStats()`: 데이터 fetch + 계산

---

## 2. 검색 (SearchView)

### 데이터 흐름
1. RecordService로 기간별 records 조회
2. CategoryService로 카테고리 목록 조회
3. 클라이언트에서 카테고리ID + 키워드(memo) 필터링
4. 날짜 오름차순 정렬

### UI 구성
- **헤더**: "검색" 타이틀
- **필터 영역** (sticky):
  - Row 1: 연도 Picker + 월 Picker(전체/1~12)
  - Row 2: 카테고리 드롭다운(Menu) + 키워드 TextField
- **결과 목록**: 각 카드에
  - 날짜 ("3월 4일 화")
  - 카테고리 이모지 + 이름
  - "같이" 뱃지 (together=true일 때)
  - 메모 텍스트
- **빈 상태**: "검색 결과가 없습니다"

### SearchViewModel
- `selectedYear`, `selectedMonth` (0 = 전체)
- `selectedCategoryId`: Int?
- `keyword`: String
- `results`: [DailyRecord] (필터링된 결과)
- `categories`: [Category]
- `search()`: fetch + 필터링

---

## 3. 카테고리 관리 (CategoriesView)

### 데이터 흐름
- CategoryService CRUD: fetch / create / update / delete / reorder

### UI 구성
- **생성 폼** (상단):
  - 이모지 TextField + 이름 TextField + 활성 토글
  - 저장 버튼
- **카테고리 리스트**:
  - List + ForEach + .onMove로 드래그 정렬
  - 각 행: 드래그 핸들 + 이모지 + 이름 + 활성 뱃지(초록/회색)
  - 탭 → 인라인 편집모드 (이모지/이름/활성 수정 + 저장/취소)
  - 스와이프 → 삭제 (confirmationDialog)
- **정렬**: .onMove 시 optimistic UI update → CategoryService.reorder() 호출 → 실패 시 복원

### CategoriesViewModel
- `categories`: [Category]
- `newEmoji`, `newName`, `newIsActive`: 생성 폼 상태
- `editingId`: Int? (편집 중인 카테고리)
- `editEmoji`, `editName`, `editIsActive`: 수정 폼 상태
- `loadCategories()`, `createCategory()`, `updateCategory()`, `deleteCategory(_:)`, `reorderCategory(from:to:)`

---

## 4. 네비게이션

- SideDrawerView 메뉴 항목: 통계 / 검색 / 카테고리 관리 → NavigationStack으로 화면 전환
- CalendarHeaderView 검색 아이콘 → SearchView 직접 이동
- ContentView에 NavigationStack 래핑 + navigationDestination 추가
