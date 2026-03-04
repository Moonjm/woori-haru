# Phase 4: 커플 기능 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 페어링 관리, 기념일 관리, 캘린더 파트너 기록 표시를 iOS로 구현한다.

**Architecture:** `@Observable` ViewModel + SwiftUI View + 기존 PairService/PairEventService 재사용. CalendarViewModel 확장으로 파트너 기록과 기념일을 캘린더에 통합.

**Tech Stack:** SwiftUI, iOS 17+ @Observable, async/await

---

## Task 1: 네비게이션 확장 + PairViewModel

**Files:**
- Modify: `WooriHaru/ContentView.swift`
- Modify: `WooriHaru/Views/Components/SideDrawerView.swift`
- Create: `WooriHaru/ViewModels/PairViewModel.swift`

**Step 1: AppDestination에 .pair, .pairEvents 추가**

`ContentView.swift`에서 AppDestination enum 수정:

```swift
enum AppDestination: Hashable {
    case stats
    case search
    case categories
    case pair
    case pairEvents
}
```

그리고 navigationDestination switch에 추가:

```swift
case .pair: PairView(navPath: $path)
case .pairEvents: PairEventsView()
```

**Step 2: SideDrawerView 커플 메뉴에 네비게이션 연결**

`SideDrawerView.swift`에서 "커플" 메뉴 항목 수정 (line 27):

```swift
drawerItem(icon: "person.2", label: "커플") { isOpen = false; navPath.append(AppDestination.pair) }
```

**Step 3: PairViewModel 작성**

