# Daily Record: 웹 → iOS 네이티브 전환 계획

## 현재 상태

### 웹 (daily-record)
- React 19 + TypeScript + Tailwind CSS
- REST API 백엔드 연동 (localhost:8080)
- 7개 페이지, 6개 커스텀 훅, 5개 API 모듈

### iOS (WooriHaru)
- SwiftUI 초기 템플릿 (빈 프로젝트)
- iOS 17+, Bundle ID: com.jm.woori-haru
- Firebase 설정 완료 (GoogleService-Info.plist)

---

## 웹 앱 기능 목록 & 전환 대상

| # | 기능 | 웹 구현 | iOS 전환 |
|---|------|---------|----------|
| 1 | 캘린더 (무한스크롤) | IntersectionObserver + lazy load | ScrollView + LazyVStack |
| 2 | 일일 기록 CRUD | 바텀시트 + 폼 | .sheet + Form |
| 3 | 카테고리 관리 (이모지+이름) | 드래그앤드롭 리스트 | List + onMove |
| 4 | 과식 레벨 기록 | 5단계 선택기 | Picker / 커스텀 버튼 |
| 5 | 통계 | 바 차트 + 필터 | Charts 프레임워크 |
| 6 | 검색 | 필터 + 키워드 검색 | .searchable + 필터 |
| 7 | 커플 페어링 | 초대코드 생성/수락 | 동일 API 연동 |
| 8 | 페어 이벤트 (기념일) | CRUD + 반복 설정 | List + Form |
| 9 | 공휴일 표시 | GET /holidays?year= API | API 조회 (HolidayService) |
| 10 | 생일 표시 | 유저/파트너 생일 계산 | 동일 로직 |
| 11 | 인증 (로그인/프로필) | @repo/auth 패키지 | 별도 구현 필요 |
| 12 | 관리자 (유저관리) | 어드민 전용 라우트 | 관리자 탭/섹션 |

---

## 데이터 모델 (Swift 변환)

```swift
// MARK: - 일일 기록
struct DailyRecord: Codable, Identifiable {
    let id: Int
    let date: String              // "YYYY-MM-DD"
    let memo: String?             // 최대 20자
    let category: Category
    let together: Bool            // 커플 함께 여부
}

// MARK: - 카테고리
struct Category: Codable, Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let isActive: Bool
    let sortOrder: Int
}

// MARK: - 과식 레벨
enum OvereatLevel: String, Codable {
    case none = "NONE"
    case mild = "MILD"
    case moderate = "MODERATE"
    case severe = "SEVERE"
    case extreme = "EXTREME"
}

// MARK: - 페어 (커플)
struct PairInfo: Codable {
    let id: Int
    let status: PairStatus
    let partnerName: String?
    let connectedAt: String?
    let partnerGender: Gender?
    let partnerBirthDate: String?
}

enum PairStatus: String, Codable {
    case pending = "PENDING"
    case connected = "CONNECTED"
}

// MARK: - 페어 이벤트
struct PairEvent: Codable, Identifiable {
    let id: Int
    let title: String
    let emoji: String
    let eventDate: String         // "YYYY-MM-DD"
    let recurring: Bool           // 매년 반복
}

// MARK: - 공휴일
struct Holiday: Codable {
    let date: String
    let localName: String?
    let name: String?
}
```

---

## API 클라이언트 (기존 백엔드 재사용)

```
Base URL: https://tree.eunji.shop/api

일일 기록:
  GET    /daily-records?date=&from=&to=
  POST   /daily-records
  PUT    /daily-records/:id
  DELETE /daily-records/:id

과식 레벨:
  GET    /daily-overeats?from=&to=
  PUT    /daily-overeats

카테고리:
  GET    /categories?active=
  POST   /categories
  PUT    /categories/:id
  DELETE /categories/:id
  PUT    /categories/order

페어:
  GET    /pair
  POST   /pair/invite
  POST   /pair/accept
  DELETE /pair
  GET    /pair/daily-records?date=&from=&to=

페어 이벤트:
  GET    /pair/events?from=&to=
  POST   /pair/events
  DELETE /pair/events/:id
```

---

## 프로젝트 구조 (목표)

