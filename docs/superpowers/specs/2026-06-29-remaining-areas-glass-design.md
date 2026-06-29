# 남은 영역 — iOS 26 Glass 롤아웃 설계 (커플·검색·프로필·관리·카테고리)

작성일: 2026-06-29

## 목적

Foundation의 Liquid Glass 디자인 시스템을 아직 적용되지 않은 나머지 영역에 일괄 적용해 글래스 롤아웃을 완주한다. 대상: **Pair(커플), Search(검색), Profile(내 정보), Admin(관리), Category(카테고리), UserManagement(사용자 관리)**. (Auth/로그인은 이미 적용됨.)

## 확정 사항 (사용자 결정)

- **범위**: 남은 전부 한 사이클 — 5영역 7파일.
- **카드 없는 화면(PairView·ProfileView·PairEventsView 폼)**: GlassCard를 **신규 도입**해 카드 기반 글래스 언어로 통일.
- **버튼**: 모든 주요(채움형) CTA를 글래스로 통일 — `appGlassProminentButton()`(블루 prominent 글래스). 기존 회색(slate700)·주황(orange300) 버튼도 전부 글래스로 전환(solid 버튼 없음). 텍스트 링크형 보조 동작(해제/취소/복사 등 원래 채움 없던 것)은 텍스트 그대로 유지.
- **촘촘한 콘텐츠 유지**: 리스트 행, 입력 필드, 상태 칩, 토글, 진행 표시는 통째 글래스화하지 않음.
- glass-on-glass 금지.

## 대상 파일 (조사 결과)

- `PairView`(247줄) — 커플 메인. 배경 없음, 섹션이 카드 없이 떠 있음. 파랑 CTA(기념일 관리/코드 생성/수락), 텍스트 버튼(해제/취소/복사).
- `PairEventsView`(124줄) — 기념일 관리. 생성 폼(카드 없음) + `List(.plain)`. 파랑 CTA(추가).
- `SearchView`(164줄) — 검색. 상단 필터바 `.background(.white)` + 결과 카드(흰+stroke 다수). 파랑 CTA 없음.
- `ProfileView`(244줄) — 내 정보. 폼(카드 없음), 입력칸 다수, 저장 버튼 slate700.
- `CategoriesView`(325줄) — 카테고리 관리. 루트 `Color.slate50`, 생성 폼 흰 카드 + 목록(흰 bg, slate50 행). 추가하기 버튼 orange300, 편집 저장 blue500.
- `AdminView`(70줄) — 관리 허브. 흰+shadow 네비 카드 2개.
- `UserManagementView`(252줄) — 사용자 관리. 루트 `Color.slate50`, 생성 폼 흰 카드 + 목록 흰 카드(slate50 행). 사용자 추가 버튼 slate700, 편집 저장 blue500.

테스트 타깃 없음 → 검증은 `xcodebuild` 빌드. 신규 파일 없음 → pbxproj 작업 없음.

## 전역 규칙

- 화면 루트 → `glassScreenBackground()` (slate50→blue50 그라데이션).
- 흰 카드 컨테이너 → `glassEffect(.regular, in: RoundedRectangle(cornerRadius:))` 또는 `GlassCard`.
- 모든 채움형 주요 CTA → `appGlassProminentButton()`. solid 버튼 없음. 텍스트 링크형 보조 동작은 텍스트 유지.
- 촘촘한 콘텐츠(리스트 행/입력 필드/상태 칩/토글)는 plain.
- 리스트는 `scrollContentBackground(.hidden)` 등으로 그라데이션이 비치게(필요한 경우).
- glass-on-glass 금지: 글래스 카드 안 입력칸·행은 plain.

## 아키텍처 — 화면별

- **PairView**: 루트 `ScrollView` → `glassScreenBackground()`. `connectedSection`/`pendingSection`/`disconnectedSection`의 내용을 각각 **GlassCard**로 감싼다. 파랑 버튼(기념일 관리 85행 / 코드 생성 159행 / 수락 188행) → `appGlassProminentButton()`. 텍스트 버튼(페어 해제·초대 취소·코드 복사), 코드 입력 TextField, 하트 아이콘은 유지.
- **PairEventsView**: 루트 `VStack` → `glassScreenBackground()`. 생성 폼(10–52행)을 **GlassCard**로. "추가"(48행, 파랑) → glass. `List(.plain)`은 `scrollContentBackground(.hidden)`로 배경 투명화, 행 내용은 유지.
- **SearchView**: 루트 `VStack` → `glassScreenBackground()`. 상단 필터바 `.background(.white)`(78행) → `glassEffect(.regular, in: Rectangle())` 패널. `SearchResultCard`(흰+stroke, 다수)는 콘텐츠라 유지. 피커/메뉴/키워드 입력칸 유지.
- **ProfileView**: 루트 `ScrollView` → `glassScreenBackground()`. 폼 필드 전체를 **GlassCard**로 묶는다. 입력칸(흰+stroke)·아이디 readonly(slate100)·성별 토글·DatePicker는 유지. "저장"(현재 slate700) → `appGlassProminentButton()`로 전환.
- **CategoriesView**: 루트 `Color.slate50`(14행) → `glassScreenBackground()`. 생성 폼 흰 카드(87행) → `glassEffect`. 목록 컨테이너 `.background(.white)`(159행) → `glassEffect` 패널. 행(slate50)·입력칸·ACTIVE 칩·드래그 핸들 유지. "추가하기"(현재 orange300)·편집 저장(blue500) 모두 → `appGlassProminentButton()`로 전환.
- **AdminView**: 루트 `VStack` → `glassScreenBackground()`. `adminCard` 흰+shadow(63행) → `glassEffect`(탭 가능한 네비 카드). 아이콘 배경은 유지.
- **UserManagementView**: 루트 `Color.slate50`(90행) → `glassScreenBackground()`. 생성 폼 카드(47행)·목록 카드(84행) → `glassEffect`. 행(slate50)·입력칸·권한 칩/메뉴 유지. "사용자 추가"(현재 slate700)·편집 저장(blue500) 모두 → `appGlassProminentButton()`로 전환.

## 검증

- `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- 시뮬레이터/실기기 육안: 7개 화면 카드/버튼/리스트 가독성. 라이트/다크 모드, 투명도 줄이기 fallback.

## 리스크 / 엣지 케이스

1. **카드 신규 도입** — 기존에 카드가 없던 화면(Pair/Profile/PairEvents)에 GlassCard를 넣으면 레이아웃 간격이 달라질 수 있음. 기존 spacing/padding 최대한 보존.
2. **List 배경** — PairEventsView `List(.plain)`은 시스템 배경을 가지므로 `scrollContentBackground(.hidden)` 필요. iOS 26 동작 확인.
3. **입력칸 over glass** — 폼 카드 안 흰 입력칸은 편집 대비를 위해 solid 유지(콘텐츠). glass-on-glass 아님.
4. **버튼 색감** — 모든 주요 CTA를 블루 prominent 글래스로 통일(기존 회색/주황 색 정체성은 사라짐). 글래스 prominent 버튼이 글래스 카드 위에 올라가는 구성이 되므로(Apple 지원), 라이트/다크·투명도 줄이기에서 대비·가독성 시각 QA 필요.
5. **결과/행 다수** — Search 결과 카드, Category/User 행은 다수라 plain 유지(가독성/성능).
6. 라이트/다크 모드, 투명도 줄이기 fallback.

## 비범위

- 기능/로직 변경, 리스트 행·폼 입력 리디자인.
- 신규 파일/네비게이션 변경.
- Auth(이미 적용), 이미 적용된 영역 재작업.
