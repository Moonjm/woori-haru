# Phase 2: 캘린더 & 기록 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 캘린더 무한스크롤 + 일일 기록 CRUD + 과식 레벨 + 공휴일 표시를 구현한다.

**Architecture:** MVVM 패턴. CalendarViewModel이 월 데이터/스크롤 범위를 관리하고, RecordViewModel이 선택 날짜의 기록 CRUD를 처리한다. 웹과 동일한 상단 헤더(햄버거+연월+검색) + 사이드 드로어 구조를 사용하며, 하단 탭바는 없다.

**Tech Stack:** SwiftUI, @Observable (iOS 17+), URLSession async/await, LazyVStack

---

### Task 1: Date+Extensions 유틸리티

**Files:**
- Create: `WooriHaru/Extensions/Date+Extensions.swift`

**Step 1: 구현**

```swift
import Foundation

extension Date {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        return f
    }()

    var dateString: String {
        let f = Date.formatter
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    var yearMonth: String {
        let f = Date.formatter
        f.dateFormat = "yyyy-MM"
        return f.string(from: self)
    }

    var year: Int { Calendar.current.component(.year, from: self) }
    var month: Int { Calendar.current.component(.month, from: self) }
    var day: Int { Calendar.current.component(.day, from: self) }
    var weekday: Int { Calendar.current.component(.weekday, from: self) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isSunday: Bool { weekday == 1 }
    var isSaturday: Bool { weekday == 7 }

    var monthDisplayText: String {
        "\(year)년 \(month)월"
    }

    var sheetHeaderText: String {
        let f = Date.formatter
        f.dateFormat = "M월 d일 EEEE"
        return f.string(from: self)
    }

    func startOfMonth() -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: self))!
    }

    func daysInMonth() -> Int {
        Calendar.current.range(of: .day, in: .month, for: self)!.count
    }

    func addingMonths(_ months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self)!
    }

    static func from(_ string: String) -> Date? {
        let f = formatter
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: string)
    }
}
```

**Step 2: Xcode 프로젝트에 추가되었는지 빌드로 확인**

Run: `cd /Users/jm/Documents/study/woori-haru && xcodebuild -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add WooriHaru/Extensions/Date+Extensions.swift
git commit -m "feat: Date 확장 유틸리티 추가"
```

---

### Task 2: Color+Extensions 색상 정의

**Files:**
- Create: `WooriHaru/Extensions/Color+Extensions.swift`

**Step 1: 구현**

웹의 Tailwind 색상을 SwiftUI Color로 매핑한다.

```swift
import SwiftUI

extension Color {
    // Slate
    static let slate50 = Color(red: 0.973, green: 0.980, blue: 0.988)
    static let slate100 = Color(red: 0.945, green: 0.961, blue: 0.976)
    static let slate200 = Color(red: 0.886, green: 0.910, blue: 0.941)
    static let slate400 = Color(red: 0.580, green: 0.639, blue: 0.718)
    static let slate500 = Color(red: 0.392, green: 0.455, blue: 0.545)
    static let slate600 = Color(red: 0.278, green: 0.333, blue: 0.412)
    static let slate700 = Color(red: 0.204, green: 0.255, blue: 0.325)
    static let slate900 = Color(red: 0.059, green: 0.094, blue: 0.169)

    // Blue
    static let blue50 = Color(red: 0.937, green: 0.961, blue: 1.0)
    static let blue300 = Color(red: 0.573, green: 0.706, blue: 0.988)
    static let blue500 = Color(red: 0.231, green: 0.510, blue: 0.965)
    static let blue700 = Color(red: 0.114, green: 0.306, blue: 0.847)

    // Red
    static let red400 = Color(red: 0.969, green: 0.447, blue: 0.447)
    static let red500 = Color(red: 0.937, green: 0.267, blue: 0.267)

    // Green (과식 MILD)
    static let green100 = Color(red: 0.863, green: 0.988, blue: 0.906)
    static let green300 = Color(red: 0.525, green: 0.937, blue: 0.675)
    static let green700 = Color(red: 0.082, green: 0.533, blue: 0.243)

    // Orange (과식 MODERATE)
    static let orange200 = Color(red: 0.996, green: 0.867, blue: 0.667)
    static let orange300 = Color(red: 0.992, green: 0.788, blue: 0.463)
    static let orange700 = Color(red: 0.769, green: 0.365, blue: 0.039)

    // Purple (과식 EXTREME)
    static let purple200 = Color(red: 0.863, green: 0.808, blue: 0.980)
    static let purple400 = Color(red: 0.647, green: 0.514, blue: 0.941)
    static let purple800 = Color(red: 0.345, green: 0.153, blue: 0.659)
}
```

