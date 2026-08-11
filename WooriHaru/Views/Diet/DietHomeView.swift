import SwiftUI

/// 식단 진입점 — 주간 날짜 스트립 + 하루 요약 카드 + 끼니 목록 + 추가 버튼.
struct DietHomeView: View {
    @State private var vm = DietDayViewModel()
    @State private var showProfile = false
    @State private var showStats = false
    @State private var showWeightSheet = false
    @State private var weightText = ""
    @State private var showCapture = false
    @State private var showManualEntry = false
    @State private var showChat = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                weekStrip

                if vm.loadFailed && vm.day == nil {
                    failureState
                } else {
                    summaryCard

                    // 하루 점수에도 같은 카드를 쓴다 — 칼로리 항목이 하나 더 붙는다.
                    if let basis = vm.day?.scoreBasis {
                        ScoreBasisCard(title: "하루 점수", score: vm.day?.dayScore, dayBasis: basis)
                    }

                    mealList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            // 플로팅 버튼이 맨 아래 카드를 덮지 않을 만큼 띄운다(버튼 ~50 + 여백 12).
            .padding(.bottom, 76)
        }
        .glassScreenBackground()
        .overlay {
            // 최초 조회가 끝나기 전에는 아무 카드도 "판정"처럼 보이면 안 된다 — 스피너만 띄운다.
            if vm.isLoading && vm.day == nil {
                ProgressView()
            }
        }
        .overlay(alignment: .bottomTrailing) { chatButton }
        .navigationTitle("식단")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showProfile) {
            NutritionProfileView { Task { await vm.reload() } }
        }
        .navigationDestination(isPresented: $showStats) {
            DietStatsView()
        }
        .navigationDestination(for: Int.self) { mealId in
            MealDetailView(mealId: mealId) { Task { await vm.reload() } }
        }
        .navigationDestination(isPresented: $showChat) {
            // **보고 있던 날짜가 그대로 앵커다.** 하루도 함께 넘겨 칩·잠금 판단에 새 호출이
            // 들지 않게 한다.
            DietChatView(anchorDate: vm.selectedDate, day: vm.day)
        }
        .sheet(isPresented: $showWeightSheet) { weightSheet }
        .sheet(isPresented: $showCapture) {
            MealCaptureSheet(date: vm.selectedDate) { _ in
                Task { await vm.reload() }
            }
        }
        .sheet(isPresented: $showManualEntry) {
            // 사진 없는 기록 — `MealConfirmView`를 그대로 재사용한다. `PhotoStrip`만 그릴 게 없다.
            // **끼니는 넘기지 않는다** — 기본값을 박으면 그대로 저장된다.
            NavigationStack {
                MealConfirmView(date: vm.selectedDate, mealType: nil, analysis: nil) { _ in
                    showManualEntry = false
                    Task { await vm.reload() }
                }
            }
        }
        .task {
            // **활동량을 먼저 올린다.** 하루 조회가 서버의 하루 피드백 생성을 걸어 놓는데,
            // 활동량 업서트는 그 캐시를 무효화하지 않는다 — 순서가 뒤면 그날 피드백이 소모
            // 칼로리를 빠뜨린 채로 굳는다(`DietDayViewModel.select(_:)`도 같은 순서다).
            await vm.syncActivity()
            await vm.load()
            // 목표가 없으면 점수를 낼 수 없으므로 프로필 입력이 먼저다.
            if vm.needsProfile { showProfile = true }
        }
        .refreshable { await vm.reload() }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: - 코치 채팅

    /// 오른쪽 아래 플로팅 버튼. **`overlay`에 얹는다** — 스크롤과 무관하게 늘 같은 자리다.
    ///
    /// **프로필이 없으면 띄우지 않는다.** 점수도 총평도 없어 코치가 답할 근거가 없고,
    /// 툴바가 이미 「목표부터 정하기」로 한 길만 열어 두고 있다.
    ///
    /// **자격이 확인됐을 때만 띄운다.** 조회 전에도, 조회가 실패해 모르는 상태에서도 띄우지
    /// 않는다 — 「없다」와 「모른다」를 같은 값으로 두면 프로필 없는 사용자에게도 버튼이
    /// 잠깐 떴다 사라진다.
    @ViewBuilder
    private var chatButton: some View {
        if vm.profileEligibility == .eligible {
            Button {
                showChat = true
            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.title3)
                    .padding(14)
            }
            .appGlassProminentButton()
            .clipShape(Circle())
            .padding(.trailing, 20)
            .padding(.bottom, 12)
            .accessibilityLabel("식단 코치")
        }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 시스템 뒤로 가기 버튼을 숨기면 **화면 가장자리 스와이프 뒤로 가기도 같이 꺼진다.**
        // 그게 목적이다 — 날짜 스트립의 좌우 스와이프와 겹쳐서 주를 넘기려다 화면이 뒤로
        // 나가 버린다. 나갈 길은 있어야 하므로 같은 자리에 같은 모양의 버튼을 직접 둔다.
        // **이 화면에서만 끈다** — 여기서 밀고 들어간 끼니 상세·통계·프로필은 그대로 스와이프로 나온다.
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
            }
            .accessibilityLabel("뒤로")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showProfile = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("식단 프로필")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showStats = true
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
            }
            .accessibilityLabel("식단 통계")
        }
        ToolbarItem(placement: .bottomBar) {
            // **프로필이 없으면 기록을 시작조차 시키지 않는다.** 서버가 확정을 거절하는데,
            // 그 사실이 인식이 다 끝난 뒤에야 드러나면 사용자는 기다린 시간을 버리고 LLM
            // 비용은 이미 나간 뒤다. 프로필 화면을 저장 없이 닫아도 여기로 다시 온다.
            //
            // **「모른다」를 「있다」로 읽지 않는다.** 조회 전이거나 프로필 조회가 실패하면
            // 자격이 `.unknown`인데, 그때 「끼니 추가」를 띄우면 위의 방어가 통째로 새어
            // 사용자가 유료 인식을 다 하고 확정에서 거절된다.
            //
            // **그렇다고 「목표부터 정하기」를 띄우지도 않는다** — 프로필이 있는 사용자에게
            // 거짓말이 된다. 조회가 끝난 뒤에도 모르면 확인하러 갈 길만 연다.
            switch vm.profileEligibility {
            case .unknown where !vm.hasLoaded:
                EmptyView()
            case .unknown:
                Button {
                    showProfile = true
                } label: {
                    Label("목표 확인하기", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.headline)
                }
            case .missing:
                Button {
                    showProfile = true
                } label: {
                    Label("목표부터 정하기", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.headline)
                }
            case .eligible:
                Menu {
                    Button {
                        showCapture = true
                    } label: {
                        Label("사진으로 추가", systemImage: "camera")
                    }
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("직접 추가", systemImage: "square.and.pencil")
                    }
                } label: {
                    Label("끼니 추가", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - 날짜 스트립

    private var weekStrip: some View {
        VStack(spacing: 6) {
            HStack {
                Text(vm.visibleMonthText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.slate500)

                Spacer()

                // 몇 주를 넘긴 뒤 돌아올 길. 보이는 주에 선택 날짜가 있으면 필요 없다.
                if !vm.isViewingSelectedWeek {
                    Button("오늘") {
                        Task { await vm.goToToday() }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.blue500)
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 4) {
                ForEach(vm.weekDates, id: \.timeIntervalSince1970) { date in
                    let isSelected = Calendar.current.isDate(date, inSameDayAs: vm.selectedDate)
                    Button {
                        Task { await vm.select(date) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(weekdayText(date))
                                .font(.caption2)
                                .foregroundStyle(Color.slate400)
                            Text("\(date.day)")
                                .font(.subheadline.weight(isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? .white : Color.slate700)
                                .frame(width: 32, height: 32)
                                .background(isSelected ? Color.blue500 : .clear, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // 빈 곳에서 시작한 스와이프도 받아야 한다 — 날짜 버튼 사이 여백이 넓다.
        .contentShape(Rectangle())
        // `.gesture`는 배타적이라 이 스트립 위에서 시작한 세로 드래그를 통째로 가져가 버려
        // 화면 최상단에서 바깥 `ScrollView`의 세로 스크롤이 죽는다. `LedgerView.monthSwipeGesture`·
        // `LedgerStatsView.periodSwipeGesture`·`CalendarView`가 같은 문제를 이미
        // `.simultaneousGesture`로 풀고 있어 그 관례를 따른다 — 세로 스크롤과 동시에 인식되다가
        // 가로 판정 조건을 만족할 때만 주를 넘긴다.
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // `minimumDistance`(30, 위)는 제스처 인식이 시작되는 지점이고, 아래 50pt는
                    // 그렇게 인식된 드래그를 "주 넘김"으로 확정하는 별도의 판정 기준이다 — 역할이
                    // 다른 두 숫자다. 세로 이동의 1.5배보다 가로 이동이 커야 하므로(대각선 배제)
                    // 가로가 세로의 1.5배를 넘어야 하므로 약 34°보다 기운 드래그는 주 넘김이 아니다.
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > 50, abs(dx) > abs(dy) * 1.5 else { return }
                    if dx < 0 {
                        vm.showNextWeek()
                    } else {
                        vm.showPreviousWeek()
                    }
                }
        )
    }

    private func weekdayText(_ date: Date) -> String {
        ["일", "월", "화", "수", "목", "금", "토"][date.weekday - 1]
    }

    // MARK: - 하루 요약

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 16) {
                    DietScoreRing(score: vm.day?.dayScore, caption: "하루 점수")

                    VStack(alignment: .leading, spacing: 8) {
                        if let profile = vm.profile, let day = vm.day {
                            MacroBar(name: "탄수화물", intakeG: day.carbsG, targetG: profile.targetCarbsG)
                            MacroBar(name: "단백질", intakeG: day.proteinG, targetG: profile.targetProteinG, tint: .green600)
                            MacroBar(name: "지방", intakeG: day.fatG, targetG: profile.targetFatG, tint: .orange400)
                        }
                    }
                }

                energyRow
                Divider()
                nutrientLimitSection
                Divider()
                feedbackSection
            }
        }
    }

    /// 활동 에너지는 **목표 칼로리에 반영하지 않는다** — 보조 표시일 뿐이다.
    private var energyRow: some View {
        HStack {
            Text("섭취 \(Int((vm.day?.totalKcal ?? 0).rounded()))kcal")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.slate700)
            if let burned = vm.day?.activeEnergyKcal {
                Text("/ 소모 \(burned)kcal")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
            Spacer()
            Button {
                weightText = vm.profile.map { $0.weightKg.trimmedText } ?? ""
                showWeightSheet = true
            } label: {
                Label(vm.profile.map { "\(String(format: "%.1f", $0.weightKg))kg" } ?? "몸무게", systemImage: "scalemass")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.blue500)
        }
    }

    /// **점수 링 옆이 아니라 별도 줄이다** — 주의 영양소는 점수에 들어가지 않는다.
    @ViewBuilder
    private var nutrientLimitSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.day?.nutrientLimits ?? []) { NutrientLimitRow(limit: $0) }

            // 값이 0이면 아무것도 그리지 않는다 — 항목 단위 「추정」 배지와 달리 없음이 기본이다.
            if let notice = vm.estimatedNoticeText {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    /// 피드백이 안 와도 **재시도 버튼을 두지 않는다** — 끼니를 추가·수정하면 자연히 다시 만들어진다.
    @ViewBuilder
    private var feedbackSection: some View {
        if let feedback = vm.day?.feedback {
            Text(feedback)
                .font(.footnote)
                .foregroundStyle(Color.slate700)
                .fixedSize(horizontal: false, vertical: true)
        } else if vm.isFeedbackPending {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("마감 피드백을 만들고 있어요")
                    .font(.caption)
                    .foregroundStyle(Color.slate400)
            }
        } else if vm.isFeedbackDelayed {
            Text("피드백 생성이 지연되고 있어요. 잠시 후 다시 확인해 주세요.")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        } else if vm.hasLoaded && !vm.loadFailed && vm.meals.isEmpty {
            // 조회가 실패했거나(loadFailed) 아직 끝나지 않았을 때는(!hasLoaded) 이 문구를
            // 보여주지 않는다 — 그러면 "기록 없음"과 "조회 실패/로딩 중"이 뒤섞여 보인다.
            Text("아직 기록한 끼니가 없어요.")
                .font(.caption)
                .foregroundStyle(Color.slate400)
        }
    }

    // MARK: - 조회 실패

    /// 하루 조회 자체가 실패한 경우. 알림을 닫아도 "기록 없음"으로 오인되지 않게 따로 띄운다.
    private var failureState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate400)

                Text("하루 기록을 불러오지 못했습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                Button("다시 시도") {
                    Task { await vm.reload() }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.blue500)
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - 끼니 목록

    /// 서버가 아침→점심→저녁→간식 순으로 주므로 **다시 정렬하지 않는다.**
    private var mealList: some View {
        VStack(spacing: 12) {
            ForEach(vm.meals) { meal in
                NavigationLink(value: meal.id) {
                    GlassCard {
                        HStack(spacing: 12) {
                            Image(systemName: meal.mealType.iconName)
                                .foregroundStyle(Color.blue500)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.mealType.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.slate700)
                                Text(meal.items.map(\.foodName).joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(Color.slate400)
                                    .lineLimit(1)
                            }
                            Spacer()
                            DietScoreRing(score: meal.score, size: 44)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 몸무게 시트

    private var isWeightInRange: Bool {
        guard let weight = Double(weightText) else { return false }
        return NutritionProfileLimits.weightKg.contains(weight)
    }

    /// 몸무게만 고친다. **과거 점수는 바뀌지 않는다** — 서버가 끼니마다 스냅샷을 남긴다.
    private var weightSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text("kg").foregroundStyle(Color.slate400)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassInputField()

                // 범위 밖이면 저장 버튼이 꺼지므로 왜 꺼졌는지 알려 준다 — 안 알려 주면
                // 눌리지 않는 버튼만 남는다.
                if !isWeightInRange, !weightText.isEmpty {
                    Text(NutritionProfileLimits.weightHint)
                        .font(.caption2)
                        .foregroundStyle(Color.orange400)
                }

                Text("몸무게를 고쳐도 지난 기록의 점수는 바뀌지 않아요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)

                Spacer()
            }
            .padding(16)
            .glassScreenBackground()
            .navigationTitle("몸무게")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { showWeightSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        // **서버가 받아 주는 범위 안일 때만 보낸다.** 밖의 값은 400으로
                        // 돌아오는데 그때는 시트가 이미 닫힌 뒤라 고칠 자리를 잃는다.
                        guard let weight = Double(weightText),
                              NutritionProfileLimits.weightKg.contains(weight) else { return }
                        showWeightSheet = false
                        Task {
                            // **성공했을 때만 재조회한다.** 실패해도 재조회하면 `load()`가
                            // 시작하자마자 오류 메시지를 지워서, 이미 닫힌 시트 뒤로 「저장이
                            // 안 됐다」는 사실이 아무 데도 안 남는다.
                            if await vm.updateWeight(weight) {
                                await vm.reload()
                            }
                        }
                    }
                    .disabled(!isWeightInRange)
                }
            }
        }
        .presentationDetents([.height(240)])
    }
}
