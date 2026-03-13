# 공유 도메인 Store Phase 1 설계

## 배경

여러 ViewModel에서 동일한 API를 각각 호출하고 독립적으로 상태를 관리하여, 데이터 불일치와 불필요한 중복 호출이 발생하고 있다.

## 목표

PairStore, CategoryStore, SubjectStore, PauseTypeStore 4개를 도입하여 중복 상태를 단일 Store로 통합한다.

## 설계 원칙

- Store는 **공유 데이터 + API 호출**만 담당
- **UI 상태**(폼 입력, 로딩, 에러 메시지 등)는 각 ViewModel/View에 남김
- 모든 Store는 `@MainActor @Observable` 클래스
- `@Environment`로 앱 전체에 주입

---

## Store 설계

### 1. PairStore

**현재 중복:** PairViewModel, CalendarViewModel, RecordViewModel, StatsViewModel에서 각각 `pairService.getStatus()` 호출.

```swift
@MainActor @Observable
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

**변경되는 ViewModel:**
- PairViewModel → PairStore의 데이터 사용. UI 상태(inviteCode, inputCode, messages)만 유지.
- CalendarViewModel → `pairInfo`, `isPaired` 프로퍼티 제거, PairStore 참조.
- RecordViewModel → `isPaired`, `partnerName` 프로퍼티 제거, PairStore 참조.
- StatsViewModel → `isPaired` 프로퍼티 제거, PairStore 참조. `pairService.getStatus()` 호출 제거.

### 2. CategoryStore

**현재 중복:** RecordViewModel, SearchViewModel, CategoriesViewModel에서 각각 `categoryService.fetchCategories()` 호출.

```swift
@MainActor @Observable
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

**변경되는 ViewModel:**
- CategoriesViewModel → CategoryStore의 CRUD 사용. 폼 상태(newEmoji 등)만 유지.
- RecordViewModel → `categories` 프로퍼티 제거, `categoryService` 제거. CategoryStore.activeCategories 참조.
- SearchViewModel → `categories` 프로퍼티 제거, `categoryService` 제거. CategoryStore.categories 참조.

### 3. SubjectStore

**현재 중복:** StudyTimerViewModel에서만 CRUD하지만, subjects 데이터를 공유 가능하게 분리.

```swift
@MainActor @Observable
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

**변경되는 ViewModel:**
- StudyTimerViewModel → `subjects` 프로퍼티 및 subject CRUD 메서드 제거. SubjectStore 참조.

### 4. PauseTypeStore

**현재 중복:** StudyTimerViewModel, StudyRecordViewModel에서 각각 `fetchPauseTypes()` 호출.

```swift
@MainActor @Observable
final class PauseTypeStore {
    private(set) var pauseTypes: [PauseType] = []
    private let service = StudyService()

    func load() async throws {
        guard pauseTypes.isEmpty else { return }
        pauseTypes = try await service.fetchPauseTypes()
    }
}
```

**변경되는 ViewModel:**
- StudyTimerViewModel → `pauseTypes` 프로퍼티 제거, PauseTypeStore 참조.
- StudyRecordViewModel → `pauseTypes` 프로퍼티 제거, PauseTypeStore 참조.

---

## 주입 (WooriHaruApp)

```swift
@State private var pairStore = PairStore()
@State private var categoryStore = CategoryStore()
@State private var subjectStore = SubjectStore()
@State private var pauseTypeStore = PauseTypeStore()

// .environment(pairStore)
// .environment(categoryStore)
// .environment(subjectStore)
// .environment(pauseTypeStore)
```

---

## 에러 처리 패턴

Store 메서드는 `throws`로 에러를 던지고, 호출하는 ViewModel/View에서 catch하여 UI 에러 메시지를 관리한다.

```swift
// ViewModel에서
do {
    try await pairStore.loadStatus()
} catch {
    errorMessage = "페어 상태를 불러오지 못했습니다."
}
```

---

## 스코프 외 (Phase 2)

- RecordStore (월별 lazy loading, 날짜 캐싱 포함 — 복잡도 높음)
- OvereatStore, HolidayStore, PairEventStore (RecordStore와 함께 진행)