**Step 2: 빌드 확인**

Run: `cd /Users/jm/Documents/study/woori-haru && xcodebuild -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add WooriHaru/Extensions/Color+Extensions.swift
git commit -m "feat: Color 확장 (Tailwind 색상 매핑) 추가"
```

---

### Task 3: CalendarViewModel

**Files:**
- Create: `WooriHaru/ViewModels/CalendarViewModel.swift`

**Step 1: 구현**

```swift
import Foundation
import Observation

struct MonthData: Identifiable {
    let id: String // "yyyy-MM"
    let year: Int
    let month: Int
    let startDate: Date
    var cells: [DayCell]

    struct DayCell: Identifiable {
        let id: String // "yyyy-MM-dd" or "empty-N"
        let date: Date?
        let day: Int?
    }
}

@MainActor
@Observable
final class CalendarViewModel {
    var months: [MonthData] = []
    var records: [String: [DailyRecord]] = [:]     // "yyyy-MM-dd" -> records
    var overeats: [String: OvereatLevel] = [:]      // "yyyy-MM-dd" -> level
    var holidays: [String: [String]] = [:]          // "yyyy-MM-dd" -> holiday names
    var currentMonthLabel: String = ""
    var isDrawerOpen = false

    private let recordService = RecordService()
    private let holidayService = HolidayService()
    private var loadedMonths: Set<String> = []
    private var loadedHolidayYears: Set<Int> = []

    func initialLoad() async {
        let today = Date()
        let start = today.startOfMonth()
        for offset in -2...2 {
            let m = start.addingMonths(offset)
            appendMonth(m)
        }
        currentMonthLabel = today.startOfMonth().monthDisplayText

        await withTaskGroup(of: Void.self) { group in
            for offset in -2...2 {
                let m = start.addingMonths(offset)
                group.addTask { await self.loadMonthData(m) }
            }
        }
    }

    func loadEarlierMonths() async {
        guard let first = months.first else { return }
        let base = first.startDate
        var newMonths: [MonthData] = []
        for offset in (-3)...(-1) {
            let m = base.addingMonths(offset)
            let data = buildMonthData(m)
            newMonths.append(data)
        }
        months.insert(contentsOf: newMonths, at: 0)

        await withTaskGroup(of: Void.self) { group in
            for monthData in newMonths {
                group.addTask { await self.loadMonthData(monthData.startDate) }
            }
        }
    }

    func loadLaterMonths() async {
        guard let last = months.last else { return }
        let base = last.startDate
        for offset in 1...3 {
            let m = base.addingMonths(offset)
            appendMonth(m)
        }

        await withTaskGroup(of: Void.self) { group in
            for offset in 1...3 {
                let m = base.addingMonths(offset)
                group.addTask { await self.loadMonthData(m) }
            }
        }
    }

    func scrollToMonth(year: Int, month: Int) async {
        let cal = Calendar.current
        guard let target = cal.date(from: DateComponents(year: year, month: month)) else { return }

        if !months.contains(where: { $0.year == year && $0.month == month }) {
            // 대상 월 ± 2 범위로 재구성
            months.removeAll()
            loadedMonths.removeAll()
            for offset in -2...2 {
                let m = target.addingMonths(offset)
                appendMonth(m)
            }
            await withTaskGroup(of: Void.self) { group in
                for offset in -2...2 {
                    let m = target.addingMonths(offset)
                    group.addTask { await self.loadMonthData(m) }
                }
            }
        }
    }

    func refreshMonth(containing dateString: String) async {
        guard let date = Date.from(dateString) else { return }
        let key = date.startOfMonth().yearMonth
        loadedMonths.remove(key)
        await loadMonthData(date.startOfMonth())
    }

    // MARK: - Private

    private func appendMonth(_ date: Date) {
        let data = buildMonthData(date)
        if !months.contains(where: { $0.id == data.id }) {
            months.append(data)
        }
    }

    private func buildMonthData(_ start: Date) -> MonthData {
        let first = start.startOfMonth()
        let weekday = first.weekday // 1=Sun
        let daysInMonth = first.daysInMonth()
        var cells: [MonthData.DayCell] = []

        // 빈 셀 (월 시작 전)
        for i in 0..<(weekday - 1) {
            cells.append(.init(id: "empty-\(first.yearMonth)-\(i)", date: nil, day: nil))
        }

        // 날짜 셀
        for d in 0..<daysInMonth {
            let date = Calendar.current.date(byAdding: .day, value: d, to: first)!
            cells.append(.init(id: date.dateString, date: date, day: d + 1))
        }

        // 끝 빈 셀 (7의 배수)
        while cells.count % 7 != 0 {
            cells.append(.init(id: "trail-\(first.yearMonth)-\(cells.count)", date: nil, day: nil))
        }

        return MonthData(
            id: first.yearMonth,
            year: first.year,
            month: first.month,
            startDate: first,
            cells: cells
        )
    }

    private func loadMonthData(_ monthStart: Date) async {
        let key = monthStart.yearMonth
        guard !loadedMonths.contains(key) else { return }
        loadedMonths.insert(key)

        let year = monthStart.year
        let month = monthStart.month
        let lastDay = monthStart.daysInMonth()
        let from = String(format: "%04d-%02d-01", year, month)
        let to = String(format: "%04d-%02d-%02d", year, month, lastDay)

        async let fetchedRecords = recordService.fetchRecords(from: from, to: to)
        async let fetchedOvereats = recordService.fetchOvereats(from: from, to: to)

        // 공휴일은 연도 단위로 한 번만
        if !loadedHolidayYears.contains(year) {
            loadedHolidayYears.insert(year)
            do {
                let h = try await holidayService.fetchHolidays(year: String(year))
                for (date, names) in h {
                    holidays[date] = names
                }
            } catch {
                loadedHolidayYears.remove(year)
            }
        }

        do {
            let recs = try await fetchedRecords
            for record in recs {
                records[record.date, default: []].append(record)
            }
        } catch {}

        do {
            let oveats = try await fetchedOvereats
            for o in oveats {
                overeats[o.date] = o.overeatLevel
            }
        } catch {}
    }
}
```

