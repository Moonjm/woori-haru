# 남은 영역 Glass 롤아웃 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아직 글래스가 적용되지 않은 나머지 영역(커플·검색·프로필·관리·카테고리·사용자관리)의 화면 배경·카드·버튼에 Foundation Liquid Glass를 적용해 롤아웃을 완주한다.

**Architecture:** 전부 기존 파일 리스타일(신규 파일/pbxproj 없음). 화면 루트는 `glassScreenBackground()`, 흰 카드 컨테이너는 `glassEffect(.regular, in:)`/`GlassCard`, 카드 없던 화면은 `GlassCard` 신규 도입. 모든 버튼은 글래스로: 채움형 CTA는 `appGlassProminentButton()`, 보조/텍스트 버튼은 `appGlassButton()`. 리스트 행·입력 필드·상태 칩 등 촘촘한 콘텐츠는 plain.

**Tech Stack:** SwiftUI, iOS 26 Liquid Glass.

## Global Constraints

- 최소 배포 타깃 iOS 26.0. 텍스트/마크 색은 기존 `Color+Extensions.swift` 팔레트 유지. glass는 재질 레이어.
- 테스트 타깃 없음 → 검증은 빌드 성공:
  `xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20` → `** BUILD SUCCEEDED **`.
- SourceKit/IDE 진단(“Cannot find … in scope” 등)은 cross-file 노이즈 → 무시. xcodebuild가 정답.
- 신규 파일 없음 → pbxproj 작업 없음.
- **모든 버튼 글래스화**: 채움형 주요 CTA → `appGlassProminentButton()`; 보조/텍스트 링크형 → `appGlassButton()`. solid·맨텍스트 버튼 없음. 텍스트 색(파괴=빨강/복사=파랑/취소=회색)은 label 안 `foregroundStyle`로 유지.
- **glass-on-glass 금지**: 글래스 카드 안의 입력칸·행은 plain 유지.
- **촘촘한 콘텐츠 유지(plain)**: 리스트 행, 입력 필드(흰+stroke), 상태 칩, 토글, 드래그 핸들.
- Foundation 컴포넌트(머지됨):
  - `View.glassScreenBackground()` — 화면 루트 배경(slate50→blue50 그라데이션).
  - `glassEffect(.regular, in: <Shape>)` — 흰 카드/패널 대체.
  - `GlassCard(cornerRadius:padding:alignment:content:)` — 흰 카드 래퍼(기본 cornerRadius 16, padding 16, alignment .leading).
  - `View.appGlassProminentButton()` — `.glassProminent` + `GlassTokens.accentTint`(blue500).
  - `View.appGlassButton()` — `.glass`.

---

## File Structure (전부 수정, 신규 없음)

- `WooriHaru/Views/Admin/AdminView.swift` — 관리 허브(네비 카드 2개).
- `WooriHaru/Views/Pair/PairView.swift` — 커플 메인(카드 신규 도입).
- `WooriHaru/Views/Pair/PairEventsView.swift` — 기념일 관리(폼 카드 신규 + List).
- `WooriHaru/Views/Search/SearchView.swift` — 검색(필터 패널 + 결과 카드).
- `WooriHaru/Views/Profile/ProfileView.swift` — 내 정보(폼 카드 신규).
- `WooriHaru/Views/Category/CategoriesView.swift` — 카테고리 관리(폼/목록 카드).
- `WooriHaru/Views/Admin/UserManagementView.swift` — 사용자 관리(폼/목록 카드).

각 Task는 한 파일을 수정하고 빌드 검증 후 커밋한다. 파일은 독립적이라 순서 무관하나 아래 순서로 진행한다(간단→복잡).

공통 빌드 명령(이하 “빌드 명령”):
```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

---

## Task 1: AdminView — 배경 + 네비 카드 2개

**Files:**
- Modify: `WooriHaru/Views/Admin/AdminView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`.
- Produces: 없음.

- [ ] **Step 1: 루트 배경 추가**

`body`의 최상위 `VStack` 수정자에서:
```swift
        .padding(.top, 8)
        .navigationTitle("관리")
