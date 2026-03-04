# Phase 3: 통계 & 검색 & 카테고리 관리 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 웹 앱의 통계/검색/카테고리 관리 3개 화면을 iOS로 구현하고, 네비게이션을 연결한다.

**Architecture:** 기존 Phase 2 패턴(MVVM + @Observable + async/await) 동일. 서비스 레이어(RecordService, CategoryService, PairService) 재사용. SideDrawerView에 enum 기반 네비게이션 추가.

**Tech Stack:** SwiftUI (iOS 17+), @Observable, async/await, GeometryReader(차트), List+onMove(드래그 정렬)

---

### Task 1: 네비게이션 구조 변경 (ContentView + SideDrawer)

**Files:**
- Modify: `WooriHaru/ContentView.swift`
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift`
- Modify: `WooriHaru/Views/Calendar/CalendarView.swift`
- Modify: `WooriHaru/Views/Calendar/CalendarHeaderView.swift`

**목적:** 사이드 드로어에서 통계/검색/카테고리 화면으로 이동할 수 있도록 네비게이션 연결.

**Step 1: ContentView에 NavigationStack + navigationDestination 추가**

```swift
// WooriHaru/ContentView.swift
import SwiftUI

enum AppDestination: Hashable {
    case stats
    case search
    case categories
}

struct ContentView: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            CalendarView(navPath: $path)
                .navigationDestination(for: AppDestination.self) { dest in
                    switch dest {
                    case .stats: StatsView()
                    case .search: SearchView()
                    case .categories: CategoriesView()
                    }
                }
        }
    }
}
```

**Step 2: SideDrawerView에 navPath 바인딩 + 메뉴 동작 연결**

```swift
// SideDrawerView.swift - 변경사항
struct SideDrawerView: View {
    @Binding var isOpen: Bool
    @Binding var navPath: NavigationPath
    @Environment(AuthViewModel.self) private var authVM

    // ... 기존 body 유지, 메뉴 항목 action만 변경:
    drawerItem(icon: "chart.bar", label: "통계") {
        isOpen = false
        navPath.append(AppDestination.stats)
    }
    drawerItem(icon: "magnifyingglass", label: "검색") {
        isOpen = false
        navPath.append(AppDestination.search)
    }
    drawerItem(icon: "folder", label: "카테고리 관리") {
        isOpen = false
        navPath.append(AppDestination.categories)
    }
    // "커플", "내 정보"는 Phase 4, 5에서 구현 - 현재는 동작 없음
```

**Step 3: CalendarView에 navPath 전달 + 검색 아이콘 연결**

CalendarView의 `@State private var calendarVM` 등은 그대로 유지. `navPath` 바인딩만 추가.

```swift
// CalendarView.swift - 시그니처 변경
struct CalendarView: View {
    @Binding var navPath: NavigationPath
    // ... 기존 @State 유지

    // SideDrawerView 호출 변경
    SideDrawerView(isOpen: $calendarVM.isDrawerOpen, navPath: $navPath)

    // CalendarHeaderView 검색 아이콘 변경
    CalendarHeaderView(
        monthLabel: calendarVM.currentMonthLabel,
        onMenuTap: { withAnimation { calendarVM.isDrawerOpen = true } },
        onMonthTap: { showPicker.toggle() },
        onSearchTap: { navPath.append(AppDestination.search) }
    )
```

**Step 4: 임시 Placeholder 뷰 생성 (빌드 확인용)**

통계/검색/카테고리 뷰가 아직 없으므로 빈 placeholder를 만든다:

```swift
// 각 파일에 임시로:
struct StatsView: View {
    var body: some View { Text("통계").navigationTitle("통계") }
}
struct SearchView: View {
    var body: some View { Text("검색").navigationTitle("검색") }
}
struct CategoriesView: View {
    var body: some View { Text("카테고리 관리").navigationTitle("카테고리 관리") }
}
```

**Step 5: 빌드 확인 후 커밋**

```bash
git add -A
git commit -m "feat: 네비게이션 구조 변경 (사이드 드로어 → 통계/검색/카테고리)"
```

---

### Task 2: StatsViewModel 구현

**Files:**
- Create: `WooriHaru/ViewModels/StatsViewModel.swift`

**목적:** 통계 데이터 fetch, 필터링, 카테고리별 집계 로직.

**Step 1: StatsViewModel 작성**

```swift
// WooriHaru/ViewModels/StatsViewModel.swift
import Foundation
import Observation

struct CategoryStat: Identifiable {
    let id: Int
    let emoji: String
    let name: String
    let count: Int
    let ratio: Double  // 0.0 ~ 1.0
}

enum RecordFilter: String, CaseIterable {
    case all = "전체"
    case together = "같이"
    case solo = "혼자"
}

@MainActor
@Observable
final class StatsViewModel {
    // MARK: - State

    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = Calendar.current.component(.month, from: Date()) // 0 = 전체
    var filterType: RecordFilter = .all
    var stats: [CategoryStat] = []
    var totalCount: Int = 0
    var isPaired: Bool = false
    var isLoading = false
    var errorMessage: String?