**Step 2: 빌드 확인**

Run: `xcodebuild -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add WooriHaru/ViewModels/CalendarViewModel.swift
git commit -m "feat: CalendarViewModel (월 데이터 관리, 무한스크롤, 캐싱)"
```

---

### Task 4: RecordViewModel

**Files:**
- Create: `WooriHaru/ViewModels/RecordViewModel.swift`

**Step 1: 구현**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class RecordViewModel {
    var selectedDate: Date = Date()
    var records: [DailyRecord] = []
    var overeatLevel: OvereatLevel = .none
    var categories: [Category] = []
    var isLoading = false
    var errorMessage: String?

    // 폼 상태
    var selectedCategoryId: Int?
    var memo: String = ""
    var editingRecord: DailyRecord?

    private let recordService = RecordService()
    private let categoryService = CategoryService()

    var dateString: String { selectedDate.dateString }

    func loadData() async {
        isLoading = true
        defer { isLoading = false }

        async let fetchedRecords = recordService.fetchRecords(date: dateString)
        async let fetchedCategories = categoryService.fetchCategories(active: true)
        async let fetchedOvereats = recordService.fetchOvereats(from: dateString, to: dateString)

        do {
            records = try await fetchedRecords
        } catch {}

        do {
            categories = try await fetchedCategories
        } catch {}

        do {
            let oveats = try await fetchedOvereats
            overeatLevel = oveats.first?.overeatLevel ?? .none
        } catch {}
    }

    func createRecord() async {
        guard let categoryId = selectedCategoryId else { return }
        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: false
        )
        do {
            try await recordService.createRecord(request)
            resetForm()
            await loadData()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "기록 저장에 실패했습니다."
        }
    }

    func updateRecord() async {
        guard let record = editingRecord, let categoryId = selectedCategoryId else { return }
        let request = DailyRecordRequest(
            date: dateString,
            categoryId: categoryId,
            memo: memo.isEmpty ? nil : memo,
            together: record.together
        )
        do {
            try await recordService.updateRecord(id: record.id, request)
            resetForm()
            await loadData()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "수정에 실패했습니다."
        }
    }

    func deleteRecord(_ record: DailyRecord) async {
        do {
            try await recordService.deleteRecord(id: record.id)
            await loadData()
        } catch {}
    }

    func updateOvereat(_ level: OvereatLevel) async {
        let request = UpdateOvereatRequest(date: dateString, overeatLevel: level)
        do {
            try await recordService.updateOvereat(request)
            overeatLevel = level
        } catch {}
    }

    func startEditing(_ record: DailyRecord) {
        editingRecord = record
        selectedCategoryId = record.category.id
        memo = record.memo ?? ""
    }

    func resetForm() {
        editingRecord = nil
        selectedCategoryId = nil
        memo = ""
    }
}
```

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add WooriHaru/ViewModels/RecordViewModel.swift
git commit -m "feat: RecordViewModel (기록 CRUD, 과식 레벨, 카테고리)"
```

