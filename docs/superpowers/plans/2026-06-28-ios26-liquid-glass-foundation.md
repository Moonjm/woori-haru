# iOS 26 · Liquid Glass Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iOS 26 배포 타깃 상향 + 재사용 Liquid Glass 디자인 시스템 구축 + 전역 크롬(사이드 드로어) 적용 + 대표 화면 2개 파일럿으로 디자인 언어 확정.

**Architecture:** 접근 방식 A — 공용 컴포넌트(`GlassCard`, glass 버튼 스타일, `GlassBackground`)를 `WooriHaru/Views/Components/Glass/`에 먼저 만들고, 사이드 드로어와 파일럿 화면(LoginView/StatsView)에 적용한다. 28개 화면 전체 적용은 후속 사이클.

**Tech Stack:** Swift, SwiftUI, iOS 26 Liquid Glass(`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`/`.glassProminent`).

## Global Constraints

- 최소 배포 타깃: **iOS 26.0** (메인 앱). 가용성 가드 불필요.
- 텍스트/차트 색은 기존 `Color+Extensions.swift` 팔레트 유지. glass는 재질 레이어.
- 테스트 타깃 없음 → 검증은 빌드 성공:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.
- SourceKit/IDE 진단이 "타입 못 찾음"을 보여도 무시 — xcodebuild가 정답. **단** 메인 타깃은 pbxproj 명시적 참조 방식이라 신규 `.swift`는 반드시 등록(미등록 시 빌드 false-positive). 등록 후 빌드 산출물 `WooriHaru.SwiftFileList`에 파일 포함 확인.
- Glass는 시각 요소 → 각 적용 후 시뮬레이터/실기기 육안 확인(최종 Task에서 일괄).
- `GlassEffectContainer`는 레이아웃 스택이 아님 → 내부에 반드시 `VStack`/`HStack`.

---

## File Structure

신규 (모두 `WooriHaru/Views/Components/Glass/`):
- `GlassTokens.swift` — 모서리/패딩/틴트 토큰.
- `GlassCard.swift` — 공용 glass 카드 래퍼.
- `GlassButtonStyles.swift` — glass 버튼용 `View` 확장.
- `GlassBackground.swift` — 화면 배경 레이어 + `.glassScreenBackground()` 확장.

수정:
- `WooriHaru.xcodeproj/project.pbxproj` — 신규 4파일 등록 + `Glass` 그룹 생성.
- `WooriHaru/Views/Components/SideDrawerView.swift` — 패널 glass화.
- `WooriHaru/Views/Auth/LoginView.swift` — 파일럿(버튼/카드/배경).
- `WooriHaru/Views/Stats/StatsView.swift` — 파일럿(배경/카드).

---

## Task 1: 배포 타깃 iOS 26.0 상향

**Files:**
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (두 곳의 `IPHONEOS_DEPLOYMENT_TARGET = 17.0`)

- [ ] **Step 1: 배포 타깃 변경**

다음 명령으로 메인 앱의 두 config(Debug/Release)를 17.0 → 26.0으로 변경:
```bash
cd /Users/youngminmoon/Documents/moonjm/woori-haru
sed -i '' 's/IPHONEOS_DEPLOYMENT_TARGET = 17.0;/IPHONEOS_DEPLOYMENT_TARGET = 26.0;/g' WooriHaru.xcodeproj/project.pbxproj
```
(위젯의 26.2는 건드리지 않는다 — 이미 26.x.)

- [ ] **Step 2: pbxproj 유효성 + 빌드 검증**

```bash
plutil -lint WooriHaru.xcodeproj/project.pbxproj
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
기대: plutil `OK`, `** BUILD SUCCEEDED **`. `IPHONEOS_DEPLOYMENT_TARGET = 17.0`이 더 이상 없어야 함(`grep -c 'TARGET = 17.0' ...` → 0).

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru.xcodeproj/project.pbxproj
git commit -m "build: 메인 앱 배포 타깃 iOS 26.0으로 상향"
```

---

## Task 2: 공용 Glass 디자인 시스템 (토큰/카드/버튼/배경)

