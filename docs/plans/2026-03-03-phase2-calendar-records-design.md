# Phase 2: 캘린더 & 기록 - 설계 문서

## 범위

Phase 2에서 구현하는 기능:
- 캘린더 무한스크롤 (상단 헤더 + 월별 그리드)
- 내 기록 CRUD (바텀시트)
- 과식 레벨 선택기
- 공휴일 표시
- 사이드 드로어 (햄버거 메뉴)
- 연/월 빠른 이동 피커

제외 (Phase 4): 파트너 기록 표시, 같이한 기록 구분, 페어 이벤트/생일

---

## 네비게이션 구조

웹과 동일:
- 상단 헤더: 햄버거 메뉴 | 연/월 표시 | 검색 아이콘
- 본문: 캘린더 무한스크롤
- 하단 탭바 없음
- 사이드 드로어에서 통계/검색/페어/설정 접근

---

## 캘린더 무한스크롤

방식: ScrollView + LazyVStack
- 초기 로드: 현재 월 ± 2개월 (5개월)
- 스크롤 끝 감지 시 양방향으로 월 추가
- 월별 API 데이터 캐싱 (로드한 월은 재요청 안함)
- scrollTo로 연/월 피커에서 빠른 이동
- 요일 헤더(일~토)는 스크롤 밖에 고정

---

## 날짜 셀 표시

```
┌────────┐
│ 3  🐷  │  날짜 + 과식 아이콘
│ 설날   │  공휴일 라벨 (빨간 배경)
│ 🍚☕🍜 │  내 기록 이모지들
└────────┘
```

색상 규칙:
- 오늘: 검정 원 배경 + 흰 글씨
- 토요일: 파란색
- 일요일/공휴일: 빨간색
- 과식 레벨별 🐷 색상: 초록(MILD), 주황(MODERATE), 빨강(SEVERE), 무지개(EXTREME)

---

## 바텀시트 (기록)

날짜 탭 시 .sheet로 열림 (.presentationDetents([.fraction(0.7)]))

구성:
1. 드래그 핸들
2. 헤더: "M월 D일 dddd" + 공휴일 라벨
3. 과식 레벨 선택기 (5단계 가로 버튼)
4. 기록 목록 (이모지 + 카테고리명 + 메모, 삭제 가능, 탭하면 편집)
5. 기록 입력 폼 (카테고리 선택 + 메모 + 저장 버튼)

---

## 파일 구조

```
ViewModels/
  CalendarViewModel.swift     # 월 데이터 관리, 스크롤 범위
  RecordViewModel.swift       # 기록 CRUD, 과식 레벨

Views/
  Calendar/
    CalendarView.swift         # 메인 (헤더+스크롤+시트)
    CalendarHeaderView.swift   # 햄버거/연월/검색
    WeekdayHeaderView.swift    # 일~토 고정 헤더
    MonthGridView.swift        # 월별 7열 그리드
    DayCellView.swift          # 날짜 셀
    YearMonthPickerView.swift  # 연/월 빠른 이동
  Record/
    RecordSheetView.swift      # 바텀시트 컨테이너
    RecordListView.swift       # 기록 목록
    RecordFormView.swift       # 기록 입력 폼
    OvereatSelectorView.swift  # 과식 레벨 5단계
  Components/
    SideDrawerView.swift       # 햄버거 메뉴

Extensions/
  Color+Extensions.swift       # Tailwind 색상 매핑
  Date+Extensions.swift        # 날짜 유틸리티
```

---

## 데이터 흐름

```
CalendarViewModel
  ├─ months: [MonthData]           # 로드된 월 목록
  ├─ records: [String: [Record]]   # 날짜별 기록 캐시
  ├─ overeats: [String: Level]     # 날짜별 과식 캐시
  ├─ holidays: [String: [String]]  # 날짜별 공휴일
  └─ loadMonth(year, month)        # API 호출 + 캐시

RecordViewModel
  ├─ selectedDate: String
  ├─ records / overeatLevel
  ├─ categories: [Category]
  └─ createRecord / updateRecord / deleteRecord / updateOvereat
```

CalendarView에서 CalendarViewModel을 소유하고, 날짜 탭 시 RecordViewModel에 선택 날짜를 전달하여 바텀시트를 표시한다.

---

## 참고 웹 소스

- Calendar: `/Users/jm/Documents/study/toy-repo/apps/daily-record/src/components/Calendar/`
- RecordSheet: `/Users/jm/Documents/study/toy-repo/apps/daily-record/src/components/RecordSheet/`
- SideDrawer: `/Users/jm/Documents/study/toy-repo/apps/daily-record/src/components/SideDrawer.tsx`
