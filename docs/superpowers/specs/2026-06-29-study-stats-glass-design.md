# 공부·통계 영역 — iOS 26 Glass 롤아웃 설계

작성일: 2026-06-29

## 목적

Foundation의 Liquid Glass 디자인 시스템을 공부(Study) 영역에 적용한다. 통계(StatsView)는 Foundation 사이클에서 이미 글래스가 적용됐으므로 일관성 검토만 한다.

## 확정 사항 (사용자 결정)

- 적용 범위: 시트 + 카드 + 배경 (이전 영역들과 일관).
- 화면 배경 → `glassScreenBackground()`, 흰 카드 컨테이너 → `GlassCard`/`glassEffect`, 주요 버튼 → glass.
- **촘촘한 콘텐츠 유지**: 진행바/그래프 막대, 주간 확장 행 내용, 통계 막대는 통째 글래스화하지 않음.
- glass-on-glass 금지. 한 화면에서만 쓰이는 하위뷰는 부모가 글래스면 자식은 plain.

## 대상 파일 (조사 결과)

- `StudyTimerView`(643줄) — 공부 타이머 메인. 루트 `Color.slate50`(30행), 흰 카드(132행 `RoundedRectangle 20` 등), 시작/일시정지/종료 등 버튼.
- `StudyRecordView`(245줄) — 루트 `Color.slate50`(23행), 흰 카드(125/175/242행 `RoundedRectangle 16`), 내부 slate50 서브카드(198행)·진행바.
- `WeeklyStudyRecordSection`(327줄) — 흰 카드(43행 `RoundedRectangle 16`), 확장 행(153행 `blue50/slate50`)·막대(`UnevenRoundedRectangle`).
- `StatsView`(123줄) — **이미 글래스 적용됨**(GlassCard×2 + `glassScreenBackground`, Foundation). 검토만, 변경 없으면 그대로.

테스트 타깃 없음 → 검증은 `xcodebuild` 빌드. 신규 파일 없음 → pbxproj 작업 없음.

## 아키텍처 — 화면별

- **StudyTimerView**: 루트 `Color.slate50` → `.glassScreenBackground()`. 흰 카드(타이머 표시 카드 132행 등) → `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: <기존>))`. 주요 버튼(시작/일시정지/종료) → glass. 단, 파란 채움+어두운 아이콘 색감 충돌이 생기면 plain glass 또는 solid 유지(보관함 추가 버튼 교훈). 작은 칩/입력칸(slate50)·진행 표시는 유지.
- **StudyRecordView**: 루트 slate50 → 배경. 흰 카드(125/175/242행) → glass. 내부 slate50 서브카드(198행)·진행바(`RoundedRectangle 3/4/6`)는 유지(콘텐츠).
- **WeeklyStudyRecordSection**: 흰 카드(43행) → glass. 확장 행(153행)·막대(`UnevenRoundedRectangle`)는 콘텐츠라 유지. 부모 카드만 글래스. glass-on-glass 주의(이 섹션이 StudyRecordView의 글래스 카드 안에 들어가면 중첩되지 않도록 — 배치 확인 후 적용).
- **StatsView**: 이미 적용. 일관성 확인, 필요시 미세 조정만.

## 검증

- `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- 시뮬레이터/실기기 육안: 타이머 카드/버튼, 공부 기록 카드, 주간 섹션 가독성. 라이트/다크 모드, 투명도 줄이기.

## 리스크 / 엣지 케이스

1. **타이머 버튼 색감** — 파란 채움 prominent + 어두운 아이콘 충돌 회피(필요시 plain glass 또는 solid). 직전 보관함 추가 버튼과 동일 교훈.
2. **glass-on-glass** — WeeklyStudyRecordSection이 StudyRecordView 글래스 카드 내부에 배치되는지 확인. 중첩되면 부모만 글래스, 자식 plain. 시트/카드 안에 또 글래스 금지.
3. **큰 파일(StudyTimerView 643줄)** — 흰 카드/배경 여러 곳. 누락/과적용 주의, 읽고 신중히.
4. **진행바/그래프 가독성** — 막대·진행 표시는 유지.
5. 라이트/다크 모드, 투명도 줄이기 fallback.

## 비범위

- 커플·검색, 프로필·인증·관리 — 후속 사이클.
- StatsView 대규모 변경(이미 적용됨), 기능/로직 변경, 그래프/진행바 리디자인.