    // MARK: - Services

    private let recordService = RecordService()
    private let pairService = PairService()

    // MARK: - Computed

    var periodLabel: String {
        if selectedMonth == 0 {
            return "\(selectedYear)년"
        }
        return "\(selectedYear)년 \(selectedMonth)월"
    }

    // MARK: - Data Loading

    func loadStats() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = dateRange(year: selectedYear, month: selectedMonth)

        do {
            // 페어 상태 확인
            let pairInfo = try? await pairService.getStatus()
            isPaired = pairInfo?.status == .connected

            // 내 기록 fetch
            let myRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)

            // 파트너 기록 fetch (페어링 시)
            var partnerRecords: [DailyRecord] = []
            if isPaired {
                partnerRecords = (try? await pairService.fetchPartnerRecords(from: fromStr, to: toStr)) ?? []
            }

            // 필터 적용
            let filtered: [DailyRecord]
            switch filterType {
            case .all:
                filtered = myRecords + partnerRecords.filter { $0.together }
            case .together:
                filtered = myRecords.filter { $0.together } + partnerRecords.filter { $0.together }
            case .solo:
                filtered = myRecords.filter { !$0.together }
            }

            // 카테고리별 집계
            var countMap: [Int: (emoji: String, name: String, count: Int)] = [:]
            for record in filtered {
                let cat = record.category
                if let existing = countMap[cat.id] {
                    countMap[cat.id] = (cat.emoji, cat.name, existing.count + 1)
                } else {
                    countMap[cat.id] = (cat.emoji, cat.name, 1)
                }
            }

            totalCount = filtered.count
            stats = countMap.map { (id, val) in
                CategoryStat(
                    id: id,
                    emoji: val.emoji,
                    name: val.name,
                    count: val.count,
                    ratio: totalCount > 0 ? Double(val.count) / Double(totalCount) : 0
                )
            }.sorted { $0.count > $1.count }

        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "통계를 불러오지 못했습니다."
        }
    }

    // MARK: - Helpers

    private func dateRange(year: Int, month: Int) -> (String, String) {
        if month == 0 {
            return ("\(year)-01-01", "\(year)-12-31")
        }
        let from = String(format: "%04d-%02d-01", year, month)
        let cal = Calendar.current
        var comps = DateComponents(year: year, month: month)
        let startDate = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: startDate)!
        let to = String(format: "%04d-%02d-%02d", year, month, range.count)
        return (from, to)
    }
}
```

**Step 2: Xcode 프로젝트에 파일 등록 및 커밋**

```bash
git add -A
git commit -m "feat: StatsViewModel 구현 (통계 집계, 필터링)"
```

---

### Task 3: StatsView 구현

**Files:**
- Create: `WooriHaru/Views/Stats/StatsView.swift`

**목적:** 통계 화면 UI. 연/월 필터, 커플 필터, 카테고리별 바 차트.

**Step 1: StatsView 작성**

```swift
// WooriHaru/Views/Stats/StatsView.swift
import SwiftUI

struct StatsView: View {
    @State private var viewModel = StatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 기간 정보
                HStack {
                    Text("\(viewModel.periodLabel) · 총 \(viewModel.totalCount)건")
                        .font(.subheadline)
                        .foregroundStyle(Color.slate600)
                    Spacer()
                }