`WooriHaru/ViewModels/PairViewModel.swift` 생성:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class PairViewModel {

    // MARK: - State

    var pairInfo: PairInfo?
    var inviteCode: String?
    var inputCode: String = ""
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Computed

    var isPaired: Bool {
        pairInfo?.status == .connected
    }

    var isPending: Bool {
        pairInfo?.status == .pending
    }

    // MARK: - Service

    private let pairService = PairService()

    // MARK: - Actions

    func loadStatus() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            pairInfo = try await pairService.getStatus()
        } catch {
            errorMessage = "페어 상태를 불러오지 못했습니다."
        }
    }

    func createInvite() async {
        errorMessage = nil
        do {
            let response = try await pairService.createInvite()
            inviteCode = response.inviteCode
            await loadStatus()
        } catch {
            errorMessage = "초대 코드 생성에 실패했습니다."
        }
    }

    func acceptInvite() async {
        let code = inputCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        errorMessage = nil
        do {
            let info = try await pairService.acceptInvite(code: code)
            pairInfo = info
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
            try await pairService.unpair()
            pairInfo = nil
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

**Step 4: Commit**

```bash
git add WooriHaru/ContentView.swift WooriHaru/Views/Components/SideDrawerView.swift WooriHaru/ViewModels/PairViewModel.swift
git commit -m "feat: PairViewModel + 네비게이션 확장"
```

---

## Task 2: PairView

**Files:**
- Create: `WooriHaru/Views/Pair/PairView.swift`

**Step 1: PairView 작성**

3가지 상태 분기 UI:

```swift
import SwiftUI

struct PairView: View {
    @Binding var navPath: NavigationPath
    @State private var viewModel = PairViewModel()
    @State private var showUnpairConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Messages
                if let success = viewModel.successMessage {
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(Color.green700)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                }

                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.isPaired {
                    connectedSection
                } else if viewModel.isPending {
                    pendingSection
                } else {
                    disconnectedSection
                }
            }
            .padding(20)
        }
        .navigationTitle("커플")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadStatus()
        }
        .confirmationDialog("페어 해제", isPresented: $showUnpairConfirm, titleVisibility: .visible) {
            Button("해제", role: .destructive) {
                Task { await viewModel.unpair() }
            }
        } message: {
            Text("파트너와의 연결을 해제할까요?")
        }
    }

    // MARK: - Connected

    private var connectedSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.red400)

            if let name = viewModel.pairInfo?.partnerName {
                Text(name)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            if let connectedAt = viewModel.pairInfo?.connectedAt {
                Text("연결일: \(connectedAt.prefix(10))")
                    .font(.caption)
                    .foregroundStyle(Color.slate500)
            }

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

            Button {
                showUnpairConfirm = true
            } label: {
                Text("페어 해제")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
        }
    }

    // MARK: - Pending

    private var pendingSection: some View {
        VStack(spacing: 16) {
            Text("초대 대기 중")
                .font(.headline)

            if let code = viewModel.inviteCode {
                Text(code.uppercased())
                    .font(.system(.title, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(4)

                Button {
                    UIPasteboard.general.string = code.uppercased()
                    viewModel.successMessage = "코드가 복사되었습니다."
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("코드 복사")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.blue500)
                }
            }

            Button {
                Task { await viewModel.unpair() }
            } label: {
                Text("초대 취소")
                    .font(.subheadline)
                    .foregroundStyle(Color.red500)
            }
        }
    }

    // MARK: - Disconnected

    private var disconnectedSection: some View {
        VStack(spacing: 24) {
            // Create invite
            VStack(spacing: 12) {
                Text("초대 코드 생성")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Button {
                    Task { await viewModel.createInvite() }
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
            }

            Divider()

            // Accept invite
            VStack(spacing: 12) {
                Text("초대 코드 입력")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    TextField("6자리 코드 입력", text: $viewModel.inputCode)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .onChange(of: viewModel.inputCode) { _, newValue in
                            if newValue.count > 6 { viewModel.inputCode = String(newValue.prefix(6)) }
                        }

                    Button {
                        Task { await viewModel.acceptInvite() }
                    } label: {
                        Text("수락")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(viewModel.inputCode.count == 6 ? Color.blue500 : Color.slate400)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(viewModel.inputCode.count != 6)
                }
            }
        }
    }
}
```

**Step 2: Commit**

```bash
git add WooriHaru/Views/Pair/PairView.swift
git commit -m "feat: PairView 화면 구현 (미연결/대기/연결 상태)"
```

---

## Task 3: PairEventsViewModel + PairEventsView

**Files:**
- Create: `WooriHaru/ViewModels/PairEventsViewModel.swift`
- Create: `WooriHaru/Views/Pair/PairEventsView.swift`

**Step 1: PairEventsViewModel 작성**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class PairEventsViewModel {

    // MARK: - State

    var events: [PairEvent] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?

    // MARK: - Form State

    var newEmoji: String = ""
    var newTitle: String = ""
    var newDate: Date = .now
    var newRecurring: Bool = false

    // MARK: - Service

    private let pairEventService = PairEventService()

    // MARK: - Actions

    func loadEvents() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            events = try await pairEventService.fetchEvents()
        } catch {
            errorMessage = "기념일을 불러오지 못했습니다."
        }
    }

    func createEvent() async {
        let emoji = newEmoji.trimmingCharacters(in: .whitespaces)
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !emoji.isEmpty, !title.isEmpty else {
            errorMessage = "이모지와 제목을 입력해주세요."
            return
        }

        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: newDate)

        let request = PairEventRequest(
            title: title,
            emoji: emoji,
            eventDate: dateStr,
            recurring: newRecurring
        )

        do {
            try await pairEventService.createEvent(request)
            resetForm()
            await loadEvents()
            successMessage = "기념일이 추가되었습니다."
        } catch {
            errorMessage = "기념일 추가에 실패했습니다."
        }
    }

    func deleteEvent(_ event: PairEvent) async {
        errorMessage = nil
        do {
            try await pairEventService.deleteEvent(id: event.id)
            events.removeAll { $0.id == event.id }
        } catch {
            errorMessage = "기념일 삭제에 실패했습니다."
        }
    }

    private func resetForm() {
        newEmoji = ""
        newTitle = ""
        newDate = .now
        newRecurring = false
    }
}
```

**Step 2: PairEventsView 작성**

```swift
import SwiftUI

struct PairEventsView: View {
    @State private var viewModel = PairEventsViewModel()
    @State private var deleteTarget: PairEvent?

