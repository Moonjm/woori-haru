import Combine
import SwiftUI

/// 배차 근무 달력. 진입점이고, 오른쪽 위에서 사진 등록으로 들어간다.
struct ScheduleView: View {
    @Binding var navPath: NavigationPath
    /// 사진 등록에서 방금 저장한 연월. `ContentView`가 올려 두면 이 화면이 그 달을 띄우고
    /// 안내를 보인 뒤 스스로 비운다 — 남겨 두면 다음에 이 화면을 다시 들를 때도 같은
    /// 안내가 뜬다.
    @Binding var savedYearMonth: String?
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm = ScheduleViewModel()
    @State private var showPicker = false
    @State private var loadTask: Task<Void, Never>?
    /// 저장 직후 잠깐 뜨는 안내. 스스로 사라진다.
    @State private var savedMessage: String?
    /// 안내를 지울 타이머. **새 저장이 오면 앞의 것을 취소한다** — 남겨 두면 먼저 걸린
    /// 타이머가 방금 띄운 안내를 이른 시각에 지운다.
    @State private var savedMessageTask: Task<Void, Never>?
    /// 편집 시트에 넘길 뷰모델. **날짜가 아니라 뷰모델을 담는다** — 시트가 뜨는 순간의
    /// 근무 값으로 폼을 채워야 하므로, 만들 때 한 번 읽고 그 뒤로는 시트가 홀로 들고 있는다.
    @State private var editing: ScheduleDayEditViewModel?

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
                        day: cell.day,
                        month: cell.month,
                        isCurrentMonth: cell.isCurrentMonth,
                        isToday: vm.isToday(cell.date),
                        holidayNames: cell.isCurrentMonth ? vm.holidayNames(on: cell.date.dateString) : [],
                        badges: cell.isCurrentMonth ? vm.badges(on: cell.date.dateString) : [],
                        isBothOff: cell.isCurrentMonth && vm.isBothOff(on: cell.date.dateString),
                        onTap: { openEditor(for: cell) }
                    )
                }
            }
            .padding(.horizontal, 8)

            legend

            Spacer()
        }
        // **달력 위에 띄우고 자리를 차지하지 않는다.** 줄로 끼워 넣으면 안내가 들고 날
        // 때마다 그리드가 위아래로 밀린다 — 방금 고친 칸을 보려는 순간에 그렇게 된다.
        .overlay(alignment: .bottom) {
            if let message = savedMessage {
                savedToast(message)
            }
        }
        // 빈 자리에서 시작한 스와이프도 받는다. 칸 사이 여백에서만 안 먹으면 손짓이
        // 될 때와 안 될 때가 갈려 고장 난 것처럼 느껴진다.
        .contentShape(Rectangle())
        .gesture(monthSwipe)
        // 좌우 스와이프를 달 이동에 쓰므로 화면 가장자리에서 시작하는 뒤로가기를 끈다.
        // 두 동작이 겹치면 이전 달로 가려던 손짓이 화면을 닫아 버린다.
        .background(SwipeBackDisabler().frame(width: 0, height: 0))
        .navigationTitle("스케줄표")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("사진 등록") { navPath.append(AppDestination.dispatchUpload) }
            }
        }
        .sheet(isPresented: $showPicker) {
            MonthPickerSheet(initialYear: vm.pickerYear, initialMonth: vm.pickerMonth) { year, month in
                dismissSaved()
                loadTask?.cancel()
                loadTask = Task { await vm.jump(year: year, month: month) }
            }
            .presentationDetents([.height(320)])
        }
        .sheet(item: $editing) { editVM in
            ScheduleDayEditSheet(vm: editVM) { days in
                vm.apply(days, on: editVM.date)
                showSaved("\(editVM.dayLabel) 근무를 저장했습니다.")
            }
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
                    showSaved("\(vm.monthLabel) 근무를 저장했습니다.")
                }
            } else {
                await vm.load()
            }
        }
        // **날이 바뀌면 화면에 알려 준다.** 시간이 흐르는 것만으로는 관찰되는 값이 하나도
        // 바뀌지 않아 SwiftUI가 이 화면을 다시 그리지 않는다. 그대로 두면 말일 자정을
        // 넘겨도 「오늘」 버튼이 잠긴 채로 굳고(눌리지 않으니 새 달로 갈 수단이 사라진다),
        // 어제 날짜가 계속 굵게 남는다.
        //
        // 이 알림은 백그라운드 스레드로 온다. 앱이 뒤에 있었으면 앞으로 돌아올 때 온다.
        .onReceive(
            NotificationCenter.default
                .publisher(for: .NSCalendarDayChanged)
                .receive(on: RunLoop.main)
        ) { _ in
            vm.refreshToday()
        }
        // **앞으로 돌아올 때도 맞춘다.** 알림만으로는 뒤에 있는 동안 날이 바뀐 경우가
        // 남는다. 그때 「오늘」 버튼이 잠긴 채로 있으면 탭이 `goToToday()`에 닿지
        // 못해, 버튼 안에 둔 갱신도 함께 막힌다 — 잠긴 버튼은 스스로를 풀 수 없다.
        .onChange(of: scenePhase) {
            if scenePhase == .active { vm.refreshToday() }
        }
        .onDisappear {
            loadTask?.cancel()
            savedMessageTask?.cancel()
        }
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

            // **넣고 빼지 않고 감추기만 한다.** 오른쪽에 「오늘」이 있어서, 스피너가
            // 들고 날 때마다 버튼이 좌우로 밀린다 — 조회는 짧아서 더 눈에 띈다.
            ProgressView().opacity(vm.isLoading ? 1 : 0)

            // **이번 달이어도 감추지 않고 잠그기만 한다.** 같은 이유다.
            Button("오늘") { goToday() }
                .font(.subheadline)
                .disabled(vm.isViewingCurrentMonth)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 저장했다는 것만 알리고 비켜 준다. 닫기 버튼을 두지 않는다 — 스스로 사라지는 것을
    /// 굳이 손으로 닫게 하면 버튼 하나가 늘 자리를 차지한다.
    private func savedToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(message)
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.slate900.opacity(0.9)))
        .padding(.bottom, 24)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 색이 무엇을 뜻하는지 알려 준다. 이 화면은 근무를 글자 없이 색과 자리로만 그리므로,
    /// 처음 보는 사람에게는 분홍과 파랑이 아무 뜻도 아니다.
    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: .pink500, label: "엄마")
            legendItem(color: .blue500, label: "아빠")
            // 옅은 색이라 테두리가 없으면 흰 배경에서 칩이 보이지 않는다.
            legendItem(color: .green100, label: "둘 다 휴무", bordered: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func legendItem(color: Color, label: String, bordered: Bool = false) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 10)
                .overlay {
                    if bordered {
                        RoundedRectangle(cornerRadius: 2).stroke(Color.slate300, lineWidth: 0.5)
                    }
                }
            Text(label).font(.caption).foregroundStyle(Color.slate500)
        }
        .accessibilityElement(children: .combine)
    }

    /// 왼쪽으로 밀면 다음 달, 오른쪽으로 밀면 이전 달. 종이 달력을 넘기는 방향과 같다.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                // 세로로 더 많이 움직였으면 달을 넘기려던 손짓이 아니다.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                move(value.translation.width < 0 ? 1 : -1)
            }
    }

    /// 잠깐 띄우고 스스로 지운다.
    private func showSaved(_ message: String) {
        savedMessageTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { savedMessage = message }
        savedMessageTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { savedMessage = nil }
        }
    }

    /// 달을 옮기면 더는 그 저장을 가리키는 말이 아니다. **타이머도 함께 끈다** —
    /// 남겨 두면 다음 저장의 안내를 그 타이머가 이른 시각에 지운다.
    private func dismissSaved() {
        savedMessageTask?.cancel()
        savedMessageTask = nil
        withAnimation(.easeIn(duration: 0.2)) { savedMessage = nil }
    }

    private func move(_ months: Int) {
        dismissSaved()
        loadTask?.cancel()
        loadTask = Task { await vm.move(by: months) }
    }

    private func goToday() {
        dismissSaved()
        loadTask?.cancel()
        loadTask = Task { await vm.goToToday() }
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { await vm.load() }
    }

    /// **이번 달 칸에서만 연다.** 그리드 앞뒤 패딩(지난달·다음달 날짜)을 고치면 저장한
    /// 결과가 지금 보이는 화면 어디에도 나타나지 않는다.
    ///
    /// 제목의 요일까지 여기서 만든다. 시트가 스스로 계산하면 기기 달력이 비그레고리력일 때
    /// 달력 칸과 시트가 서로 다른 날을 가리킨다.
    private func openEditor(for cell: MonthData.DayCell) {
        guard cell.isCurrentMonth else { return }
        let dateString = cell.date.dateString
        editing = ScheduleDayEditViewModel(
            date: dateString,
            dayLabel: dayLabel(for: cell),
            days: vm.shiftDays(on: dateString),
            holidayNames: vm.holidayNames(on: dateString)
        )
    }

    private func dayLabel(for cell: MonthData.DayCell) -> String {
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let index = Calendar.dispatchGregorian.component(.weekday, from: cell.date) - 1
        return "\(cell.month)월 \(cell.day)일 (\(weekdays[index]))"
    }
}

/// 이 화면이 떠 있는 동안 가장자리 스와이프 뒤로가기를 끈다.
///
/// SwiftUI에는 이 제스처를 끄는 수단이 없어 `UINavigationController`를 직접 만진다.
/// **떠날 때 반드시 되돌린다** — 되돌리지 않으면 이 화면을 한 번 들른 뒤로 앱 전체에서
/// 뒤로가기 스와이프가 죽는다.
private struct SwipeBackDisabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Controller() }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