```
를 다음으로 교체:
```swift
        .padding(.top, 8)
        .glassScreenBackground()
        .navigationTitle("관리")
```

- [ ] **Step 2: adminCard 배경을 글래스로**

`adminCard(...)`의 `label` 말미:
```swift
            .padding(16)
            .background(.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
```
를 다음으로 교체(그림자 제거, 글래스가 대체):
```swift
            .padding(16)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
```

> 아이콘 배경(`Color.slate100`)은 콘텐츠라 유지.

- [ ] **Step 3: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**
```bash
git add WooriHaru/Views/Admin/AdminView.swift
git commit -m "feat: AdminView Liquid Glass 적용 (배경·네비 카드)"
```

---

## Task 2: PairView — 배경 + 섹션 카드 신규 + 버튼

**Files:**
- Modify: `WooriHaru/Views/Pair/PairView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `GlassCard`, `appGlassProminentButton()`, `appGlassButton()`.
- Produces: 없음.

- [ ] **Step 1: 루트 배경 + 섹션을 GlassCard로 감싸기**

`body`의 분기부:
```swift
                if isLoading {
                    ProgressView()
                } else if pairStore.isPaired {
                    connectedSection
                } else if pairStore.isPending {
                    pendingSection
                } else {
                    disconnectedSection
                }
```
를 다음으로 교체(각 섹션을 가운데 정렬 GlassCard로):
```swift
                if isLoading {
                    ProgressView()
                } else if pairStore.isPaired {
                    GlassCard(alignment: .center) { connectedSection }
                } else if pairStore.isPending {
                    GlassCard(alignment: .center) { pendingSection }
                } else {
                    GlassCard(alignment: .center) { disconnectedSection }
                }
```
그리고 `ScrollView { ... }`의 수정자에 배경 추가 — 다음을:
```swift
        .navigationTitle("커플")
        .navigationBarTitleDisplayMode(.inline)
```
다음으로 교체:
```swift
        .glassScreenBackground()
        .navigationTitle("커플")
        .navigationBarTitleDisplayMode(.inline)
```

- [ ] **Step 2: "기념일 관리" 버튼 → glassProminent**

`connectedSection`의 버튼:
```swift
            Button {
                navPath.append(AppDestination.pairEvents)
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("기념일 관리")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue500)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
```
를 다음으로 교체:
```swift
            Button {
                navPath.append(AppDestination.pairEvents)
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                    Text("기념일 관리")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .appGlassProminentButton()
```

- [ ] **Step 3: "페어 해제" 텍스트 버튼 → glass 캡슐**

`connectedSection`의:
```swift
            Button {
                showUnpairConfirm = true
            } label: {
                Text("페어 해제")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
```
를 다음으로 교체(빨강 텍스트 유지 + 글래스 캡슐):
```swift
            Button {
                showUnpairConfirm = true
            } label: {
                Text("페어 해제")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
            .appGlassButton()
```

- [ ] **Step 4: "코드 복사" 텍스트 버튼 → glass 캡슐**

`pendingSection`의:
```swift
                Button {
                    UIPasteboard.general.string = code.uppercased()
                    errorMessage = nil
                    successMessage = "코드가 복사되었습니다."
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("코드 복사")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
```
를 다음으로 교체:
```swift
                Button {
                    UIPasteboard.general.string = code.uppercased()
                    errorMessage = nil
                    successMessage = "코드가 복사되었습니다."
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("코드 복사")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
                .appGlassButton()
```

- [ ] **Step 5: "초대 취소" 텍스트 버튼 → glass 캡슐**

`pendingSection`의:
```swift
            Button {
                Task { await unpair() }
            } label: {
                Text("초대 취소")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
```
를 다음으로 교체:
```swift
            Button {
                Task { await unpair() }
            } label: {
                Text("초대 취소")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
            .appGlassButton()
```

- [ ] **Step 6: "코드 생성하기" 버튼 → glassProminent**

`disconnectedSection`의:
```swift
                Button {
                    Task { await createInvite() }
                } label: {
                    Text("코드 생성하기")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
```
를 다음으로 교체:
```swift
                Button {
                    Task { await createInvite() }
                } label: {
                    Text("코드 생성하기")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .appGlassProminentButton()
```

- [ ] **Step 7: "수락" 버튼 → glassProminent**

`disconnectedSection`의:
```swift
                    Button {
                        Task { await acceptInvite() }
                    } label: {
                        Text("수락")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(inputCode.count == 6 ? Color.blue500 : Color.slate400)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(inputCode.count != 6)
```
를 다음으로 교체(채움 색은 glassProminent + disabled가 담당):
```swift
                    Button {
                        Task { await acceptInvite() }
                    } label: {
                        Text("수락")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                    }
                    .appGlassProminentButton()
                    .disabled(inputCode.count != 6)
```

> 코드 입력 `TextField`, 하트 아이콘, 메시지 텍스트는 유지.

- [ ] **Step 8: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 9: 커밋**
```bash
git add WooriHaru/Views/Pair/PairView.swift
git commit -m "feat: PairView Liquid Glass 적용 (배경·섹션 카드·버튼 글래스화)"
```

---

## Task 3: PairEventsView — 배경 + 폼 카드 신규 + 버튼 + List

**Files:**
- Modify: `WooriHaru/Views/Pair/PairEventsView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `GlassCard`, `appGlassProminentButton()`.
- Produces: 없음.

- [ ] **Step 1: 생성 폼을 GlassCard로 감싸기**

`body`의 시작 생성 폼:
```swift
        VStack(spacing: 0) {
            // 생성 폼
            VStack(spacing: 12) {
                Text("새 기념일")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
```
에서 폼 VStack을 GlassCard로 감싼다. 폼 VStack의 닫는 부분과 수정자:
```swift
            }
            .padding(16)
            .font(.subheadline)

            Divider()
```
를 다음으로 교체(`.padding(16)` 내부 패딩 제거 → GlassCard가 담당, 바깥 여백 16 부여, Divider 제거):
```swift
            }
            .font(.subheadline)
```
그리고 폼 VStack 시작 `VStack(spacing: 12) {` 앞에 `GlassCard {` 를 추가하고, 위에서 닫은 직후 GlassCard를 닫으며 외부 패딩을 준다. 최종 형태:
```swift
        VStack(spacing: 0) {
            // 생성 폼
            GlassCard {
                VStack(spacing: 12) {
                    Text("새 기념일")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        TextField("😀", text: $viewModel.newEmoji)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.newEmoji) { _, newValue in
                                if newValue.count > 1 { viewModel.newEmoji = String(newValue.prefix(1)) }
                            }

                        TextField("제목", text: $viewModel.newTitle)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: viewModel.newTitle) { _, newValue in
                                if newValue.count > 30 { viewModel.newTitle = String(newValue.prefix(30)) }
                            }
                    }

                    HStack {
                        DatePicker("날짜", selection: $viewModel.newDate, displayedComponents: .date)
                            .labelsHidden()

                        Toggle("매년 반복", isOn: $viewModel.newRecurring)
                            .font(.caption)
                    }

                    Button {
                        Task { await viewModel.createEvent() }
                    } label: {
                        Text("추가")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .appGlassProminentButton()
                }
                .font(.subheadline)
            }
            .padding(16)
```
(위 블록은 "추가" 버튼의 glassProminent 전환까지 포함한다 — 기존 버튼의 `.foregroundStyle(.white).background(Color.blue500).clipShape(...)` 제거.)

- [ ] **Step 2: 루트 배경 + List 배경 투명화**

`body` 말미 `List { ... }.listStyle(.plain)` 의 `.listStyle(.plain)` 다음 줄에 `.scrollContentBackground(.hidden)` 를 추가:
```swift
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
```
그리고 최상위 `VStack(spacing: 0)`의 수정자:
```swift
        .navigationTitle("기념일 관리")
        .navigationBarTitleDisplayMode(.inline)
```
를 다음으로 교체:
```swift
        .glassScreenBackground()
        .navigationTitle("기념일 관리")
        .navigationBarTitleDisplayMode(.inline)
```

> List 행 내용(이모지/제목/날짜/🔄), 입력칸, DatePicker, Toggle, 메시지 텍스트는 유지.

- [ ] **Step 3: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**
```bash
git add WooriHaru/Views/Pair/PairEventsView.swift
git commit -m "feat: PairEventsView Liquid Glass 적용 (배경·폼 카드·버튼·리스트 투명)"
```

---

## Task 4: SearchView — 배경 + 필터 패널

**Files:**
- Modify: `WooriHaru/Views/Search/SearchView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`.
- Produces: 없음.

- [ ] **Step 1: 필터 바를 글래스 패널로**

상단 필터 영역 VStack 말미:
```swift
            }
            .padding(16)
            .background(.white)

            Divider()
```
를 다음으로 교체(흰 배경 → 글래스 패널, 중복 Divider 제거):
```swift
            }
            .padding(16)
            .glassEffect(.regular, in: Rectangle())