    var body: some View {
        VStack(spacing: 0) {
            // 생성 폼
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
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue500)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(16)
            .font(.subheadline)

            Divider()

            // Messages
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

            // Event list
            List {
                ForEach(viewModel.events) { event in
                    HStack(spacing: 10) {
                        Text(event.emoji).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title).font(.subheadline)
                            Text(event.eventDate)
                                .font(.caption)
                                .foregroundStyle(Color.slate500)
                        }
                        Spacer()
                        if event.recurring {
                            Text("🔄 매년")
                                .font(.caption2)
                                .foregroundStyle(Color.blue600)
                        }
                    }
                }
                .onDelete { indexSet in
                    if let index = indexSet.first {
                        deleteTarget = viewModel.events[index]
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("기념일 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadEvents() }
        .confirmationDialog(
            "기념일 삭제",
            isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                if let target = deleteTarget {
                    Task { await viewModel.deleteEvent(target) }
                    deleteTarget = nil
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("\(target.emoji) \(target.title)을(를) 삭제할까요?")
            }
        }
    }
}
```

**Step 3: Commit**

```bash
git add WooriHaru/ViewModels/PairEventsViewModel.swift WooriHaru/Views/Pair/PairEventsView.swift
git commit -m "feat: PairEventsViewModel + PairEventsView 구현"
```

---

## Task 4: CalendarViewModel 확장 (파트너 기록 + 기념일 + 생일)

**Files:**
- Modify: `WooriHaru/ViewModels/CalendarViewModel.swift`

**Step 1: 파트너/기념일/생일 상태 추가**

CalendarViewModel 상태 섹션에 추가 (line 30 이후):

```swift
var partnerRecords: [String: [DailyRecord]] = [:]
var pairEvents: [String: [PairEvent]] = [:]
var birthdayMap: [String: [(emoji: String, label: String)]] = [:]
var isPaired: Bool = false
var pairInfo: PairInfo?
```

서비스 추가 (line 41 이후):

```swift
private let pairService = PairService()
private let pairEventService = PairEventService()
```

**Step 2: initialLoad에 페어 상태 체크 추가**

`initialLoad()` 맨 앞에 페어 상태 확인 추가:

```swift
func initialLoad() async {
    // 페어 상태 확인
    do {
        pairInfo = try await pairService.getStatus()
        isPaired = pairInfo?.status == .connected
    } catch {
        isPaired = false
    }

    // 생일 맵 구축
    buildBirthdayMap()

    // 기존 코드 그대로...
    let today = Date()
    // ...
}
```

**Step 3: loadMonthData 확장**

`loadMonthData()` 끝에 페어링 시 파트너 기록 + 기념일 fetch 추가:

```swift
// Fetch partner records (only when paired)
if isPaired {
    do {
        let partnerRecs = try await pairService.fetchPartnerRecords(from: fromStr, to: toStr)
        for dayOffset in 0..<daysInMonth {
            if let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: startDate) {
                partnerRecords[dayDate.dateString] = []
            }
        }
        for record in partnerRecs {
            partnerRecords[record.date, default: []].append(record)
        }
    } catch {
        print("[CalendarVM] Failed to fetch partner records: \(error.localizedDescription)")
    }

    do {
        let events = try await pairEventService.fetchEvents(from: fromStr, to: toStr)
        for event in events {
            pairEvents[event.eventDate, default: []].append(event)
        }
        // recurring 이벤트: 현재 연도의 MM-DD에도 추가
        for event in events where event.recurring {
            let mmdd = String(event.eventDate.suffix(5)) // "MM-dd"
            let thisYearDate = "\(monthData.year)-\(mmdd)"
            if thisYearDate != event.eventDate {
                pairEvents[thisYearDate, default: []].append(event)
            }
        }
    } catch {
        print("[CalendarVM] Failed to fetch pair events: \(error.localizedDescription)")
    }
}
```

**Step 4: buildBirthdayMap 헬퍼 추가**

```swift
private func buildBirthdayMap() {
    birthdayMap.removeAll()

    // 현재 사용자 생일은 AuthViewModel에서 가져올 수 없으므로
    // 별도로 user 정보를 받아야 함 — 외부에서 주입
}

/// CalendarView에서 authVM.user를 전달하여 생일 맵 구축
func updateBirthdays(user: User?, pairInfo: PairInfo?) {
    birthdayMap.removeAll()

    let currentYear = Calendar.current.component(.year, from: Date())
    let years = loadedMonthIds.compactMap { Int($0.prefix(4)) }
    let yearRange = Set(years).union([currentYear])

    // 내 생일
    if let birthDate = user?.birthDate, birthDate.count >= 10 {
        let mmdd = String(birthDate.suffix(5))
        let genderEmoji = user?.gender == .male ? "👨" : user?.gender == .female ? "👩" : ""
        for year in yearRange {
            let key = "\(year)-\(mmdd)"
            birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "내 생일"))
        }
    }

    // 파트너 생일
    if let birthDate = pairInfo?.partnerBirthDate, birthDate.count >= 10 {
        let mmdd = String(birthDate.suffix(5))
        let name = pairInfo?.partnerName ?? "파트너"
        let genderEmoji = pairInfo?.partnerGender == .male ? "👨" : pairInfo?.partnerGender == .female ? "👩" : ""
        for year in yearRange {
            let key = "\(year)-\(mmdd)"
            birthdayMap[key, default: []].append((emoji: "🎂\(genderEmoji)", label: "\(name) 생일"))
        }
    }
}
```

**Step 5: Commit**

```bash
git add WooriHaru/ViewModels/CalendarViewModel.swift
git commit -m "feat: CalendarViewModel 파트너 기록 + 기념일 + 생일 확장"
```

---

## Task 5: DayCellView 확장 (파트너 기록 + 기념일 + 생일 표시)

**Files:**
- Modify: `WooriHaru/Views/Calendar/DayCellView.swift`
- Modify: `WooriHaru/Views/Calendar/MonthGridView.swift`
- Modify: `WooriHaru/Views/Calendar/CalendarView.swift`

**Step 1: DayCellView에 파트너/기념일/생일 프로퍼티 추가**

DayCellView의 프로퍼티를 확장:

```swift
struct DayCellView: View {
    let date: Date
    let records: [DailyRecord]
    let partnerRecords: [DailyRecord]
    let overeatLevel: OvereatLevel?
    let holidays: [String]
    let pairEvents: [PairEvent]
    let birthdays: [(emoji: String, label: String)]
    let isCurrentMonth: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                dateNumber
                if isCurrentMonth { overeatIndicator }
                Spacer()
            }

            if isCurrentMonth {
                // 공휴일
                ForEach(holidays.prefix(2), id: \.self) { name in
                    Text(name)
                        .font(.system(size: 8))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(Color.red.opacity(0.1))
                        .foregroundStyle(Color.red500)
                        .cornerRadius(2)
                }

                // 기념일 + 생일 이모지
                let eventEmojis = pairEvents.map(\.emoji) + birthdays.map(\.emoji)
                if !eventEmojis.isEmpty {
                    Text(eventEmojis.joined())
                        .font(.system(size: 10))
                        .lineLimit(1)
                }

                // 같이 한 것 (together)
                let togetherEmojis = records.filter(\.together).map { $0.category.emoji }
                    + partnerRecords.filter(\.together).map { $0.category.emoji }
                if !togetherEmojis.isEmpty {
                    Text(togetherEmojis.joined())
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 1)
                        .background(Color.blue50)
                        .cornerRadius(2)
                }

                // 개별 기록: 내 것 + 파트너 (파트너는 opacity 낮게)
                let myEmojis = records.filter { !$0.together }.map { $0.category.emoji }
                let partnerEmojis = partnerRecords.filter { !$0.together }.map { $0.category.emoji }
                if !myEmojis.isEmpty || !partnerEmojis.isEmpty {
                    HStack(spacing: 1) {
                        if !myEmojis.isEmpty {
                            Text(myEmojis.joined())
                                .font(.system(size: 10))
                        }
                        if !partnerEmojis.isEmpty {
                            Text(partnerEmojis.joined())
                                .font(.system(size: 10))
                                .opacity(0.5)
                        }
                    }
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding(2)
        .background(.white)
        .opacity(isCurrentMonth ? 1.0 : 0.3)
        .contentShape(Rectangle())
        .onTapGesture { if isCurrentMonth { onTap() } }
    }

    // dateNumber, dateColor, overeatIndicator, overeatColor는 기존과 동일
}
```

**Step 2: MonthGridView에 파트너/기념일/생일 전달**

```swift
struct MonthGridView: View {
    let monthData: MonthData
    let records: [String: [DailyRecord]]
    let partnerRecords: [String: [DailyRecord]]
    let overeats: [String: OvereatLevel]
    let holidays: [String: [String]]
    let pairEvents: [String: [PairEvent]]
    let birthdayMap: [String: [(emoji: String, label: String)]]
    let onSelectDate: (Date) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0.5), count: 7), spacing: 0.5) {
            ForEach(monthData.cells) { cell in
                let dateStr = cell.date.dateString
                DayCellView(
                    date: cell.date,
                    records: cell.isCurrentMonth ? (records[dateStr] ?? []) : [],
                    partnerRecords: cell.isCurrentMonth ? (partnerRecords[dateStr] ?? []) : [],
                    overeatLevel: cell.isCurrentMonth ? overeats[dateStr] : nil,
                    holidays: cell.isCurrentMonth ? (holidays[dateStr] ?? []) : [],
                    pairEvents: cell.isCurrentMonth ? (pairEvents[dateStr] ?? []) : [],
                    birthdays: cell.isCurrentMonth ? (birthdayMap[dateStr] ?? []) : [],
                    isCurrentMonth: cell.isCurrentMonth,
                    onTap: { onSelectDate(cell.date) }
                )
            }
        }
        .background(Color.slate200.opacity(0.5))
    }
}
```

**Step 3: CalendarView에서 새 프로퍼티 전달**

CalendarView의 MonthGridView 호출 수정 (line 29-38):

```swift
MonthGridView(
    monthData: monthData,
    records: calendarVM.records,
    partnerRecords: calendarVM.partnerRecords,
    overeats: calendarVM.overeats,
    holidays: calendarVM.holidays,
    pairEvents: calendarVM.pairEvents,
    birthdayMap: calendarVM.birthdayMap,
    onSelectDate: { date in
        recordVM.selectedDate = date
        showSheet = true
    }
)
```

그리고 `.task` 블록에서 생일 맵 업데이트:

```swift
.task {
    await calendarVM.initialLoad()
    calendarVM.updateBirthdays(user: authVM.user, pairInfo: calendarVM.pairInfo)
}
```

**Step 4: Commit**

```bash
git add WooriHaru/Views/Calendar/DayCellView.swift WooriHaru/Views/Calendar/MonthGridView.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "feat: 캘린더에 파트너 기록 + 기념일 + 생일 표시"
```

---

## Task 6: RecordSheetView 확장 (파트너 기록 섹션)

**Files:**
- Modify: `WooriHaru/Views/Record/RecordSheetView.swift`
- Modify: `WooriHaru/Views/Record/RecordListView.swift`
- Modify: `WooriHaru/ViewModels/RecordViewModel.swift`

**Step 1: RecordViewModel에 파트너 기록 추가**

RecordViewModel에 파트너 기록 fetch 추가:

```swift
// State 섹션에 추가
var partnerRecords: [DailyRecord] = []
var isPaired: Bool = false
var partnerName: String = ""

