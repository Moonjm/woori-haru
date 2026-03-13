# CLAUDE.md

## 리팩토링 계획

아키텍처 리뷰 기반 리팩토링 순서 (우선순위 높은 순):

### 1. [완료] StudyTimerViewModel 분리 (PR #22)
- NotificationScheduler, LiveActivityCoordinator 별도 클래스로 추출
- 모든 Service struct에 @MainActor 추가 (Swift 6 호환)

### 2. [완료] 공유 도메인 Store 생성 (PR #23, #24)
- PairStore, CategoryStore, SubjectStore, PauseTypeStore 도입
- 여러 ViewModel에서 중복되는 상태를 단일 Store로 통합
- @Environment로 주입, private(set) + configure() 패턴 적용

### 3. [완료] Session/Auth 인프라 분리 (PR #25)
- SessionManager 도입 — URLSession 소유, 토큰 갱신, 세션 만료 처리
- APIClient는 순수 HTTP 통신만 담당하도록 경량화
- os.Logger 기반 로깅 적용

---

### 4. [완료] Task 경쟁 조건 수정 (PR #26)
- ViewModel 내부에서 단일 task 관리로 이전 요청 cancel 후 새 요청 시작
- View의 onChange에서 Task 직접 생성 대신 VM의 reload 메서드 호출

### 5. [완료] 단순 ViewModel 제거 (PR #27)
- PairViewModel 제거 — View에서 PairStore 직접 사용
- 나머지 VM은 폼 상태 + CRUD 로직이 복잡하여 유지

### 6. [완료] CalendarView 동기화 허브 해소 (PR #28)
- holidayNames를 RecordViewModel에서 제거, RecordSheetView가 직접 파라미터로 수신
- RecordStore 도입은 불필요 판단 (records는 날짜별 fetch, 공유 필요 없음)

---

### 7. APIClient actor/Sendable 전환
- @MainActor 싱글턴 → actor 또는 Sendable 기반 인프라로 전환
- Swift 6 strict concurrency 대응
- 테스트 대체 가능한 구조로 개선