```

- [ ] **Step 2: 루트 배경 추가**

최상위 `VStack(spacing: 0)`의 수정자:
```swift
        .contentShape(Rectangle())
        .onTapGesture { isKeywordFocused = false }
        .navigationTitle("검색")
```
를 다음으로 교체:
```swift
        .contentShape(Rectangle())
        .onTapGesture { isKeywordFocused = false }
        .glassScreenBackground()
        .navigationTitle("검색")
```

> `SearchResultCard`(흰+stroke, 다수)·피커/메뉴/키워드 입력칸은 콘텐츠라 유지. 파랑 CTA 없음.

- [ ] **Step 3: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**
```bash
git add WooriHaru/Views/Search/SearchView.swift
git commit -m "feat: SearchView Liquid Glass 적용 (배경·필터 패널)"
```

---

## Task 5: ProfileView — 배경 + 폼 카드 신규 + 저장 버튼

**Files:**
- Modify: `WooriHaru/Views/Profile/ProfileView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `GlassCard`, `appGlassProminentButton()`.
- Produces: 없음.

- [ ] **Step 1: 폼 전체를 GlassCard로 감싸기 + 루트 배경**

`body`의 `ScrollView { VStack(...) { ... }.padding(20) }` 구조를 GlassCard로 감싼다. 시작부:
```swift
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 아이디 (읽기전용)
```
를 다음으로 교체:
```swift
        ScrollView {
            GlassCard(alignment: .leading) {
                VStack(alignment: .leading, spacing: 24) {
                    // 아이디 (읽기전용)
```
그리고 VStack 닫는 부분과 `.padding(20)`:
```swift
            }
            .padding(20)
        }
        .navigationTitle("내 정보")
```
를 다음으로 교체(VStack을 닫고 GlassCard를 닫은 뒤 외부 패딩, 루트 배경 추가):
```swift
                }
            }
            .padding(20)
        }
        .glassScreenBackground()
        .navigationTitle("내 정보")
```