                // 연/월 필터
                HStack(spacing: 12) {
                    Picker("연도", selection: $viewModel.selectedYear) {
                        ForEach(2018...Calendar.current.component(.year, from: Date()) + 1, id: \.self) { year in
                            Text("\(String(year))년").tag(year)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("월", selection: $viewModel.selectedMonth) {
                        Text("전체").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)월").tag(month)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                // 커플 필터 (페어링 시에만)
                if viewModel.isPaired {
                    HStack(spacing: 8) {
                        ForEach(RecordFilter.allCases, id: \.self) { filter in
                            Button {
                                viewModel.filterType = filter
                                Task { await viewModel.loadStats() }
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 20)
                                            .fill(viewModel.filterType == filter ? Color.blue50 : .white)
                                            .stroke(viewModel.filterType == filter ? Color.blue300 : Color.slate200, lineWidth: 1)
                                    }
                                    .foregroundStyle(viewModel.filterType == filter ? Color.blue700 : Color.slate500)
                            }
                        }
                        Spacer()
                    }
                }

                // 차트
                if viewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 40)
                } else if viewModel.stats.isEmpty {
                    Text("해당 기간에 기록이 없습니다")
                        .font(.subheadline)
                        .foregroundStyle(Color.slate400)
                        .padding(.vertical, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(viewModel.stats) { stat in
                            StatBarView(stat: stat)
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }
            }
            .padding(16)
        }
        .navigationTitle("통계")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadStats() }
        .onChange(of: viewModel.selectedYear) { _, _ in Task { await viewModel.loadStats() } }
        .onChange(of: viewModel.selectedMonth) { _, _ in Task { await viewModel.loadStats() } }
    }
}

// MARK: - StatBarView

struct StatBarView: View {
    let stat: CategoryStat

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.emoji)
                Text(stat.name)
                    .font(.subheadline)
                Spacer()
                Text("\(stat.count)건")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(Int(stat.ratio * 100))%")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue400)
                    .frame(width: geo.size.width * stat.ratio, height: 8)
            }
            .frame(height: 8)
            .background {
                RoundedRectangle(cornerRadius: 4).fill(Color.slate100)
            }
        }
    }
}
```

**Step 2: 기존 placeholder 제거 (ContentView의 임시 StatsView)**

ContentView.swift에서 임시 StatsView placeholder를 제거한다 (Task 1에서 만든 것).

**Step 3: Xcode 프로젝트에 파일 등록 및 커밋**

```bash
git add -A
git commit -m "feat: StatsView 구현 (바 차트, 연/월/커플 필터)"
```

---

### Task 4: SearchViewModel 구현

**Files:**
- Create: `WooriHaru/ViewModels/SearchViewModel.swift`

**목적:** 검색 데이터 fetch, 카테고리/키워드 필터링 로직.

**Step 1: SearchViewModel 작성**

```swift
// WooriHaru/ViewModels/SearchViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    // MARK: - State

    var selectedYear: Int = Calendar.current.component(.year, from: Date())
    var selectedMonth: Int = 0  // 0 = 전체
    var selectedCategoryId: Int?  // nil = 전체
    var keyword: String = ""
    var results: [DailyRecord] = []
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Services

    private let recordService = RecordService()
    private let categoryService = CategoryService()
    private var allRecords: [DailyRecord] = []

    // MARK: - Data Loading

    func loadInitial() async {
        do {
            categories = try await categoryService.fetchCategories()
        } catch {
            print("[SearchVM] Failed to load categories: \(error.localizedDescription)")
        }
        await search()
    }

    func search() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        let (fromStr, toStr) = dateRange(year: selectedYear, month: selectedMonth)

        do {
            allRecords = try await recordService.fetchRecords(from: fromStr, to: toStr)
            applyFilters()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "검색에 실패했습니다."
        }
    }

    /// 클라이언트 필터링 (카테고리 + 키워드). 네트워크 호출 없음.
    func applyFilters() {
        var filtered = allRecords

        // 카테고리 필터
        if let catId = selectedCategoryId {
            filtered = filtered.filter { $0.category.id == catId }
        }

        // 키워드 필터 (memo에서 검색)
        if !keyword.isEmpty {
            let lowered = keyword.lowercased()
            filtered = filtered.filter { ($0.memo ?? "").lowercased().contains(lowered) }
        }

        // 날짜 오름차순 정렬
        results = filtered.sorted { $0.date < $1.date }
    }

    // MARK: - Helpers

    private func dateRange(year: Int, month: Int) -> (String, String) {
        if month == 0 {
            return ("\(year)-01-01", "\(year)-12-31")
        }
        let from = String(format: "%04d-%02d-01", year, month)
        let cal = Calendar.current
        let comps = DateComponents(year: year, month: month)
        let startDate = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: startDate)!
        let to = String(format: "%04d-%02d-%02d", year, month, range.count)
        return (from, to)
    }
}
```

**Step 2: 커밋**

```bash
git add -A
git commit -m "feat: SearchViewModel 구현 (기록 검색, 카테고리/키워드 필터)"
```

---

### Task 5: SearchView 구현

**Files:**
- Create: `WooriHaru/Views/Search/SearchView.swift`

**목적:** 검색 화면 UI. 필터 영역 + 결과 목록.

**Step 1: SearchView 작성**

```swift
// WooriHaru/Views/Search/SearchView.swift
import SwiftUI

