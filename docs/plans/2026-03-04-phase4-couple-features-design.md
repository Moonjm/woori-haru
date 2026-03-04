# Phase 4: 커플 기능 설계

## 목표

웹 앱의 커플 기능(PairPage, PairEventsPage, 캘린더 파트너 기록 표시)을 iOS로 구현한다. 서비스 레이어(PairService, PairEventService)는 이미 구축되어 있으므로 ViewModel + View + 캘린더 확장만 추가한다.

## 아키텍처

기존 Phase 2/3 패턴 동일: `@Observable` ViewModel + SwiftUI View + 기존 Service 재사용. SideDrawerView에서 커플 화면으로 네비게이션.

---

## 1. 페어링 관리 (PairView)

### 데이터 흐름
1. PairService.getStatus() → 현재 페어 상태 조회
2. 상태에 따라 3가지 UI 분기

### UI 구성
- **미연결 상태**:
  - "초대 코드 생성" 버튼 → createInvite() → 코드 표시
  - 구분선
  - "코드 입력" TextField(6자리) + "수락" 버튼 → acceptInvite()
- **PENDING 상태**:
  - 생성된 6자리 코드 대문자 표시
  - "코드 복사" 버튼 (UIPasteboard)
  - "초대 취소" 버튼 → unpair()
- **CONNECTED 상태**:
  - 파트너 이름 + 연결일 정보
  - "기념일 관리" 네비게이션 링크 → PairEventsView
  - "페어 해제" 버튼 → confirmationDialog → unpair()

### PairViewModel
- `pairInfo: PairInfo?`
- `inviteCode: String?` (생성된 초대 코드)
- `inputCode: String` (입력 중인 코드)
- `isLoading: Bool`, `errorMessage: String?`, `successMessage: String?`
- `loadStatus()`, `createInvite()`, `acceptInvite()`, `unpair()`

---

## 2. 기념일 관리 (PairEventsView)

### 데이터 흐름
- PairEventService: fetch / create / delete

### UI 구성
- **생성 폼** (상단):
  - 이모지 TextField(1자) + 제목 TextField(30자)
  - DatePicker(날짜) + "매년 반복" Toggle
  - "추가" 버튼
- **이벤트 목록**:
  - 각 행: 이모지 + 제목 + 날짜 + 반복 뱃지(🔄)
  - 스와이프 삭제 → confirmationDialog

### PairEventsViewModel
- `events: [PairEvent]`
- `newEmoji`, `newTitle`, `newDate: Date`, `newRecurring: Bool`
- `isLoading: Bool`, `errorMessage: String?`, `successMessage: String?`
- `loadEvents()`, `createEvent()`, `deleteEvent(_:)`

---

## 3. 캘린더 확장 (파트너 기록 + 기념일 + 생일)

### CalendarViewModel 변경
- `partnerRecordsByDate: [String: [DailyRecord]]` 추가
- `pairEventsByDate: [String: [PairEvent]]` 추가
- `birthdayMap: [String: [(emoji: String, label: String)]]` 추가
- `isPaired: Bool` (PairService 상태 연동)
- `loadMonthData()` 확장: 페어링 시 파트너 기록 + 기념일 추가 fetch

### 생일 로직
- 내 생일: User.birthDate → "🎂" + (gender에 따라 "👨"/"👩") + "내 생일"
- 파트너 생일: PairInfo.partnerBirthDate → "🎂" + (gender) + "{이름} 생일"
- recurring: MM-DD 기준으로 매년 표시

### DayCellView 변경
```
┌─────────────────────┐
│  날짜 + 과식        │
│  공휴일             │
│  기념일/생일 이모지  │
│  🔵 같이 한 것      │
│  ────────────       │
│  내 기록 | 파트너   │ (파트너: opacity 0.6)
└─────────────────────┘
```

- 기념일/생일 이모지: pairEventsByDate + birthdayMap
- "같이 한 것": 내 records + 파트너 records 중 together=true인 것 (파란 배경)
- 개별 기록: 왼쪽 내 기록, 오른쪽 파트너 기록 (파트너는 opacity 0.6)

### RecordSheetView 변경
- 섹션 구분 (페어링 시):
  1. "👫 같이 한 것" (내 together + 파트너 together)
  2. "나의 기록" (내 solo)
  3. "{파트너이름}의 기록" (파트너 solo, 읽기 전용)
- 미페어링 시: 기존과 동일

---

## 4. 네비게이션

- AppDestination에 `.pair`, `.pairEvents` 추가
- SideDrawerView "커플" 메뉴 → `.pair`
- PairView CONNECTED → "기념일 관리" → `.pairEvents`
- ContentView navigationDestination 추가