**Files:**
- Create: `WooriHaru/Views/Components/Glass/GlassTokens.swift`
- Create: `WooriHaru/Views/Components/Glass/GlassCard.swift`
- Create: `WooriHaru/Views/Components/Glass/GlassButtonStyles.swift`
- Create: `WooriHaru/Views/Components/Glass/GlassBackground.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (4파일 등록 + Glass 그룹)

**Interfaces:**
- Produces (이후 태스크가 사용):
  - `enum GlassTokens` — `cardCornerRadius`, `cardPadding`, `cardSpacing: CGFloat`, `accentTint: Color`
  - `struct GlassCard<Content: View>: View` — `init(cornerRadius:padding:@ViewBuilder content:)`, 기본값 토큰
  - `View.appGlassProminentButton()`, `View.appGlassButton()`
  - `struct GlassBackground: View`, `View.glassScreenBackground()`

- [ ] **Step 1: GlassTokens.swift 작성**

```swift
import SwiftUI

/// 앱 공용 Liquid Glass 토큰.
enum GlassTokens {
    static let cardCornerRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 16
    /// 앱 액센트 계열 (glass prominent 틴트용).
    static let accentTint: Color = .blue500
}
```

- [ ] **Step 2: GlassCard.swift 작성**

```swift
import SwiftUI

/// 앱 공용 Liquid Glass 카드. 기존 흰 카드(RoundedRectangle.fill(.white).stroke) 대체용.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = GlassTokens.cardCornerRadius
    var padding: CGFloat = GlassTokens.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 3: GlassButtonStyles.swift 작성**

```swift
import SwiftUI

extension View {
    /// 주요 CTA: Liquid Glass prominent + 앱 액센트 틴트.
    func appGlassProminentButton() -> some View {
        buttonStyle(.glassProminent).tint(GlassTokens.accentTint)
    }

    /// 보조 액션: Liquid Glass.
    func appGlassButton() -> some View {
        buttonStyle(.glass)
    }
}
```

- [ ] **Step 4: GlassBackground.swift 작성**

```swift
import SwiftUI

/// 화면 배경 레이어. glass 요소가 비쳐 보이도록 은은한 그라데이션을 깐다.
struct GlassBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.slate50, Color.blue50],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension View {
    /// 화면 루트 배경으로 GlassBackground를 깐다.
    func glassScreenBackground() -> some View {
        background { GlassBackground() }
    }
}
```

- [ ] **Step 5: pbxproj에 4파일 + Glass 그룹 등록**

메인 타깃은 명시적 파일 참조 방식이다. 다음 4종을 모두 추가하고 `Glass` 그룹을 `Components` 그룹(`B40012`) 하위에 만든다. `GLS` 접두사 UUID 사용(미사용 확인됨).

(a) PBXBuildFile 섹션에 4줄:
```
		GLS10001 /* GlassTokens.swift in Sources */ = {isa = PBXBuildFile; fileRef = GLS20001 /* GlassTokens.swift */; };
		GLS10002 /* GlassCard.swift in Sources */ = {isa = PBXBuildFile; fileRef = GLS20002 /* GlassCard.swift */; };
		GLS10003 /* GlassButtonStyles.swift in Sources */ = {isa = PBXBuildFile; fileRef = GLS20003 /* GlassButtonStyles.swift */; };
		GLS10004 /* GlassBackground.swift in Sources */ = {isa = PBXBuildFile; fileRef = GLS20004 /* GlassBackground.swift */; };
```
(b) PBXFileReference 섹션에 4줄:
```
		GLS20001 /* GlassTokens.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassTokens.swift; sourceTree = "<group>"; };
		GLS20002 /* GlassCard.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassCard.swift; sourceTree = "<group>"; };
		GLS20003 /* GlassButtonStyles.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassButtonStyles.swift; sourceTree = "<group>"; };
		GLS20004 /* GlassBackground.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GlassBackground.swift; sourceTree = "<group>"; };
```
(c) 새 PBXGroup 정의(다른 그룹 정의들 근처에 추가):
```
		GLS40001 /* Glass */ = {
			isa = PBXGroup;
			children = (
				GLS20001 /* GlassTokens.swift */,
				GLS20002 /* GlassCard.swift */,
				GLS20003 /* GlassButtonStyles.swift */,
				GLS20004 /* GlassBackground.swift */,
			);
			path = Glass;
			sourceTree = "<group>";
		};
```
(d) `Components` 그룹(`B40012 /* Components */`)의 children 목록에 추가:
```
				GLS40001 /* Glass */,
```
(e) 메인 타깃 PBXSourcesBuildPhase(파일들이 `... in Sources */,`로 나열된 곳, ContentView/StatsView 등이 있는 phase)에 4줄:
```
				GLS10001 /* GlassTokens.swift in Sources */,
				GLS10002 /* GlassCard.swift in Sources */,
				GLS10003 /* GlassButtonStyles.swift in Sources */,
				GLS10004 /* GlassBackground.swift in Sources */,
```

