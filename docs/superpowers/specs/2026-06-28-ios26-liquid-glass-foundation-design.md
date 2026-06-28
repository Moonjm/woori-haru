# iOS 26 대응 · Liquid Glass 도입 — Foundation 설계

작성일: 2026-06-28

## 목적

WooriHaru 앱을 iOS 26 디자인 언어(Liquid Glass)에 맞춰 현대화한다. 본 문서는 **Foundation(서브 프로젝트 1)** 만 다룬다: 배포 타깃 상향, 재사용 가능한 Glass 디자인 시스템 구축, 전역 크롬 적용, 대표 화면 파일럿. 28개 화면의 개별 적용은 후속 사이클(영역별 설계→계획→구현)로 분리한다.

## 확정 사항 (사용자 결정)

- **최소 배포 타깃: iOS 26.0** 으로 상향 (메인 앱). → 가용성 가드(`if #available`) 불필요, Glass 무조건 적용 가능.
- **적용 범위: 전체 화면 적극 적용** (단, 본 Foundation은 기반 + 파일럿까지).
- **작업 성격: Glass + iOS 26 전반 현대화.** 단, 실측 결과 현재 코드는 iOS 26.5 SDK 빌드 시 **deprecation 경고 0건**(무관한 AppIntents 메타데이터 안내 1건 제외) → 현대화 부담은 적고 핵심은 Glass.
- **접근 방식 A** — 공용 Glass 디자인 시스템 먼저, 이후 영역별 적용.

## 현재 구조 (조사 결과)

- 앱 진입: `WooriHaruApp` → `ContentView`(`NavigationStack` + `AppDestination`) / `LoginView`. **TabView 미사용**, 커스텀 `SideDrawerView`로 메뉴.
- UI: 흰 배경 하드코딩, slate/blue 팔레트(`Color+Extensions.swift`), 커스텀 카드(`RoundedRectangle().fill(.white).stroke()`), `.buttonStyle(.plain)` 광범위, 일부 `.borderedProminent`.
- 테스트 타깃 없음 → 검증은 `xcodebuild` 빌드 성공.
- 메인 타깃은 pbxproj **명시적 파일 참조**(동기화 그룹 아님) → 신규 파일 수동 등록 필요(미등록 시 빌드 false-positive 통과).
- SDK: iphoneos 26.5.

## 아키텍처 — 공용 Glass 디자인 시스템

신규 디렉터리 `WooriHaru/Views/Components/Glass/`, 작은 단일 책임 파일로 분리:

- **`GlassCard.swift`** — `GlassCard<Content: View>`: `content`를 `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: token))`로 감싸는 카드 래퍼. 기존 `RoundedRectangle().fill(.white).stroke()` 카드 패턴의 표준 교체물. 패딩·모서리 토큰화.
- **`GlassButtonStyles.swift`** — 주요 CTA용/보조용 glass 버튼 스타일. 주요: `.glassProminent`(앱 액센트 틴트), 보조: `.glass`. 필요한 곳의 `.plain` 탭 타깃만 선별 승격.
- **`GlassBackground.swift`** — 화면 최하단 배경 레이어(앱 액센트 기반 소프트 그라데이션 또는 시스템 grouped 배경 계열). glass가 비쳐 보이도록 하는 토대. 기존 흰색 하드코딩을 점진 대체.
- (선택) **`GlassTokens.swift`** — 모서리 반경/간격/틴트 등 공용 토큰.

원칙: 텍스트·차트 색은 기존 팔레트 유지(glass는 재질 레이어). 인접 glass 요소는 `GlassEffectContainer`로 묶되, **컨테이너는 레이아웃 스택이 아니므로 내부에 `VStack`/`HStack` 필수**.

## 전역 크롬 적용

- **배경 레이어**: Liquid Glass는 뒤 콘텐츠가 비쳐야 효과가 산다. 불투명 흰 배경 위에서는 밋밋 → `GlassBackground`를 도입해 그 위에 glass 크롬/카드가 입체적으로 보이게 한다.
- **내비게이션 바/툴바**: iOS 26 SDK 빌드 시 대부분 자동 glass. 불투명 배경 강제(`toolbarBackground` 등)가 있으면 제거해 자동 glass 복원(현재 강제 배경 거의 없음).
- **사이드 드로어(`SideDrawerView`)**: 현재 `.background(.white)` → glass 재질로 교체(떠 있는 패널). Foundation 대표 크롬 적용 대상.
- **시트(`.sheet`)**: iOS 26 자동 glass 표현 확인(표시 시 깨짐 없음).
- **하단 주요 액션 바**: 존재 시 floating glass 바.

## 파일럿 화면

디자인 언어 확정용 대표 3종(후속 영역 작업이 이를 그대로 따름):
1. `SideDrawerView` — 크롬 대표
2. `StatsView`(또는 `StorageMainView`) — 카드 대표
3. `LoginView` — 버튼 대표

## 검증

- `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **`.
- 신규 파일은 빌드 산출물 `WooriHaru.SwiftFileList`에 포함됐는지로 실제 컴파일 확인.
- **Glass는 시각 요소 → 시뮬레이터/실기기 육안 확인 필수**: 가독성·대비·레이아웃, 라이트/다크 모드 양쪽.

## 리스크 / 엣지 케이스

1. **가독성** — slate 텍스트가 glass 위에서 흐려질 수 있음 → 배경 레이어 + 필요 시 대비 보정.
2. **대형 콘텐츠 glass 과용** — Apple은 glass를 크롬/컨트롤용으로 권장. 카드는 적용하되 가독성 모니터링, 과하면 일부 불투명 유지.
3. **레이아웃 회귀** — `GlassEffectContainer`에 내부 스택 누락 시 뷰가 겹침(빌드로 안 잡힘 → 육안 확인).
4. **pbxproj** — 신규 파일 4곳 수동 등록(PBXBuildFile/PBXFileReference/그룹 children/Sources phase) + `plutil -lint` 검증.
5. **접근성/모드** — 다크 모드, Reduce Transparency 시 fallback 동작 확인.

## 후속 (비범위, 참고)

영역별 적용 사이클: 캘린더 / 기록·보관함 / 공부·통계 / 커플·검색 / 프로필·인증·관리 — 각각 별도 설계→계획→구현. Foundation에서 확정한 `GlassCard`/버튼 스타일/배경을 재사용.