> 주의: GlassCard로 감싸면서 내부 블록 들여쓰기가 한 단계 깊어진다. 닫는 괄호 개수(VStack `}` + GlassCard `}`)를 정확히 맞춘다.

- [ ] **Step 2: "저장" 버튼 → glassProminent**

`body` 내 저장 버튼:
```swift
                Button {
                    Task { await save() }
                } label: {
                    Text("저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.slate700)
                        )
                }
                .disabled(isSaving)
                .opacity(isSaving ? 0.6 : 1)
```
를 다음으로 교체(slate700 채움 제거, glassProminent 적용):
```swift
                Button {
                    Task { await save() }
                } label: {
                    Text("저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .appGlassProminentButton()
                .disabled(isSaving)
                .opacity(isSaving ? 0.6 : 1)
```

> 입력칸(흰+stroke)·아이디 readonly(slate100)·성별 토글·DatePicker는 유지(콘텐츠).

- [ ] **Step 3: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: 커밋**
```bash
git add WooriHaru/Views/Profile/ProfileView.swift
git commit -m "feat: ProfileView Liquid Glass 적용 (배경·폼 카드·저장 버튼)"
```

---

## Task 6: CategoriesView — 배경 + 폼/목록 카드 + 버튼

**Files:**
- Modify: `WooriHaru/Views/Category/CategoriesView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`, `appGlassProminentButton()`, `appGlassButton()`.
- Produces: 없음.