struct SearchView: View {
    @State private var viewModel = SearchViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 필터 영역
            VStack(spacing: 12) {
                // Row 1: 연도 + 월
                HStack(spacing: 12) {
                    Picker("연도", selection: $viewModel.selectedYear) {
                        ForEach(2018...Calendar.current.component(.year, from: Date()) + 1, id: \.self) { year in
                            Text("\(String(year))년").tag(year)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("월", selection: $viewModel.selectedMonth) {
                        Text("전체").tag(0)
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)월").tag(month)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()
                }

                // Row 2: 카테고리 + 키워드
                HStack(spacing: 12) {
                    Menu {
                        Button("전체") { viewModel.selectedCategoryId = nil; viewModel.applyFilters() }
                        ForEach(viewModel.categories) { cat in
                            Button("\(cat.emoji) \(cat.name)") {
                                viewModel.selectedCategoryId = cat.id
                                viewModel.applyFilters()
                            }
                        }
                    } label: {
                        HStack {
                            if let catId = viewModel.selectedCategoryId,
                               let cat = viewModel.categories.first(where: { $0.id == catId }) {
                                Text("\(cat.emoji) \(cat.name)")
                            } else {
                                Text("전체 카테고리")
                            }
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.slate700)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.slate200, lineWidth: 1)
                        }
                    }

                    TextField("키워드 검색", text: $viewModel.keyword)
                        .font(.subheadline)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: viewModel.keyword) { _, _ in
                            viewModel.applyFilters()
                        }
                }
            }
            .padding(16)
            .background(.white)

            Divider()

            // 결과 목록
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .padding(.vertical, 40)
                    } else if viewModel.results.isEmpty {
                        Text("검색 결과가 없습니다")
                            .font(.subheadline)
                            .foregroundStyle(Color.slate400)
                            .padding(.vertical, 40)
                    } else {
                        ForEach(viewModel.results) { record in
                            SearchResultCard(record: record)
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("검색")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadInitial() }
        .onChange(of: viewModel.selectedYear) { _, _ in Task { await viewModel.search() } }
        .onChange(of: viewModel.selectedMonth) { _, _ in Task { await viewModel.search() } }
    }
}

// MARK: - SearchResultCard

struct SearchResultCard: View {
    let record: DailyRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
                Spacer()
                if record.together {
                    Text("👫 같이")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue50)
                        .foregroundStyle(Color.blue600)
                        .cornerRadius(10)
                }
            }

            HStack(spacing: 6) {
                Text(record.category.emoji)
                Text(record.category.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            if let memo = record.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.white)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }

    private var formattedDate: String {
        guard let date = Date.from(record.date) else { return record.date }
        let month = date.month
        let day = date.day
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = weekdays[date.weekday - 1]
        return "\(month)월 \(day)일 \(weekday)"
    }
}
```

**Step 2: 기존 placeholder 제거 + 커밋**

```bash
git add -A
git commit -m "feat: SearchView 구현 (필터 영역 + 결과 카드)"
```

---

### Task 6: CategoriesViewModel 구현

**Files:**
- Create: `WooriHaru/ViewModels/CategoriesViewModel.swift`

**목적:** 카테고리 CRUD + 드래그 정렬 로직.

**Step 1: CategoriesViewModel 작성**

```swift
// WooriHaru/ViewModels/CategoriesViewModel.swift
import Foundation
import Observation