---

### Task 5: WeekdayHeaderView + DayCellView

**Files:**
- Create: `WooriHaru/Views/Calendar/WeekdayHeaderView.swift`
- Create: `WooriHaru/Views/Calendar/DayCellView.swift`

**Step 1: WeekdayHeaderView**

```swift
import SwiftUI

struct WeekdayHeaderView: View {
    private let days = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(index == 0 ? .red500 : index == 6 ? .blue500 : .slate500)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(.white)
    }
}
```

**Step 2: DayCellView**

```swift
import SwiftUI

struct DayCellView: View {
    let date: Date
    let records: [DailyRecord]
    let overeatLevel: OvereatLevel?
    let holidays: [String]
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            // 날짜 + 과식
            HStack(spacing: 2) {
                dateNumber
                overeatIndicator
                Spacer()
            }

            // 공휴일
            ForEach(holidays.prefix(2), id: \.self) { name in
                Text(name)
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(.red.opacity(0.1))
                    .foregroundStyle(.red500)
                    .cornerRadius(2)
            }

            // 기록 이모지
            let emojis = records.map { $0.category.emoji }
            if !emojis.isEmpty {
                Text(emojis.joined())
                    .font(.system(size: 12))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(2)
        .background(.white)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    @ViewBuilder
    private var dateNumber: some View {
        let isToday = date.isToday
        Text("\(date.day)")
            .font(.caption2)
            .fontWeight(isToday ? .bold : .regular)
            .foregroundStyle(dateColor)
            .padding(4)
            .background {
                if isToday {
                    Circle().fill(.slate900)
                }
            }
            .foregroundStyle(isToday ? .white : dateColor)
    }

    private var dateColor: Color {
        if date.isToday { return .white }
        if date.isSunday || !holidays.isEmpty { return .red500 }
        if date.isSaturday { return .blue500 }
        return .primary
    }

    @ViewBuilder
    private var overeatIndicator: some View {
        if let level = overeatLevel, level != .none {
            Text("🐷")
                .font(.system(size: 10))
                .padding(2)
                .background {
                    Circle().fill(overeatColor(level).opacity(0.3))
                }
        }
    }

    private func overeatColor(_ level: OvereatLevel) -> Color {
        switch level {
        case .none: return .clear
        case .mild: return .green300
        case .moderate: return .orange300
        case .severe: return .red400
        case .extreme: return .purple400
        }
    }
}
```

**Step 3: 빌드 확인**