- [ ] **Step 1: 루트 배경 교체**

`body`의:
```swift
        .background(Color.slate50)
        .navigationTitle("카테고리 관리")
```
를 다음으로 교체:
```swift
        .glassScreenBackground()
        .navigationTitle("카테고리 관리")
```

- [ ] **Step 2: 생성 폼 카드를 글래스로**

`createFormSection`의 폼 카드 말미:
```swift
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
```
를 다음으로 교체:
```swift
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
```

- [ ] **Step 3: "추가하기" 버튼 → glassProminent**

`createFormSection`의:
```swift
                    Button {
                        Task { await viewModel.createCategory() }
                    } label: {
                        Text("추가하기")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange300))
                    }
```
를 다음으로 교체(주황 채움 제거):
```swift
                    Button {
                        Task { await viewModel.createCategory() }
                    } label: {
                        Text("추가하기")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .appGlassProminentButton()
```

- [ ] **Step 4: 목록 컨테이너 배경을 글래스 패널로**

`categoryListSection` 말미:
```swift
        }
        .background(.white)
    }

    // MARK: - Category Row
```
를 다음으로 교체:
```swift
        }
        .glassEffect(.regular, in: Rectangle())
    }

    // MARK: - Category Row
```

- [ ] **Step 5: 편집 행 "저장" → glassProminent, "취소" → glass 캡슐**

`editRow(_:)`의 버튼 HStack:
```swift
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateCategory() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
```
를 다음으로 교체:
```swift
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateCategory() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .appGlassProminentButton()

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                    .appGlassButton()
            }
```

> 행(slate50), 입력칸(흰+stroke), ACTIVE/INACTIVE 칩, 드래그 핸들, Active/Inactive 토글 버튼은 유지(콘텐츠).

- [ ] **Step 6: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: 커밋**
```bash
git add WooriHaru/Views/Category/CategoriesView.swift
git commit -m "feat: CategoriesView Liquid Glass 적용 (배경·폼/목록 카드·버튼)"
```

---

## Task 7: UserManagementView — 배경 + 폼/목록 카드 + 버튼

**Files:**
- Modify: `WooriHaru/Views/Admin/UserManagementView.swift`

**Interfaces:**
- Consumes: `glassScreenBackground()`, `glassEffect(.regular, in:)`, `appGlassProminentButton()`, `appGlassButton()`.
- Produces: 없음.

- [ ] **Step 1: 루트 배경 교체**

`body`의:
```swift
        .background(Color.slate50)
        .navigationTitle("사용자 관리")
```
를 다음으로 교체:
```swift
        .glassScreenBackground()
        .navigationTitle("사용자 관리")
```

- [ ] **Step 2: "사용자 추가" 버튼 → glassProminent**

생성 폼의:
```swift
                    Button {
                        Task { await viewModel.createUser() }
                    } label: {
                        Text("사용자 추가")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.slate700)
                            )
                    }
```
를 다음으로 교체:
```swift
                    Button {
                        Task { await viewModel.createUser() }
                    } label: {
                        Text("사용자 추가")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .appGlassProminentButton()
```

- [ ] **Step 3: 생성 폼 카드 배경을 글래스로**

생성 폼 VStack 말미(첫 번째 흰 카드):
```swift
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)

                // Messages
```
를 다음으로 교체:
```swift
                }
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))

                // Messages
```

- [ ] **Step 4: 사용자 목록 카드 배경을 글래스로**

사용자 목록 VStack 말미(두 번째 흰 카드):
```swift
                }
                .padding(16)
                .background(.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
            }
            .padding(20)
```
를 다음으로 교체:
```swift
                }
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(20)
```

- [ ] **Step 5: 편집 행 "저장" → glassProminent, "취소" → glass 캡슐**