@MainActor
@Observable
final class CategoriesViewModel {
    // MARK: - State

    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Create Form

    var newEmoji: String = ""
    var newName: String = ""
    var newIsActive: Bool = true

    // MARK: - Edit Form

    var editingId: Int?
    var editEmoji: String = ""
    var editName: String = ""
    var editIsActive: Bool = true

    // MARK: - Services

    private let categoryService = CategoryService()

    // MARK: - Data Loading

    func loadCategories() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            categories = try await categoryService.fetchCategories()
            categories.sort { $0.sortOrder == $1.sortOrder ? $0.id < $1.id : $0.sortOrder < $1.sortOrder }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리를 불러오지 못했습니다."
        }
    }

    // MARK: - CRUD

    func createCategory() async {
        guard !newEmoji.isEmpty, !newName.isEmpty else {
            errorMessage = "이모지와 이름을 입력해주세요."
            return
        }
        errorMessage = nil
        successMessage = nil

        let request = CategoryRequest(emoji: newEmoji, name: newName, isActive: newIsActive)

        do {
            try await categoryService.createCategory(request)
            newEmoji = ""
            newName = ""
            newIsActive = true
            successMessage = "새 카테고리를 추가했어요."
            await loadCategories()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 생성에 실패했습니다."
        }
    }

    func updateCategory() async {
        guard let id = editingId, !editEmoji.isEmpty, !editName.isEmpty else { return }
        errorMessage = nil
        successMessage = nil

        let request = CategoryRequest(emoji: editEmoji, name: editName, isActive: editIsActive)

        do {
            try await categoryService.updateCategory(id: id, request)
            editingId = nil
            successMessage = "카테고리를 저장했어요."
            await loadCategories()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 수정에 실패했습니다."
        }
    }

    func deleteCategory(_ category: Category) async {
        errorMessage = nil
        successMessage = nil

        do {
            try await categoryService.deleteCategory(id: category.id)
            successMessage = "삭제가 완료됐어요."
            await loadCategories()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "카테고리 삭제에 실패했습니다."
        }
    }

    // MARK: - Reorder

    func moveCategory(from source: IndexSet, to destination: Int) {
        // Optimistic UI update
        categories.move(fromOffsets: source, toOffset: destination)

        // API 호출
        guard let sourceIndex = source.first else { return }
        let moved = categories[sourceIndex < destination ? destination - 1 : destination]
        let beforeId: Int? = {
            let newIndex = sourceIndex < destination ? destination - 1 : destination
            if newIndex + 1 < categories.count {
                return categories[newIndex + 1].id
            }
            return nil
        }()

        Task {
            do {
                try await categoryService.reorderCategory(
                    ReorderCategoryRequest(targetId: moved.id, beforeId: beforeId)
                )
            } catch {
                // 실패 시 복원
                await loadCategories()
            }
        }
    }

    // MARK: - Edit Helpers

    func startEditing(_ category: Category) {
        editingId = category.id
        editEmoji = category.emoji
        editName = category.name
        editIsActive = category.isActive
    }

    func cancelEditing() {
        editingId = nil
    }
}
```

**Step 2: 커밋**

```bash
git add -A
git commit -m "feat: CategoriesViewModel 구현 (CRUD + 드래그 정렬)"
```

---

### Task 7: CategoriesView 구현

**Files:**
- Create: `WooriHaru/Views/Category/CategoriesView.swift`

**목적:** 카테고리 관리 화면 UI. 생성 폼 + 리스트(드래그 정렬, 인라인 편집, 스와이프 삭제).

**Step 1: CategoriesView 작성**

```swift
// WooriHaru/Views/Category/CategoriesView.swift
import SwiftUI

struct CategoriesView: View {
    @State private var viewModel = CategoriesViewModel()
    @State private var deleteTarget: Category?