- [ ] **Step 6: 검증**

```bash
plutil -lint WooriHaru.xcodeproj/project.pbxproj
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug clean build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
기대: plutil `OK`, `** BUILD SUCCEEDED **`. 이어서 4개 파일이 실제 컴파일됐는지 확인:
```bash
DERIVED=$(xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -showBuildSettings -destination 'generic/platform=iOS' 2>/dev/null | grep -m1 OBJROOT | awk '{print $3}')
find "$DERIVED" -path "*WooriHaru.build*" -name "WooriHaru.SwiftFileList" | head -1 | xargs grep -o "Glass[A-Za-z]*\.swift" | sort -u
```
기대: `GlassBackground.swift`, `GlassButtonStyles.swift`, `GlassCard.swift`, `GlassTokens.swift` 4개 모두 출력.

- [ ] **Step 7: 커밋**

```bash
git add WooriHaru/Views/Components/Glass WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: Liquid Glass 디자인 시스템(토큰/카드/버튼/배경) 추가"
```

---

## Task 3: 전역 크롬 — 사이드 드로어 glass화

**Files:**
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift`

**Interfaces:**
- Consumes: (없음 — 시스템 glass API 직접 사용)

- [ ] **Step 1: 드로어 패널 배경을 glass로 교체**

`SideDrawerView.swift`의 `drawerContent` 적용부에서:
```swift
            drawerContent
                .frame(width: Self.width)
                .background(.white)
                .offset(x: revealedWidth - Self.width)
```
의 `.background(.white)` 한 줄을 다음으로 교체:
```swift
                .glassEffect(.regular, in: Rectangle())
```
(나머지 `.frame`/`.offset`/오버레이/제스처는 유지.)

- [ ] **Step 2: 빌드 검증**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
기대: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Views/Components/SideDrawerView.swift
git commit -m "feat: 사이드 드로어 Liquid Glass 적용"
```

---

## Task 4: 파일럿 — LoginView (버튼/카드/배경)

**Files:**
- Modify: `WooriHaru/Views/Auth/LoginView.swift`

**Interfaces:**
- Consumes: `GlassCard`(여기선 직접 `glassEffect` 사용), `appGlassProminentButton()`, `GlassBackground`

- [ ] **Step 1: 배경 레이어 교체**

`body`의 `ZStack` 안 첫 요소:
```swift
            Color.slate50
                .ignoresSafeArea()
```
를 다음으로 교체:
```swift
            GlassBackground()
```

- [ ] **Step 2: 로그인 버튼을 glass prominent로**

로그인 `Button`의 label에서 수동 배경/클립 두 줄을 제거:
```swift
                        .background(Color.slate900)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
```
(이 두 줄 삭제). 그리고 `Button { login() } label: { ... }` 클로저 닫힌 직후, `.disabled(...)` 위에 다음을 추가:
```swift
                    .appGlassProminentButton()
```
(label의 `.foregroundStyle(.white)`, `.frame(maxWidth:.infinity)`, `.frame(height: 52)`는 유지.)

- [ ] **Step 3: 입력 폼 카드를 glass로**

폼 `VStack(spacing: 14) { ... }` 의 카드 스타일:
```swift
                .padding(22)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.slate200, lineWidth: 1)
                }
                .padding(.horizontal, 24)
```
에서 `.background(.white)` ~ `.overlay { ... }` 블록을 다음 한 줄로 교체(`.padding(22)`와 `.padding(.horizontal, 24)`는 유지):
```swift
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18))
```

- [ ] **Step 4: 빌드 검증**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
기대: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/Views/Auth/LoginView.swift
git commit -m "feat: LoginView Liquid Glass 파일럿 적용"
```

---

## Task 5: 파일럿 — StatsView (배경/카드 대표)

**Files:**
- Modify: `WooriHaru/Views/Stats/StatsView.swift`

