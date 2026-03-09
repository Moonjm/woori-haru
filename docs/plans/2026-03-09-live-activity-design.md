# 공부 타이머 Live Activity 설계

## 개요
공부 타이머 실행 중 Dynamic Island와 잠금화면에 타이머 상태를 표시하고, 일시정지/재개/종료 조작을 지원한다.

## 구성

| 영역 | 표시 내용 |
|------|----------|
| Dynamic Island (compact) | 과목 아이콘 + 경과시간 |
| Dynamic Island (minimal) | 과목 아이콘 |
| Dynamic Island (expanded) | 과목명, 경과시간, 일시정지/재개/종료 버튼 |
| 잠금화면 | 과목명, 경과시간, "일시정지" 라벨(일시정지 시) |

## 데이터

- **Attributes (고정)**: subjectName
- **ContentState (동적)**: timerState ("running"/"paused"), startDate, pausedElapsed

## 경과시간 표시

- Running: `Text(startDate, style: .timer)` — 시스템 자동 갱신
- Paused: 고정된 경과시간 문자열 + "일시정지" 라벨

## 버튼 동작

Deep Link(`wooriharu://study/pause|resume|end`)로 앱에 전달.
WooriHaruApp의 `onOpenURL`에서 StudyTimerViewModel 액션 호출.

## 파일 구조

| 파일 | 위치 | 타겟 |
|------|------|------|
| StudyTimerAttributes.swift | WooriHaru/Models/ | 메인 앱 + Widget Extension |
| StudyTimerLiveActivity.swift | StudyTimerWidget/ | Widget Extension |
| StudyTimerWidgetBundle.swift | StudyTimerWidget/ | Widget Extension |

## Xcode 설정 필요

1. File > New > Target > Widget Extension 추가 (이름: StudyTimerWidget)
2. "Include Live Activity" 체크
3. StudyTimerAttributes.swift를 Widget Extension 타겟에도 추가 (Target Membership)
4. 자동 생성된 파일 삭제 후 기존 파일 사용