// Service 추가
private let pairService = PairService()
```

`loadData()` 끝에 파트너 기록 fetch:

```swift
// 기존 loadData 내부, do 블록 끝에 추가:
if isPaired {
    do {
        partnerRecords = try await pairService.fetchPartnerRecords(date: date)
    } catch {
        partnerRecords = []
    }
}
```

**Step 2: RecordListView를 섹션 분리 지원하도록 수정**

기존 RecordListView를 수정하여 파트너 기록을 표시:

```swift
struct RecordListView: View {
    let records: [DailyRecord]
    let partnerRecords: [DailyRecord]
    let partnerName: String
    let isPaired: Bool
    let onDelete: (DailyRecord) -> Void
    let onTap: (DailyRecord) -> Void

    private var togetherRecords: [DailyRecord] {
        records.filter(\.together) + partnerRecords.filter(\.together)
    }

    private var myRecords: [DailyRecord] {
        records.filter { !$0.together }
    }

    private var partnerSoloRecords: [DailyRecord] {
        partnerRecords.filter { !$0.together }
    }

    var body: some View {
        if records.isEmpty && partnerRecords.isEmpty {
            Text("기록이 없습니다")
                .font(.subheadline)
                .foregroundStyle(Color.slate400)
                .padding(.vertical, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                // Together section (only when paired and has together records)
                if isPaired && !togetherRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("👫 같이 한 것")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.blue600)

                        FlowLayout(spacing: 6) {
                            ForEach(togetherRecords) { record in
                                let isMine = records.contains { $0.id == record.id }
                                RecordPill(record: record, showDelete: isMine, onDelete: { onDelete(record) })
                                    .onTapGesture { if isMine { onTap(record) } }
                                    .opacity(isMine ? 1.0 : 0.7)
                            }
                        }
                    }
                }