```
WooriHaru/
├── App/
│   └── WooriHaruApp.swift
├── Models/
│   ├── DailyRecord.swift
│   ├── Category.swift
│   ├── OvereatLevel.swift
│   ├── PairInfo.swift
│   ├── PairEvent.swift
│   └── Holiday.swift
├── Services/
│   ├── APIClient.swift            # 공통 HTTP 클라이언트
│   ├── AuthService.swift          # 인증/토큰 관리
│   ├── RecordService.swift        # 일일 기록 API
│   ├── CategoryService.swift      # 카테고리 API
│   ├── PairService.swift          # 페어 API
│   ├── PairEventService.swift     # 페어 이벤트 API
│   └── HolidayService.swift       # 공휴일 로드
├── ViewModels/
│   ├── CalendarViewModel.swift
│   ├── RecordViewModel.swift
│   ├── StatsViewModel.swift
│   ├── SearchViewModel.swift
│   ├── PairViewModel.swift
│   ├── CategoryViewModel.swift
│   └── AuthViewModel.swift
├── Views/
│   ├── Calendar/
│   │   ├── CalendarView.swift     # 메인 캘린더
│   │   ├── MonthGridView.swift    # 월별 그리드
│   │   ├── DayCellView.swift      # 날짜 셀
│   │   └── YearMonthPicker.swift  # 연/월 선택
│   ├── Record/
│   │   ├── RecordSheetView.swift  # 기록 바텀시트
│   │   ├── RecordFormView.swift   # 기록 입력 폼
│   │   ├── RecordListView.swift   # 기록 목록
│   │   └── OvereatSelector.swift  # 과식 레벨 선택
│   ├── Stats/
│   │   └── StatsView.swift        # 통계
│   ├── Search/
│   │   └── SearchView.swift       # 검색
│   ├── Pair/
│   │   ├── PairView.swift         # 페어링 관리
│   │   └── PairEventsView.swift   # 페어 이벤트
│   ├── Category/
│   │   └── CategoryManageView.swift # 카테고리 관리
│   ├── Auth/
│   │   ├── LoginView.swift        # 로그인
│   │   └── ProfileView.swift      # 프로필
│   └── Components/
│       ├── MainTabView.swift      # 하단 탭바
│       └── LoadingView.swift      # 로딩 표시
├── Resources/
│   ├── holidays/                  # 공휴일 JSON (2018-2026)
│   └── GoogleService-Info.plist
└── Extensions/
    ├── Date+Extensions.swift
    └── Color+Extensions.swift
```

---

## 구현 단계 (Phase)

### Phase 1: 기반 구축
- [ ] 프로젝트 폴더 구조 생성
- [ ] 데이터 모델 정의 (Models/)
- [ ] API 클라이언트 구현 (URLSession + async/await)
- [ ] 인증 서비스 구현 (토큰 저장/관리 - Keychain)
- [ ] 로그인 화면

### Phase 2: 핵심 기능 - 캘린더 & 기록
- [ ] 메인 탭바 (캘린더, 통계, 검색, 설정)
- [ ] 캘린더 뷰 (월별 그리드, 스크롤)
- [ ] 날짜 셀 (이모지, 공휴일, 과식 표시)
- [ ] 기록 바텀시트 (생성/수정/삭제)
- [ ] 과식 레벨 선택기
- [ ] 공휴일 JSON 로드 & 표시
- [ ] 연/월 빠른 이동 피커

### Phase 3: 부가 기능
- [ ] 통계 화면 (카테고리별 빈도, 필터)
- [ ] 검색 화면 (키워드, 카테고리, 기간 필터)
- [ ] 카테고리 관리 (추가/수정/삭제/정렬)

### Phase 4: 커플 기능
- [ ] 페어링 (초대코드 생성/수락/해제)
- [ ] 파트너 기록 표시 (캘린더에 함께 보기)
- [ ] 페어 이벤트 관리 (기념일, 생일)
- [ ] 생일 표시

### Phase 5: 마무리
- [ ] 프로필 화면
- [ ] 앱 아이콘 & 런치스크린
- [ ] 에러 처리 & 빈 상태 UI
- [ ] 오프라인 대응 (캐싱)

---

## 기술 스택 (iOS)

| 영역 | 기술 |
|------|------|
| UI | SwiftUI |
| 아키텍처 | MVVM |
| 네트워크 | URLSession + async/await |
| 데이터 저장 | Keychain (토큰), UserDefaults (설정) |
| 차트 | Swift Charts (iOS 16+) |
| 날짜 처리 | Foundation (Calendar, DateFormatter) |
| 최소 지원 | iOS 17.0 |

---

## 웹 → iOS 주요 매핑

| 웹 (React) | iOS (SwiftUI) |
|-------------|---------------|
| React Router | NavigationStack + TabView |
| React Query | @Observable ViewModel + async/await |
| useState/useEffect | @State / .task / .onChange |
| Tailwind CSS | SwiftUI 내장 스타일 |
| 바텀시트 | .sheet / .presentationDetents |
| IntersectionObserver | ScrollView + LazyVStack |
| fetch() | URLSession.shared.data() |
| localStorage | UserDefaults / Keychain |
| @dnd-kit | List + .onMove |
| dayjs | Foundation Date/Calendar |