**Step 4: Commit**

```bash
git add WooriHaru/Views/Calendar/WeekdayHeaderView.swift WooriHaru/Views/Calendar/DayCellView.swift
git commit -m "feat: 요일 헤더 + 날짜 셀 뷰 구현"
```

---

### Task 6: MonthGridView + CalendarView (메인 스크롤)

**Files:**
- Create: `WooriHaru/Views/Calendar/MonthGridView.swift`
- Create: `WooriHaru/Views/Calendar/CalendarView.swift`

**Step 1: MonthGridView**

```swift
import SwiftUI

struct MonthGridView: View {
    let monthData: MonthData
    let records: [String: [DailyRecord]]
    let overeats: [String: OvereatLevel]
    let holidays: [String: [String]]
    let onSelectDate: (Date) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0.5), count: 7), spacing: 0.5) {
            ForEach(monthData.cells) { cell in
                if let date = cell.date {
                    DayCellView(
                        date: date,
                        records: records[cell.id] ?? [],
                        overeatLevel: overeats[cell.id],
                        holidays: holidays[cell.id] ?? [],
                        onTap: { onSelectDate(date) }
                    )
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
            }
        }
        .background(Color.slate200.opacity(0.5))
    }
}
```

**Step 2: CalendarView**

```swift
import SwiftUI

struct CalendarView: View {
    @State private var calendarVM = CalendarViewModel()
    @State private var recordVM = RecordViewModel()
    @State private var showSheet = false
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            CalendarHeaderView(
                monthLabel: calendarVM.currentMonthLabel,
                onMenuTap: { calendarVM.isDrawerOpen = true },
                onMonthTap: { showPicker.toggle() },
                onSearchTap: { /* Phase 3 */ }
            )

            // 요일 헤더
            WeekdayHeaderView()

            // 캘린더 스크롤
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(calendarVM.months) { monthData in
                            Section {
                                MonthGridView(
                                    monthData: monthData,
                                    records: calendarVM.records,
                                    overeats: calendarVM.overeats,
                                    holidays: calendarVM.holidays,
                                    onSelectDate: { date in
                                        recordVM.selectedDate = date
                                        showSheet = true
                                    }
                                )
                            } header: {
                                Text(monthData.startDate.monthDisplayText)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.slate500)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(.white.opacity(0.9))
                                    .id(monthData.id)
                            }
                            .onAppear {
                                calendarVM.currentMonthLabel = monthData.startDate.monthDisplayText
                                // 끝 감지
                                if monthData.id == calendarVM.months.last?.id {
                                    Task { await calendarVM.loadLaterMonths() }
                                }
                                if monthData.id == calendarVM.months.first?.id {
                                    Task { await calendarVM.loadEarlierMonths() }
                                }
                            }
                        }
                    }
                }
                .onChange(of: showPicker) { _, show in
                    if !show, let target = findPickerTarget() {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            RecordSheetView(viewModel: recordVM) {
                Task { await calendarVM.refreshMonth(containing: recordVM.dateString) }
            }
            .presentationDetents([.fraction(0.7)])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if calendarVM.isDrawerOpen {
                SideDrawerView(isOpen: $calendarVM.isDrawerOpen)
            }
        }
        .overlay {
            if showPicker {
                YearMonthPickerView(isPresented: $showPicker) { year, month in
                    Task { await calendarVM.scrollToMonth(year: year, month: month) }
                }
            }
        }
        .task {
            await calendarVM.initialLoad()
        }
    }

    private func findPickerTarget() -> String? {
        // 현재 라벨에서 year/month 파싱
        nil // YearMonthPicker에서 직접 scrollTo 호출
    }
}
```

**Step 3: 빌드 확인**

**Step 4: Commit**

```bash
git add WooriHaru/Views/Calendar/MonthGridView.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "feat: 캘린더 메인 뷰 (무한스크롤, 월별 그리드)"
```

---

### Task 7: CalendarHeaderView

**Files:**
- Create: `WooriHaru/Views/Calendar/CalendarHeaderView.swift`

**Step 1: 구현**