`editUserRow(_:)`의 버튼 HStack:
```swift
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateUser() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
```
를 다음으로 교체:
```swift
            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.updateUser() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
                .appGlassProminentButton()

                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                    .appGlassButton()
            }
```

> 행(slate50), 입력칸(흰+stroke), 권한 칩, 권한 메뉴(흰+stroke)는 유지(콘텐츠).

- [ ] **Step 6: 빌드 검증** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: 커밋**
```bash
git add WooriHaru/Views/Admin/UserManagementView.swift
git commit -m "feat: UserManagementView Liquid Glass 적용 (배경·폼/목록 카드·버튼)"
```

---

## Task 8: 최종 빌드 + 육안 검증

**Files:** 없음(검증 전용).

- [ ] **Step 1: 전체 클린 빌드** — 빌드 명령 → `** BUILD SUCCEEDED **`.

- [ ] **Step 2: 시뮬레이터 육안 체크리스트**

- **커플(PairView)**: 연결/대기/미연결 3상태 카드 글래스, 버튼 글래스(기념일 관리/코드 생성/수락 prominent, 해제·취소·복사 캡슐) 가독성·텍스트 색.
- **기념일(PairEventsView)**: 생성 폼 카드 글래스, "추가" prominent, List 행이 그라데이션 위에서 읽힘(배경 투명).
- **검색(SearchView)**: 상단 필터 패널 글래스, 결과 카드 가독성.
- **내 정보(ProfileView)**: 폼 카드 글래스, 입력칸 편집 대비, "저장" prominent.
- **카테고리(CategoriesView)**: 폼/목록 카드 글래스, "추가하기"·편집 저장 prominent, "취소" 캡슐, 행/칩 가독성.
- **관리(AdminView)**: 네비 카드 2개 글래스.
- **사용자 관리(UserManagementView)**: 폼/목록 카드 글래스, "사용자 추가"·편집 저장 prominent, "취소" 캡슐.
- 공통: 라이트/다크 모드, 설정 > 손쉬운 사용 > 투명도 줄이기 ON fallback.

- [ ] **Step 3: 리스크 재확인**

- 글래스 카드 안 입력칸(흰)·행(slate50)이 plain 유지되어 glass-on-glass 아님 확인.
- prominent 버튼이 글래스 카드 위에 올라간 구성(Profile/Category/User 폼)에서 대비 OK 확인. 약하면 후속 미세 조정(`appGlassProminentButton` → `appGlassButton` 또는 tint 조정).
- 카드 신규 도입 화면(Pair/Profile/PairEvents)의 간격이 어색하면 padding 미세 조정.

---

## 비범위

- 기능/로직 변경, 리스트 행·폼 입력 리디자인.
- 신규 파일/네비게이션 변경.
- Auth(이미 적용)·이미 적용된 영역 재작업.

---

## Self-Review (스펙 대비 점검)

- **범위(7파일)**: Task 1~7이 각 1파일 담당, Task 8 검증. ✅
- **카드 신규 도입(Pair/Profile/PairEvents)**: Task 2 Step1(Pair 섹션 GlassCard), Task 3 Step1(PairEvents 폼 GlassCard), Task 5 Step1(Profile 폼 GlassCard). ✅
- **모든 버튼 글래스**: 채움형→`appGlassProminentButton`(기념일관리/코드생성/수락/추가/추가하기/저장/사용자추가/편집저장), 보조→`appGlassButton`(해제/복사/초대취소/편집취소). ✅
- **촘촘한 콘텐츠 plain**: 각 Task 인용 아래 “유지” 주석으로 리스트 행/입력칸/칩 명시. ✅
- **glass-on-glass 금지**: 카드 안 입력칸·행 plain(Task 5/6/7 주석). ✅
- **List 배경**: PairEventsView `scrollContentBackground(.hidden)`(Task 3 Step2). ✅
- **검증=빌드+육안**: 각 Task 빌드 Step + Task 8 체크리스트(라이트/다크/투명도 줄이기). ✅
- 라인 번호는 스냅샷 — 실행 시 파일을 먼저 읽고 해당 수정자/블록을 매칭해 교체할 것.
