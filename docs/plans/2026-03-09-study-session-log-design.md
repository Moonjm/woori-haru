# 공부 세션 캘린더 기록 뷰

## 개요
구글 캘린더 스타일로 공부 세션 기록을 날짜별로 보여주는 뷰.
StudyTimerView의 `오늘 기록` 하단에 `전체 기록` 버튼 → NavigationStack push.

## 레이아웃
- 세로 스크롤 리스트, 오늘 기준 위=과거/아래=미래
- 왼쪽: 날짜+요일 (예: `9 일`), 오른쪽: 세션 블록들
- 세션 블록: blue 배경, 과목명 + 시간 범위
- 세션 없는 날도 날짜 표시
- 무한 스크롤 (월 단위 lazy load)

## 데이터
- `StudyService.fetchSessions(from:to:)` 사용
- `StudySessionLogViewModel`에서 월 단위 fetch, 날짜별 그룹핑

## 네비게이션
- `AppDestination.studySessionLog` 추가
- StudyTimerView `오늘 기록` 섹션 하단에 버튼 추가