                // My records
                if !myRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("나의 기록")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.slate600)

                        FlowLayout(spacing: 6) {
                            ForEach(myRecords) { record in
                                RecordPill(record: record, showDelete: true, onDelete: { onDelete(record) })
                                    .onTapGesture { onTap(record) }
                            }
                        }
                    }
                }

                // Partner records (read-only)
                if isPaired && !partnerSoloRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(partnerName)의 기록")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.slate500)

                        FlowLayout(spacing: 6) {
                            ForEach(partnerSoloRecords) { record in
                                RecordPill(record: record, showDelete: false, onDelete: {})
                                    .opacity(0.7)
                            }
                        }
                    }
                }
            }
        }
    }
}
```

RecordPill에 `showDelete` 파라미터 추가:

```swift
struct RecordPill: View {
    let record: DailyRecord
    let showDelete: Bool
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
                    .foregroundStyle(Color.slate500)
            }
            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red400)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .stroke(Color.slate200, lineWidth: 1)
        }
    }
}
```

**Step 3: RecordSheetView에서 새 프로퍼티 전달**

```swift
RecordListView(
    records: viewModel.records,
    partnerRecords: viewModel.partnerRecords,
    partnerName: viewModel.partnerName,
    isPaired: viewModel.isPaired,
    onDelete: { record in
        Task {
            await viewModel.deleteRecord(record)
            onChanged()
        }
    },
    onTap: { record in
        viewModel.startEditing(record)
    }
)
```

**Step 4: CalendarView에서 RecordViewModel에 페어 정보 전달**

CalendarView의 `.sheet` 수정:

```swift
.sheet(isPresented: $showSheet) {
    RecordSheetView(viewModel: recordVM, onChanged: {
        Task { await calendarVM.refreshMonth(containing: recordVM.selectedDate) }
    })
    .presentationDetents([.fraction(0.7)])
    .presentationDragIndicator(.visible)
    .onAppear {
        recordVM.isPaired = calendarVM.isPaired
        recordVM.partnerName = calendarVM.pairInfo?.partnerName ?? "파트너"
    }
}
```

**Step 5: Commit**

```bash
git add WooriHaru/Views/Record/RecordSheetView.swift WooriHaru/Views/Record/RecordListView.swift WooriHaru/ViewModels/RecordViewModel.swift WooriHaru/Views/Calendar/CalendarView.swift
git commit -m "feat: RecordSheet에 파트너 기록 섹션 추가 (같이/나/파트너 구분)"
```

---

## Task 7: together 토글 지원

**Files:**
- Modify: `WooriHaru/Views/Record/RecordFormView.swift`
- Modify: `WooriHaru/ViewModels/RecordViewModel.swift`

**Step 1: RecordViewModel에 together 상태 추가**

RecordViewModel Form State에 추가:

```swift
var together: Bool = false
```

createRecord/updateRecord의 DailyRecordRequest에서 `together: false` → `together: together`:

```swift
let request = DailyRecordRequest(
    date: dateString,
    categoryId: categoryId,
    memo: memo.isEmpty ? nil : memo,
    together: together
)
```

resetForm에 추가:

```swift
func resetForm() {
    editingRecord = nil
    selectedCategoryId = nil
    memo = ""
    together = false
}
```

startEditing에 추가:

```swift
func startEditing(_ record: DailyRecord) {
    editingRecord = record
    selectedCategoryId = record.category.id
    memo = record.memo ?? ""
    together = record.together
}
```

**Step 2: RecordFormView에 together 토글 추가**

RecordFormView의 HStack(memo + save) 앞에 추가 (페어링 시에만 표시):

```swift
// Together toggle (only when paired)
if viewModel.isPaired {
    Toggle(isOn: $viewModel.together) {
        HStack(spacing: 4) {
            Text("👫")
            Text("같이")
                .font(.caption)
        }
    }
    .toggleStyle(.button)
    .tint(Color.blue500)
}
```

**Step 3: Commit**

```bash
git add WooriHaru/Views/Record/RecordFormView.swift WooriHaru/ViewModels/RecordViewModel.swift
git commit -m "feat: 기록 생성/수정 시 together 토글 지원"
```

---

## Task 8: 최종 통합 및 정리

**Files:**
- 모든 변경 파일 검토

**Step 1: Xcode 빌드 확인**

```bash
xcodebuild -project WooriHaru.xcodeproj -scheme WooriHaru -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

**Step 2: 빌드 에러 수정 (있는 경우)**

빌드 에러가 있으면 수정.

**Step 3: 최종 커밋 및 푸시**

```bash
git add -A
git commit -m "fix: Phase 4 빌드 에러 수정"
git push -u origin feat/phase4-couple-features
```