**Interfaces:**
- Consumes: `GlassCard`, `glassScreenBackground()`

> 먼저 `StatsView.swift` 전체를 읽어 구조를 파악할 것. 아래는 적용 규칙과 수용 기준이며, 정확한 줄 위치는 파일을 읽고 맞춘다.

- [ ] **Step 1: 화면 배경 레이어 추가**

최상위 `ScrollView { ... }` 에 배경을 깐다. `ScrollView` 닫는 중괄호 뒤 모디파이어 체인(예: `.navigationTitle("통계")` 인근)에 다음을 추가:
```swift
        .glassScreenBackground()
```
(스크롤 콘텐츠가 배경 위에 떠 보이도록.) `ScrollView`가 불투명 배경을 강제하지 않는지 확인하고, 강제 흰 배경이 있으면 제거.

- [ ] **Step 2: 콘텐츠 블록을 GlassCard로 감싸기**

`ScrollView` 내부 최상위 `VStack(spacing: 16) { ... }`의 주요 콘텐츠 묶음(기간/필터 컨트롤 묶음, 통계 본문 묶음)을 `GlassCard { ... }`로 감싼다. 예시 패턴:
```swift
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        // 기존 콘텐츠 (기간 라벨/Picker/필터칩 등)
                    }
                }
```
기존에 `.background { RoundedRectangle(cornerRadius: 20).fill(.white)... }`로 흰 박스를 그리던 부분은 `GlassCard`로 대체(중복 배경 제거). 필터칩처럼 작은 토글 배경(`Color.blue50`/흰색)은 가독성 위해 그대로 둘 수 있음 — 큰 컨테이너만 glass로.

- [ ] **Step 3: 빌드 검증**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```
기대: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/Views/Stats/StatsView.swift
git commit -m "feat: StatsView Liquid Glass 파일럿 적용"
```

---

## Task 6: 육안 검증 (수동)

**Files:** 없음(수동).

- [ ] **Step 1: 시뮬레이터 실행 및 디자인 언어 확인**

iOS 26 시뮬레이터에서 앱 실행 → LoginView(버튼/카드/배경), 로그인 후 사이드 드로어(glass 패널), StatsView(배경+glass 카드) 확인.

- [ ] **Step 2: 가독성/대비 확인**

slate 텍스트·차트 색이 glass 위에서 충분히 읽히는지. 흐리면 배경 그라데이션 톤 또는 텍스트 대비 보정 필요(후속 메모).

- [ ] **Step 3: 라이트/다크 모드 + 접근성**

다크 모드 전환, 설정의 "투명도 줄이기(Reduce Transparency)" 켠 상태에서 fallback이 깨지지 않는지 확인.

- [ ] **Step 4: 레이아웃 회귀 확인**

`GlassEffectContainer`를 쓴 곳이 있으면 내부 스택 누락으로 겹치지 않는지 확인(이 Foundation에선 미사용이면 생략).

---

## Self-Review 결과

- **Spec 커버리지**: 배포 타깃 상향 → Task 1; 디자인 시스템(카드/버튼/배경/토큰) → Task 2; 전역 크롬(사이드 드로어) → Task 3; 파일럿(LoginView/StatsView) → Task 4·5; 육안 검증/리스크 → Task 6. 내비/툴바 자동 glass는 타깃 상향(Task 1)으로 확보, 강제 배경 제거는 파일럿에서 점검. SideDrawer는 spec의 대표 크롬으로 Task 3에 포함.
- **Placeholder 스캔**: 코드 스텝에 실제 코드 포함. StatsView(Task 5)는 복잡 뷰라 "읽고 맞춤" + 적용 규칙·수용 기준 명시(완전 축자 대신 컴포넌트 적용 지시).
- **타입 일관성**: `GlassTokens`/`GlassCard`/`appGlassProminentButton()`/`appGlassButton()`/`GlassBackground`/`glassScreenBackground()` 명칭이 Task 2 정의와 Task 3·4·5 사용에서 일치.
- **주의**: Glass API(`glassEffect(_:in:)`, `.buttonStyle(.glass/.glassProminent)`)는 iOS 26 SDK 기준. 시그니처 불일치 시 빌드에서 보정. pbxproj 등록(Task 2 Step 5)은 SwiftFileList로 실제 컴파일 확인 필수.
