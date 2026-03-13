# 공유 도메인 Store Phase 1 구현 계획

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PairStore, CategoryStore, SubjectStore, PauseTypeStore 4개를 도입하여 ViewModel 간 중복 상태를 제거한다.

**Architecture:** 각 Store는 `@MainActor @Observable` 클래스로, 공유 데이터와 API 호출을 담당한다. `@Environment`로 앱 전체에 주입하고, 기존 ViewModel은 Store를 참조하도록 수정한다. UI 상태(폼, 에러 메시지)는 ViewModel/View에 남긴다.

**Tech Stack:** SwiftUI, Observation framework, @Environment DI

**Spec:** `docs/superpowers/specs/2026-03-13-shared-store-phase1-design.md`

---

## Chunk 1: Store 생성 및 주입

### Task 1: PairStore 생성

**Files:**
- Create: `WooriHaru/Stores/PairStore.swift`
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (Xcode 자동)

- [ ] **Step 1: PairStore 파일 생성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class PairStore {
    private(set) var pairInfo: PairInfo?
    private let service = PairService()

    var isPaired: Bool { pairInfo?.status == .connected }
    var isPending: Bool { pairInfo?.status == .pending }
    var partnerName: String { pairInfo?.partnerName ?? "파트너" }

    func loadStatus() async throws {
        pairInfo = try await service.getStatus()
    }

    func createInvite() async throws -> String {
        let response = try await service.createInvite()
        try await loadStatus()
        return response.inviteCode
    }

    func acceptInvite(code: String) async throws {
        pairInfo = try await service.acceptInvite(code: code)
    }

    func unpair() async throws {
        try await service.unpair()
        pairInfo = nil
    }
}
```

- [ ] **Step 2: Xcode 프로젝트에 파일 추가**

Stores 디렉토리 생성 후 Xcode 프로젝트에 등록.

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/Stores/PairStore.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: PairStore 생성 — 페어 상태 공유 Store"
```

### Task 2: CategoryStore 생성

**Files:**
- Create: `WooriHaru/Stores/CategoryStore.swift`

