# 공부 타이머 설계 (1차)

## 개요

세무사 시험 과목별 공부 시간을 기록하는 타이머 기능.
카테고리 선택 후 타이머 시작, 1시간마다 알림, 일시정지/재개, 종료 시 서버 저장.

## 과목 카테고리 (Enum)

| Enum값 | 이모지 | 과목명 |
|--------|--------|--------|
| FISCAL | 🏛️ | 재정학 |
| TAX_LAW_INTRO | 📜 | 세법학개론 |
| ACCOUNTING_INTRO | 📊 | 회계학개론 |
| COMMERCIAL_LAW | ⚖️ | 상법/민법/행정소송법 |
| TAX_LAW_1 | 📕 | 세법학 1부 |
| TAX_LAW_2 | 📗 | 세법학 2부 |
| FINANCIAL_ACCOUNTING | 🧮 | 회계학 1부 (재무회계) |
| COST_ACCOUNTING | 💰 | 회계학 2부 (원가/관리회계) |

백엔드: `StudySubject` enum. `GET /study/subjects`로 iOS에 제공.

## DB 테이블

### study_sessions

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | BIGINT PK | auto increment |
| user_id | BIGINT FK | users 참조 |
| subject | VARCHAR(30) | enum 값 |
| started_at | TIMESTAMP | 타이머 시작 시각 |
| ended_at | TIMESTAMP (nullable) | 종료 시각 |
| total_seconds | BIGINT | 순공부시간 (초, 일시정지 제외) |
| created_at / updated_at | TIMESTAMP | BaseEntity 상속 |

### study_pauses

| 컬럼 | 타입 | 설명 |
|------|------|------|
| id | BIGINT PK | auto increment |
| session_id | BIGINT FK | study_sessions 참조 |
| paused_at | TIMESTAMP | 일시정지 시작 |
| resumed_at | TIMESTAMP (nullable) | 재개 시각 (null이면 정지중) |
| created_at / updated_at | TIMESTAMP | BaseEntity 상속 |

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| GET | /study/subjects | 과목 목록 조회 |
| POST | /study/sessions | 세션 시작 (subject 전달) |
| PATCH | /study/sessions/{id}/pause | 일시정지 |
| PATCH | /study/sessions/{id}/resume | 재개 |
| PATCH | /study/sessions/{id}/end | 종료 (totalSeconds 계산) |
| GET | /study/sessions | 세션 목록 조회 (날짜 필터) |

## iOS 화면

### 타이머 화면 (StudyTimerView)

- 과목 선택: 가로 스크롤 이모지+과목명 버튼
- 경과 시간: 00:00:00 (순공부시간 실시간 표시)
- 버튼 상태:
  - 초기: [시작]
  - 진행중: [일시정지] [종료]
  - 일시정지: [재개] [종료]
- 종료 시 서버에 세션 데이터 저장

### 진입점

사이드 드로어 메뉴에 "공부 타이머" 항목 추가 → StudyTimerView로 네비게이션.

## 로컬 알림 (순공부시간 기준 1시간)

단순 반복이 아닌, 누적 공부시간 기준으로 1시간마다 알림.

### 로직

1. 시작 → 60분 후 단발 알림 예약
2. 일시정지 → 알림 취소, 남은 시간 저장 (예: 30분 남음)
3. 재개 → 남은 시간(30분) 후 알림 예약
4. 알림 발생 → 다시 60분 후 알림 예약
5. 종료 → 모든 알림 취소

### 예시

```
[시작]              → 60분 알림 예약
[30분 경과, 정지]   → 알림 취소, 남은시간=30분
[재개]              → 30분 알림 예약
[30분 후 알림 발생]  → 60분 알림 예약
[종료]              → 알림 취소
```

## 2차 개발 (별도)

- Live Activity (잠금화면 / Dynamic Island)
- Widget Extension 타겟 추가