    var body: some View {
        VStack(spacing: 0) {
            // 생성 폼
            createForm

            Divider()

            // 메시지
            if let success = viewModel.successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(Color.green700)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Color.red500)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            // 카테고리 리스트
            List {
                ForEach(viewModel.categories) { category in
                    if viewModel.editingId == category.id {
                        editRow(category)
                    } else {
                        categoryRow(category)
                    }
                }
                .onMove { source, destination in
                    viewModel.moveCategory(from: source, to: destination)
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        deleteTarget = viewModel.categories[index]
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("카테고리 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadCategories() }
        .confirmationDialog(
            "카테고리 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    Task { await viewModel.deleteCategory(target) }
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\(target.emoji) \(target.name)을(를) 삭제할까요?")
            }
        }
    }

    // MARK: - Create Form

    private var createForm: some View {
        VStack(spacing: 12) {
            Text("새 카테고리")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                TextField("😀", text: $viewModel.newEmoji)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.newEmoji) { _, newValue in
                        if newValue.count > 2 { viewModel.newEmoji = String(newValue.prefix(2)) }
                    }

                TextField("이름", text: $viewModel.newName)
                    .textFieldStyle(.roundedBorder)

                Toggle("활성", isOn: $viewModel.newIsActive)
                    .labelsHidden()

                Button {
                    Task { await viewModel.createCategory() }
                } label: {
                    Text("추가")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .font(.subheadline)
    }

    // MARK: - Category Row

    private func categoryRow(_ category: Category) -> some View {
        HStack(spacing: 10) {
            Text(category.emoji)
                .font(.title3)
            Text(category.name)
                .font(.subheadline)

            Spacer()

            Text(category.isActive ? "활성" : "비활성")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(category.isActive ? Color.green100 : Color.slate100)
                .foregroundStyle(category.isActive ? Color.green700 : Color.slate500)
                .cornerRadius(10)

            Button {
                viewModel.startEditing(category)
            } label: {
                Image(systemName: "pencil")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Edit Row

    private func editRow(_ category: Category) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("😀", text: $viewModel.editEmoji)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)

                TextField("이름", text: $viewModel.editName)
                    .textFieldStyle(.roundedBorder)

                Toggle("활성", isOn: $viewModel.editIsActive)
                    .labelsHidden()
            }

            HStack {
                Button("취소") { viewModel.cancelEditing() }
                    .font(.caption)
                    .foregroundStyle(Color.slate500)

                Spacer()

                Button {
                    Task { await viewModel.updateCategory() }
                } label: {
                    Text("저장")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.slate50)
        }
        .font(.subheadline)
    }
}
```

**Step 2: 기존 placeholder 제거 + 커밋**

```bash
git add -A
git commit -m "feat: CategoriesView 구현 (생성/수정/삭제/드래그 정렬)"
```

---

### Task 8: 통합 빌드 및 네비게이션 테스트

**Files:**
- Modify: `WooriHaru.xcodeproj/project.pbxproj` (새 파일 등록)

**목적:** 모든 새 파일을 Xcode 프로젝트에 등록하고 빌드 확인.

**Step 1: Xcode 프로젝트에 모든 새 파일 등록 확인**

새로 생성된 파일 목록:
- `WooriHaru/ViewModels/StatsViewModel.swift`
- `WooriHaru/ViewModels/SearchViewModel.swift`
- `WooriHaru/ViewModels/CategoriesViewModel.swift`
- `WooriHaru/Views/Stats/StatsView.swift`
- `WooriHaru/Views/Search/SearchView.swift`
- `WooriHaru/Views/Category/CategoriesView.swift`

수정된 파일:
- `WooriHaru/ContentView.swift`
- `WooriHaru/Views/Components/SideDrawerView.swift`
- `WooriHaru/Views/Calendar/CalendarView.swift`
- `WooriHaru/Views/Calendar/CalendarHeaderView.swift`

**Step 2: 빌드 확인**

Xcode에서 빌드가 성공하는지 확인한다. 특히:
- NavigationStack 경로가 올바르게 동작하는지
- SideDrawerView에서 각 화면으로 이동되는지
- CalendarHeaderView 검색 아이콘이 SearchView로 이동하는지

**Step 3: 커밋**

```bash
git add -A
git commit -m "chore: Phase 3 빌드 확인 및 프로젝트 설정 정리"
```