- [ ] **Step 1: CategoryStore 파일 생성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class CategoryStore {
    private(set) var categories: [Category] = []
    private let service = CategoryService()

    var activeCategories: [Category] { categories.filter(\.isActive) }

    func load() async throws {
        categories = try await service.fetchCategories()
        categories.sort { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
    }

    func create(_ request: CategoryRequest) async throws {
        try await service.createCategory(request)
        try await load()
    }

    func update(id: Int, _ request: CategoryRequest) async throws {
        try await service.updateCategory(id: id, request)
        try await load()
    }

    func delete(id: Int) async throws {
        try await service.deleteCategory(id: id)
        try await load()
    }

    func reorder(targetId: Int, beforeId: Int?) async throws {
        try await service.reorderCategory(ReorderCategoryRequest(targetId: targetId, beforeId: beforeId))
    }

    func move(from source: IndexSet, to destination: Int) {
        categories.move(fromOffsets: source, toOffset: destination)
    }
}
```

- [ ] **Step 2: 커밋**

```bash
git add WooriHaru/Stores/CategoryStore.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: CategoryStore 생성 — 카테고리 공유 Store"
```

### Task 3: SubjectStore 생성

**Files:**
- Create: `WooriHaru/Stores/SubjectStore.swift`

- [ ] **Step 1: SubjectStore 파일 생성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SubjectStore {
    private(set) var subjects: [StudySubject] = []
    private let service = StudyService()

    func load() async throws {
        subjects = try await service.fetchSubjects()
    }

    func create(name: String) async throws {
        _ = try await service.createSubject(name: name)
        try await load()
    }

    func update(id: Int, name: String) async throws {
        try await service.updateSubject(id: id, name: name)
        try await load()
    }

    func delete(id: Int) async throws {
        try await service.deleteSubject(id: id)
        try await load()
    }
}
```

- [ ] **Step 2: 커밋**

```bash
git add WooriHaru/Stores/SubjectStore.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: SubjectStore 생성 — 과목 공유 Store"
```

### Task 4: PauseTypeStore 생성

**Files:**
- Create: `WooriHaru/Stores/PauseTypeStore.swift`

- [ ] **Step 1: PauseTypeStore 파일 생성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class PauseTypeStore {
    private(set) var pauseTypes: [PauseType] = []
    private let service = StudyService()

    func load() async throws {
        guard pauseTypes.isEmpty else { return }
        pauseTypes = try await service.fetchPauseTypes()
    }
}
```

- [ ] **Step 2: 커밋**

```bash
git add WooriHaru/Stores/PauseTypeStore.swift WooriHaru.xcodeproj/project.pbxproj
git commit -m "feat: PauseTypeStore 생성 — 일시정지 타입 공유 Store"
```

### Task 5: WooriHaruApp에 Store 주입

**Files:**
- Modify: `WooriHaru/WooriHaruApp.swift`

- [ ] **Step 1: 4개 Store @State 선언 및 .environment() 주입 추가**

```swift
// 기존 @State 아래에 추가
@State private var pairStore = PairStore()
@State private var categoryStore = CategoryStore()
@State private var subjectStore = SubjectStore()
@State private var pauseTypeStore = PauseTypeStore()

// Group 아래 기존 .environment() 뒤에 추가
.environment(pairStore)
.environment(categoryStore)
.environment(subjectStore)
.environment(pauseTypeStore)
```

- [ ] **Step 2: 빌드 확인**

Xcode에서 빌드하여 Store 주입이 정상 동작하는지 확인.

- [ ] **Step 3: 커밋**

```bash
git add WooriHaru/WooriHaruApp.swift
git commit -m "feat: WooriHaruApp에 4개 공유 Store Environment 주입"
```

---

## Chunk 2: PairStore 적용 — ViewModel 수정

### Task 6: PairViewModel → PairStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/PairViewModel.swift`
- Modify: `WooriHaru/Views/Pair/PairView.swift`

- [ ] **Step 1: PairViewModel에서 데이터/API를 PairStore로 위임**

PairViewModel을 수정하여:
- `pairInfo` 프로퍼티 제거, `pairService` 제거
- `isPaired`, `isPending` computed 제거
- PairStore를 생성자 파라미터로 받음
- UI 상태(inviteCode, inputCode, messages)만 유지
- 각 액션 메서드에서 `pairStore`의 메서드 호출, catch에서 에러메시지 설정

```swift
@MainActor
@Observable
final class PairViewModel {
    var inviteCode: String?
    var inputCode: String = ""
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    private let pairStore: PairStore

    init(pairStore: PairStore) {
        self.pairStore = pairStore
    }

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            try await pairStore.loadStatus()
        } catch {
            errorMessage = "페어 상태를 불러오지 못했습니다."
        }
    }

    func createInvite() async {
        errorMessage = nil
        do {
            inviteCode = try await pairStore.createInvite()
        } catch {
            errorMessage = "초대 코드 생성에 실패했습니다."
        }
    }

    func acceptInvite() async {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        errorMessage = nil
        do {
            try await pairStore.acceptInvite(code: code)
            inputCode = ""
            inviteCode = nil
            successMessage = "페어링이 완료되었습니다!"
        } catch {
            errorMessage = "초대 코드가 올바르지 않습니다."
        }
    }

    func unpair() async {
        errorMessage = nil
        do {
            try await pairStore.unpair()
            inviteCode = nil
            successMessage = "페어가 해제되었습니다."
        } catch {
            errorMessage = "페어 해제에 실패했습니다."
        }
    }

    func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
```

- [ ] **Step 2: PairView에서 PairStore를 @Environment로 받아 PairViewModel에 전달**

PairView 수정:
- `@Environment(PairStore.self) private var pairStore` 추가
- `@State private var viewModel: PairViewModel?` 로 변경 (optional)
- `.task`에서 `viewModel = PairViewModel(pairStore: pairStore)` 초기화
- `pairStore.isPaired`, `pairStore.isPending`, `pairStore.pairInfo` 등은 pairStore에서 직접 참조
- UI 상태(inviteCode, inputCode, messages)는 viewModel에서 참조

- [ ] **Step 3: 빌드 확인**

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/ViewModels/PairViewModel.swift WooriHaru/Views/Pair/PairView.swift
git commit -m "refactor: PairViewModel이 PairStore 사용하도록 수정"
```

### Task 7: CalendarViewModel → PairStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/CalendarViewModel.swift`
- Modify: `WooriHaru/Views/Calendar/CalendarView.swift`

- [ ] **Step 1: CalendarViewModel에서 pairInfo/isPaired 관련 프로퍼티 및 로직 제거**

CalendarViewModel 수정:
- `pairInfo: PairInfo?` 프로퍼티 제거
- `isPaired: Bool` 프로퍼티 제거
- `pairService` 인스턴스 제거 (pairService의 다른 용도 있으면 확인 필요 — fetchPartnerRecords 등은 남길 수 있음)
- `initialLoad()`에서 `pairService.getStatus()` 호출 제거
- `isPaired` 참조하는 곳에서 외부에서 주입받도록 변경

PairStore를 CalendarViewModel 생성자로 받거나, CalendarView에서 직접 `pairStore.isPaired` 참조.

**방안:** CalendarViewModel이 PairStore를 init 파라미터로 받아서 `pairStore.isPaired`를 직접 참조하는 방식. CalendarViewModel 내부에서 partner records 로드 시 `pairStore.isPaired` 체크.

- [ ] **Step 2: CalendarView에서 RecordVM에 isPaired/partnerName 수동 전달 제거**

CalendarView 수정:
- `@Environment(PairStore.self) private var pairStore` 추가
- CalendarViewModel 초기화 시 pairStore 전달
- RecordVM에 isPaired/partnerName 전달하는 코드 제거 (RecordVM이 PairStore 직접 참조)

```swift
// 제거할 코드:
// recordVM.isPaired = calendarVM.isPaired
// recordVM.partnerName = calendarVM.pairInfo?.partnerName ?? "파트너"
```

- [ ] **Step 3: 빌드 확인**

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/ViewModels/CalendarViewModel.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "refactor: CalendarViewModel이 PairStore 사용하도록 수정"
```

### Task 8: RecordViewModel → PairStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/RecordViewModel.swift`

- [ ] **Step 1: RecordViewModel에서 isPaired/partnerName 프로퍼티 제거, PairStore 참조**

RecordViewModel 수정:
- `isPaired: Bool` 프로퍼티 제거
- `partnerName: String` 프로퍼티 제거
- `pairService` 인스턴스 제거 (partnerRecords 로드는 PairService 직접 사용 유지하거나 PairStore에 위임)
- PairStore를 init 파라미터로 받음
- `loadData()`에서 `pairStore.isPaired` 체크하여 파트너 기록 로드
- 파트너 기록 로드에 필요한 `pairService.fetchPartnerRecords()` → PairStore에는 없으므로 PairService는 RecordViewModel에 유지

```swift
@MainActor
@Observable
final class RecordViewModel {
    // isPaired, partnerName 제거
    // pairService 유지 (fetchPartnerRecords용)

    private let pairStore: PairStore
    private let pairService = PairService()

    init(pairStore: PairStore) {
        self.pairStore = pairStore
    }

    func loadData() async {
        // ...기존 로직...
        if pairStore.isPaired {
            // fetchPartnerRecords
        }
    }
}
```

- [ ] **Step 2: CalendarView에서 RecordViewModel 초기화 시 pairStore 전달**

- [ ] **Step 3: RecordView(시트)에서 partnerName 참조를 pairStore.partnerName으로 변경**

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/RecordViewModel.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "refactor: RecordViewModel이 PairStore 사용하도록 수정"
```

### Task 9: StatsViewModel → PairStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/StatsViewModel.swift`
- Modify: `WooriHaru/Views/Stats/StatsView.swift`

- [ ] **Step 1: StatsViewModel에서 isPaired 프로퍼티 제거, PairStore 참조**

StatsViewModel 수정:
- `isPaired: Bool` 프로퍼티 제거
- `pairService` 중 `getStatus()` 호출 제거 (fetchPartnerRecords는 유지)
- PairStore를 init 파라미터로 받음
- `loadStats()`에서 `pairStore.isPaired` 체크

```swift
init(pairStore: PairStore) {
    self.pairStore = pairStore
}

func loadStats() async {
    // pairService.getStatus() 호출 제거
    // pairStore.isPaired로 대체
    if pairStore.isPaired {
        partnerRecords = (try? await pairService.fetchPartnerRecords(...)) ?? []
    }
}
```

- [ ] **Step 2: StatsView에서 PairStore @Environment 받아 StatsViewModel에 전달**

- [ ] **Step 3: StatsView에서 `viewModel.isPaired` → `pairStore.isPaired` 로 변경**

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/StatsViewModel.swift WooriHaru/Views/Stats/StatsView.swift
git commit -m "refactor: StatsViewModel이 PairStore 사용하도록 수정"
```

---

## Chunk 3: CategoryStore, SubjectStore, PauseTypeStore 적용

### Task 10: CategoriesViewModel → CategoryStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/CategoriesViewModel.swift`
- Modify: `WooriHaru/Views/Category/CategoriesView.swift`

- [ ] **Step 1: CategoriesViewModel에서 categories 데이터/CRUD를 CategoryStore로 위임**

CategoriesViewModel 수정:
- `categories: [Category]` 프로퍼티 제거
- `categoryService` 제거
- CategoryStore를 init 파라미터로 받음
- `loadCategories()` → `categoryStore.load()` 위임
- CRUD 메서드에서 `categoryStore.create/update/delete()` 호출
- 폼 상태(newEmoji, editingId 등), 에러/성공 메시지만 유지
- `moveCategory()`, `syncCategoryOrder()` → `categoryStore.move()`, `categoryStore.reorder()` 사용

- [ ] **Step 2: CategoriesView에서 CategoryStore @Environment 받아 ViewModel에 전달**

- [ ] **Step 3: CategoriesView에서 `viewModel.categories` → `categoryStore.categories` 참조**

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/CategoriesViewModel.swift WooriHaru/Views/Category/CategoriesView.swift
git commit -m "refactor: CategoriesViewModel이 CategoryStore 사용하도록 수정"
```

### Task 11: RecordViewModel → CategoryStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/RecordViewModel.swift`

- [ ] **Step 1: RecordViewModel에서 categories/categoryService 제거, CategoryStore 참조**

RecordViewModel 수정:
- `categories: [Category]` 프로퍼티 제거
- `categoryService` 제거
- CategoryStore를 init 파라미터로 추가 (PairStore와 함께)
- `loadData()`에서 `categoryService.fetchCategories(active: true)` 제거
- View에서 카테고리 목록은 `categoryStore.activeCategories` 참조

```swift
init(pairStore: PairStore, categoryStore: CategoryStore) {
    self.pairStore = pairStore
    self.categoryStore = categoryStore
}
```

- [ ] **Step 2: CalendarView에서 RecordViewModel 초기화 시 categoryStore도 전달**

- [ ] **Step 3: RecordView(시트)에서 카테고리 목록 참조를 categoryStore.activeCategories로 변경**

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/RecordViewModel.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "refactor: RecordViewModel이 CategoryStore 사용하도록 수정"
```

### Task 12: SearchViewModel → CategoryStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/SearchViewModel.swift`
- Modify: `WooriHaru/Views/Search/SearchView.swift`

- [ ] **Step 1: SearchViewModel에서 categories/categoryService 제거, CategoryStore 참조**

SearchViewModel 수정:
- `categories: [Category]` 프로퍼티 제거
- `categoryService` 제거
- CategoryStore를 init 파라미터로 받음
- `loadInitial()`에서 `categoryService.fetchCategories()` 제거 (Store가 이미 로드됨)

- [ ] **Step 2: SearchView에서 CategoryStore @Environment 받아 ViewModel에 전달**

- [ ] **Step 3: SearchView에서 카테고리 목록 참조를 categoryStore.categories로 변경**

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/SearchViewModel.swift WooriHaru/Views/Search/SearchView.swift
git commit -m "refactor: SearchViewModel이 CategoryStore 사용하도록 수정"
```

### Task 13: StudyTimerViewModel → SubjectStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/StudyTimerViewModel.swift`
- Modify: `WooriHaru/Views/Study/StudyTimerView.swift`

- [ ] **Step 1: StudyTimerViewModel에서 subjects/subject CRUD 제거, SubjectStore 참조**

StudyTimerViewModel 수정:
- `subjects: [StudySubject]` 프로퍼티 제거
- `loadSubjects()`, `addSubject()`, `updateSubject()`, `deleteSubject()` 제거
- `showAddSubject`, `newSubjectName`, `editingSubject`, `editSubjectName` 폼 상태 → View로 이동하거나 ViewModel에 유지
- SubjectStore를 외부에서 주입 (이미 @Environment인 StudyTimerVM이므로, SubjectStore도 @Environment로 View에서 직접 접근)

**주의:** StudyTimerViewModel은 이미 `@Environment`로 주입되므로, init 파라미터가 아닌 View에서 SubjectStore를 직접 참조하는 방식이 더 자연스러움.

- [ ] **Step 2: StudyTimerView에서 SubjectStore @Environment 추가**

```swift
@Environment(SubjectStore.self) private var subjectStore
```

- subjects 목록, CRUD 호출을 subjectStore로 변경.

- [ ] **Step 3: 빌드 확인**

- [ ] **Step 4: 커밋**

```bash
git add WooriHaru/ViewModels/StudyTimerViewModel.swift WooriHaru/Views/Study/StudyTimerView.swift
git commit -m "refactor: subjects를 SubjectStore로 분리"
```

### Task 14: StudyTimerViewModel + StudyRecordViewModel → PauseTypeStore 사용

**Files:**
- Modify: `WooriHaru/ViewModels/StudyTimerViewModel.swift`
- Modify: `WooriHaru/ViewModels/StudyRecordViewModel.swift`
- Modify: `WooriHaru/Views/Study/StudyTimerView.swift`
- Modify: `WooriHaru/Views/Study/StudyRecordView.swift`

- [ ] **Step 1: StudyTimerViewModel에서 pauseTypes 프로퍼티 및 loadPauseTypes() 제거**

- View에서 PauseTypeStore를 @Environment로 참조.
- `pauseTypes` 목록은 `pauseTypeStore.pauseTypes`로 대체.

- [ ] **Step 2: StudyRecordViewModel에서 pauseTypes 프로퍼티 제거**

- `loadMonth()`에서 `service.fetchPauseTypes()` 호출 제거.
- `pauseTypeLabel()` 메서드에서 PauseTypeStore를 사용하도록 변경하거나, View에서 직접 처리.

- [ ] **Step 3: StudyTimerView, StudyRecordView에서 PauseTypeStore @Environment 추가**

```swift
@Environment(PauseTypeStore.self) private var pauseTypeStore
```

- [ ] **Step 4: 빌드 확인**

- [ ] **Step 5: 커밋**

```bash
git add WooriHaru/ViewModels/StudyTimerViewModel.swift WooriHaru/ViewModels/StudyRecordViewModel.swift \
      WooriHaru/Views/Study/StudyTimerView.swift WooriHaru/Views/Study/StudyRecordView.swift
git commit -m "refactor: pauseTypes를 PauseTypeStore로 분리"
```

---

## Chunk 4: 정리 및 초기 로딩

### Task 15: Store 초기 로딩 시점 설정

**Files:**
- Modify: `WooriHaru/WooriHaruApp.swift` 또는 `ContentView.swift`

- [ ] **Step 1: 앱 시작(로그인 후) 시 Store 데이터 초기 로딩**

로그인 성공 후 ContentView가 나타날 때 Store들의 초기 데이터를 로드.

```swift
ContentView()
    .task {
        try? await pairStore.loadStatus()
        try? await categoryStore.load()
        try? await subjectStore.load()
        try? await pauseTypeStore.load()
    }
```

또는 ContentView 내부 `.task`에서 병렬 로딩:

```swift
.task {
    async let pair: () = try? pairStore.loadStatus()
    async let cat: () = try? categoryStore.load()
    async let sub: () = try? subjectStore.load()
    async let pause: () = try? pauseTypeStore.load()
    _ = await (pair, cat, sub, pause)
}
```

- [ ] **Step 2: 기존 ViewModel의 중복 초기 로딩 제거**

각 View의 `.task`에서 이미 Store가 로드한 데이터를 다시 로드하는 호출 제거 (예: `loadCategories()`, `loadStatus()` 등).

- [ ] **Step 3: 빌드 및 전체 흐름 테스트**

앱 시작 → 로그인 → 각 화면에서 데이터가 정상 표시되는지 확인.

- [ ] **Step 4: 커밋**

```bash
git add -A
git commit -m "refactor: Store 초기 로딩 설정 및 중복 로딩 제거"
```

### Task 16: 불필요해진 코드 정리

**Files:**
- 각 ViewModel에서 사용하지 않는 import, 빈 메서드 등 정리

- [ ] **Step 1: 사용하지 않는 Service import 제거**

- RecordViewModel에서 `categoryService` import 제거
- SearchViewModel에서 `categoryService` import 제거
- StatsViewModel에서 `pairService.getStatus()` 관련 코드 제거

- [ ] **Step 2: 빌드 확인**

- [ ] **Step 3: 커밋**

```bash
git add -A
git commit -m "chore: Store 리팩토링 후 불필요 코드 정리"
```
