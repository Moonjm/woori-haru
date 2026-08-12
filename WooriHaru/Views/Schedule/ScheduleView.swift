import SwiftUI

/// 배차 근무 달력. 진입점이고, 오른쪽 위에서 사진 등록으로 들어간다.
struct ScheduleView: View {
    @Binding var navPath: NavigationPath
    /// 사진 등록에서 방금 저장한 연월. `ContentView`가 올려 두면 이 화면이 그 달을 띄우고
    /// 안내를 보인 뒤 스스로 비운다 — 남겨 두면 다음에 이 화면을 다시 들를 때도 같은
    /// 안내가 뜬다.
    @Binding var savedYearMonth: String?
    @State private var vm = ScheduleViewModel()
    @State private var showPicker = false
    @State private var loadTask: Task<Void, Never>?
    /// 저장 직후 한 번 보여줄 안내. 사용자가 달을 옮기면 더는 그 저장을 가리키는 말이
    /// 아니므로 지운다.
    @State private var savedMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            WeekdayHeaderView()

            if let message = savedMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(message).font(.footnote).foregroundStyle(.green)
                    Spacer()
                    Button {
                        savedMessage = nil
                    } label: {
                        Image(systemName: "xmark").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if let message = vm.errorMessage {
                HStack(spacing: 8) {
                    Text(message).font(.footnote).foregroundStyle(.red)
                    Button("다시 시도") { reload() }.font(.footnote)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(vm.cells) { cell in
                    ScheduleDayCellView(
                        date: cell.date,
                        day: cell.day,
                        month: cell.month,
                        isCurrentMonth: cell.isCurrentMonth,
                        holidayNames: cell.isCurrentMonth ? vm.holidayNames(on: cell.date.dateString) : [],
                        badges: cell.isCurrentMonth ? vm.badges(on: cell.date.dateString) : []
                    )
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .navigationTitle("스케줄표")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("사진 등록") { navPath.append(AppDestination.dispatchUpload) }
            }
        }
        .sheet(isPresented: $showPicker) {
            MonthPickerSheet(initialYear: vm.pickerYear, initialMonth: vm.pickerMonth) { year, month in
                savedMessage = nil
                loadTask?.cancel()
                loadTask = Task { await vm.jump(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
        }
        // 첫 등장에서 조회하고, 사진 등록에서 돌아올 때도 다시 조회한다 — `.task`는 뷰가
        // 사라질 때 취소되고 다시 나타날 때 스스로 재실행된다(같은 저장소의
        // `SwimRecordListView`가 그 성질을 전제로 `loadIfNeeded` 가드를 둔 이유다).
        // 별도 트리거를 달면 복귀 때 조회가 두 번 나간다.
        //
        // 저장하고 돌아온 경우엔 보고 있던 달이 아니라 **저장한 달**을 띄운다 — 배차표는
        // 다음 달치를 등록하는 게 정상이라, 그냥 돌아오면 방금 넣은 것이 화면에 없다.
        .task {
            if let target = savedYearMonth {
                savedYearMonth = nil
                await vm.show(yearMonth: target)
                if vm.yearMonth == target {
                    savedMessage = "\(vm.monthLabel) 근무를 저장했습니다."
                }
            } else {
                await vm.load()
            }
        }
        .onDisappear { loadTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").font(.title3).foregroundStyle(Color.slate700)
            }
            .accessibilityLabel("이전 달")

            Button { showPicker = true } label: {
                Text(vm.monthLabel)
                    .font(.title3).fontWeight(.bold).foregroundStyle(Color.slate900)
            }
            .accessibilityHint("연월 선택 열기")

            Button { move(1) } label: {
                Image(systemName: "chevron.right").font(.title3).foregroundStyle(Color.slate700)
            }
            .accessibilityLabel("다음 달")

            Spacer()

            if vm.isLoading { ProgressView() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func move(_ months: Int) {
        savedMessage = nil
        loadTask?.cancel()
        loadTask = Task { await vm.move(by: months) }
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await vm.load() }
    }
}