```swift
import SwiftUI

struct CalendarHeaderView: View {
    let monthLabel: String
    let onMenuTap: () -> Void
    let onMonthTap: () -> Void
    let onSearchTap: () -> Void

    var body: some View {
        HStack {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .font(.title3)
                    .foregroundStyle(.slate700)
            }

            Spacer()

            Button(action: onMonthTap) {
                HStack(spacing: 4) {
                    Text(monthLabel)
                        .font(.headline)
                        .foregroundStyle(.slate900)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.slate500)
                }
            }

            Spacer()

            Button(action: onSearchTap) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(.slate700)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white)
    }
}
```

**Step 2: Commit**

```bash
git add WooriHaru/Views/Calendar/CalendarHeaderView.swift
git commit -m "feat: 캘린더 상단 헤더 (햄버거/연월/검색)"
```

---

### Task 8: OvereatSelectorView + RecordListView + RecordFormView

**Files:**
- Create: `WooriHaru/Views/Record/OvereatSelectorView.swift`
- Create: `WooriHaru/Views/Record/RecordListView.swift`
- Create: `WooriHaru/Views/Record/RecordFormView.swift`

**Step 1: OvereatSelectorView**

```swift
import SwiftUI

struct OvereatSelectorView: View {
    let currentLevel: OvereatLevel
    let onSelect: (OvereatLevel) -> Void

    private let levels: [(OvereatLevel, String)] = [
        (.none, "없음"), (.mild, "소"), (.moderate, "중"), (.severe, "대"), (.extreme, "대대")
    ]

    var body: some View {
        HStack {
            Text("🐷 과식")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.slate600)

            Spacer()

            HStack(spacing: 4) {
                ForEach(levels, id: \.0) { level, label in
                    Button(action: { onSelect(level) }) {
                        Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(buttonBackground(level))
                            .foregroundStyle(buttonForeground(level))
                            .clipShape(Capsule())
                            .overlay {
                                if currentLevel == level && level != .none {
                                    Capsule().stroke(buttonBorder(level), lineWidth: 1)
                                }
                            }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.slate50)
                .stroke(.slate200, lineWidth: 1)
        }
    }

    private func buttonBackground(_ level: OvereatLevel) -> Color {
        guard currentLevel == level else { return .white }
        switch level {
        case .none: return .white
        case .mild: return .green100
        case .moderate: return .orange200
        case .severe: return Color.red.opacity(0.15)
        case .extreme: return .purple200
        }
    }

    private func buttonForeground(_ level: OvereatLevel) -> Color {
        guard currentLevel == level else { return .slate400 }
        switch level {
        case .none: return .slate500
        case .mild: return .green700
        case .moderate: return .orange700
        case .severe: return .red500
        case .extreme: return .purple800
        }
    }

    private func buttonBorder(_ level: OvereatLevel) -> Color {
        switch level {
        case .none: return .slate200
        case .mild: return .green300
        case .moderate: return .orange300
        case .severe: return .red400
        case .extreme: return .purple400
        }
    }
}
```

**Step 2: RecordListView**

```swift
import SwiftUI

struct RecordListView: View {
    let records: [DailyRecord]
    let onDelete: (DailyRecord) -> Void
    let onTap: (DailyRecord) -> Void

    var body: some View {
        if records.isEmpty {
            Text("기록이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.slate400)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("나의 기록")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.slate600)

                FlowLayout(spacing: 6) {
                    ForEach(records) { record in
                        RecordPill(record: record, onDelete: { onDelete(record) })
                            .onTapGesture { onTap(record) }
                    }
                }
            }
        }
    }
}

struct RecordPill: View {
    let record: DailyRecord
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(record.category.emoji)
                .font(.subheadline)
            Text(record.category.name)
                .font(.caption)
            if let memo = record.memo, !memo.isEmpty {
                Text(memo)
                    .font(.caption)
                    .foregroundStyle(.slate500)
            }
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.red400)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(.slate200, lineWidth: 1)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
```

**Step 3: RecordFormView**

