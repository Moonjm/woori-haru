import SwiftUI

/// 배차 근무 달력. 진입점이고, 오른쪽 위에서 사진 등록으로 들어간다.
struct ScheduleView: View {
    @Binding var navPath: NavigationPath
    @State private var vm = ScheduleViewModel()
    @State private var showPicker = false
    @State private var loadTask: Task<Void, Never>?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            WeekdayHeaderView()

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
                loadTask?.cancel()
                loadTask = Task { await vm.jump(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
        }
        // 첫 등장에서 조회하고, 사진 등록에서 돌아올 때도 다시 조회한다 — `.task`는 뷰가
        // 사라질 때 취소되고 다시 나타날 때 스스로 재실행된다(같은 저장소의
        // `SwimRecordListView`가 그 성질을 전제로 `loadIfNeeded` 가드를 둔 이유다).
        // 별도 트리거를 달면 복귀 때 조회가 두 번 나간다.
        .task { await vm.load() }
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
        loadTask?.cancel()
        loadTask = Task { await vm.move(by: months) }
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await vm.load() }
    }
}