```swift
import SwiftUI

struct RecordFormView: View {
    @Bindable var viewModel: RecordViewModel
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 카테고리 선택
            FlowLayout(spacing: 8) {
                ForEach(viewModel.categories) { category in
                    Button {
                        viewModel.selectedCategoryId = category.id
                    } label: {
                        HStack(spacing: 4) {
                            Text(category.emoji)
                            Text(category.name)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(viewModel.selectedCategoryId == category.id ? .blue50 : .white)
                                .stroke(viewModel.selectedCategoryId == category.id ? .blue300 : .slate200, lineWidth: 1)
                        }
                        .foregroundStyle(viewModel.selectedCategoryId == category.id ? .blue700 : .slate700)
                    }
                }
            }

            // 메모 + 저장
            HStack(spacing: 8) {
                TextField("메모 (최대 20자)", text: $viewModel.memo)
                    .font(.subheadline)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: viewModel.memo) { _, newValue in
                        if newValue.count > 20 { viewModel.memo = String(newValue.prefix(20)) }
                    }

                Button(action: onSave) {
                    Text(viewModel.editingRecord != nil ? "수정" : "저장")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedCategoryId != nil ? .blue500 : .slate400)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(viewModel.selectedCategoryId == nil)
            }

            // 편집 중 취소
            if viewModel.editingRecord != nil {
                Button("취소") {
                    viewModel.resetForm()
                }
                .font(.caption)
                .foregroundStyle(.slate500)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.slate50)
                .stroke(.slate200, lineWidth: 1)
        }
    }
}
```

**Step 4: 빌드 확인**

**Step 5: Commit**

```bash
git add WooriHaru/Views/Record/OvereatSelectorView.swift WooriHaru/Views/Record/RecordListView.swift WooriHaru/Views/Record/RecordFormView.swift
git commit -m "feat: 과식 선택기 + 기록 목록 + 기록 입력 폼"
```

---

### Task 9: RecordSheetView (바텀시트)

**Files:**
- Create: `WooriHaru/Views/Record/RecordSheetView.swift`

**Step 1: 구현**

```swift
import SwiftUI

struct RecordSheetView: View {
    @Bindable var viewModel: RecordViewModel
    let onDismissRefresh: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 헤더
                    sheetHeader

                    // 과식 선택기
                    OvereatSelectorView(
                        currentLevel: viewModel.overeatLevel,
                        onSelect: { level in
                            Task { await viewModel.updateOvereat(level) }
                        }
                    )

                    // 기록 목록
                    RecordListView(
                        records: viewModel.records,
                        onDelete: { record in
                            Task {
                                await viewModel.deleteRecord(record)
                                onDismissRefresh()
                            }
                        },
                        onTap: { record in
                            viewModel.startEditing(record)
                        }
                    )

                    // 입력 폼
                    RecordFormView(viewModel: viewModel) {
                        Task {
                            if viewModel.editingRecord != nil {
                                await viewModel.updateRecord()
                            } else {
                                await viewModel.createRecord()
                            }
                            onDismissRefresh()
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red500)
                    }
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await viewModel.loadData()
        }
        .onDisappear {
            viewModel.resetForm()
        }
    }

    @ViewBuilder
    private var sheetHeader: some View {
        VStack(spacing: 4) {
            Text(viewModel.selectedDate.sheetHeaderText)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}
```

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add WooriHaru/Views/Record/RecordSheetView.swift
git commit -m "feat: 기록 바텀시트 (과식+목록+폼 통합)"
```

---

### Task 10: SideDrawerView

**Files:**
- Create: `WooriHaru/Views/Components/SideDrawerView.swift`

**Step 1: 구현**

```swift
import SwiftUI

struct SideDrawerView: View {
    @Binding var isOpen: Bool
    @Environment(AuthViewModel.self) private var authVM

    var body: some View {
        ZStack(alignment: .leading) {
            // 배경 딤
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { isOpen = false } }

            // 드로어
            VStack(alignment: .leading, spacing: 0) {
                // 헤더
                VStack(alignment: .leading, spacing: 4) {
                    Text(authVM.user?.name ?? "사용자")
                        .font(.headline)
                    Text(authVM.user?.username ?? "")
                        .font(.caption)
                        .foregroundStyle(.slate500)
                }
                .padding(20)

                Divider()

                // 메뉴
                VStack(spacing: 0) {
                    drawerItem(icon: "person.2", label: "커플") {
                        // Phase 4
                        isOpen = false
                    }
                    drawerItem(icon: "chart.bar", label: "통계") {
                        // Phase 3
                        isOpen = false
                    }
                    drawerItem(icon: "magnifyingglass", label: "검색") {
                        // Phase 3
                        isOpen = false
                    }
                    drawerItem(icon: "person.circle", label: "내 정보") {
                        // Phase 5
                        isOpen = false
                    }
                }

                Spacer()

                // 로그아웃
                Button {
                    Task {
                        await authVM.logout()
                        isOpen = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("로그아웃")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red500)
                    .padding(20)
                }
            }
            .frame(width: 260)
            .background(.white)
        }
        .transition(.opacity)
    }

    private func drawerItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(label)
                Spacer()
            }
            .font(.subheadline)
            .foregroundStyle(.slate700)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
```

**Step 2: Commit**

```bash
git add WooriHaru/Views/Components/SideDrawerView.swift
git commit -m "feat: 사이드 드로어 (햄버거 메뉴)"
```

---

### Task 11: YearMonthPickerView

**Files:**
- Create: `WooriHaru/Views/Calendar/YearMonthPickerView.swift`

**Step 1: 구현**

```swift
import SwiftUI

struct YearMonthPickerView: View {
    @Binding var isPresented: Bool
    let onSelect: (Int, Int) -> Void

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth: Int = Calendar.current.component(.month, from: Date())

    private let years = Array(2018...2037)
    private let months = Array(1...12)

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 16) {
                HStack {
                    Picker("년", selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text("\(year)년").tag(year)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("월", selection: $selectedMonth) {
                        ForEach(months, id: \.self) { month in
                            Text("\(month)월").tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 150)

                HStack(spacing: 12) {
                    Button("취소") {
                        isPresented = false
                    }
                    .foregroundStyle(.slate500)

                    Button("이동") {
                        onSelect(selectedYear, selectedMonth)
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue500)
                }
                .font(.subheadline)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white)
                    .shadow(radius: 10)
            )
            .padding(.horizontal, 40)
        }
    }
}
```

**Step 2: Commit**

```bash
git add WooriHaru/Views/Calendar/YearMonthPickerView.swift
git commit -m "feat: 연/월 빠른 이동 피커"
```

---

### Task 12: ContentView 교체 + WooriHaruApp 연결

**Files:**
- Modify: `WooriHaru/ContentView.swift`
- Modify: `WooriHaru/WooriHaruApp.swift`

**Step 1: ContentView를 CalendarView로 교체**

ContentView.swift의 body를 CalendarView()로 변경:

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        CalendarView()
    }
}
```

**Step 2: 빌드 확인**

Run: `xcodebuild -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add WooriHaru/ContentView.swift
git commit -m "feat: ContentView → CalendarView 연결"
```

---

### Task 13: Xcode 프로젝트에 신규 파일 등록 + 전체 빌드

**Files:**
- Modify: `WooriHaru.xcodeproj/project.pbxproj`

이 태스크는 Xcode가 자동으로 관리하는 프로젝트 파일이므로, 빌드 시 파일이 인식되지 않으면 수동으로 프로젝트에 추가해야 한다. 파일 생성 시 적절한 위치에 생성했다면 Xcode가 자동으로 인식할 수 있다.

**Step 1: 전체 빌드 테스트**

Run: `cd /Users/jm/Documents/study/woori-haru && xcodebuild -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20`

**Step 2: 빌드 에러가 있으면 수정**

일반적인 문제:
- 파일이 pbxproj에 등록 안 됨 → Xcode에서 수동 추가
- import 누락 → 파일 상단에 import 추가
- 타입 불일치 → 모델 확인

**Step 3: 최종 Commit**

```bash
git add -A
git commit -m "feat: Phase 2 전체 빌드 통과"
```
