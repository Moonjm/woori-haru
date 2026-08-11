import SwiftUI

/// 일별 점수 추이·평균 섭취량과 목표 대비·자주 먹은 음식.
struct DietStatsView: View {
    @State private var vm = DietStatsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: GlassTokens.cardSpacing) {
                rangePicker

                if vm.loadFailed && vm.stats == nil {
                    failureState
                } else if vm.isEmpty {
                    emptyState
                } else if let stats = vm.stats {
                    summaryCard(stats)
                    trendCard
                    averageCard(stats)
                    topFoodsCard(stats)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .glassScreenBackground()
        .navigationTitle("식단 통계")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
        .overlay { if vm.isLoading && vm.stats == nil { ProgressView() } }
        .alert("오류", isPresented: .init(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var rangePicker: some View {
        Picker("기간", selection: .init(
            get: { vm.range },
            set: { newValue in Task { await vm.select(newValue) } }
        )) {
            ForEach(DietStatsViewModel.Range.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// 통계 조회 자체가 실패한 경우. 알림을 닫아도 "기록 없음"으로 오인되지 않게 따로 띄운다.
    private var failureState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate400)

                Text("통계를 불러오지 못했습니다")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                Button("다시 시도") {
                    Task { await vm.load() }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.blue500)
            }
            .padding(.vertical, 12)
        }
    }

    private var emptyState: some View {
        GlassCard(alignment: .center) {
            VStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .font(.largeTitle)
                    .foregroundStyle(Color.slate300)
                Text("이 기간에 기록한 끼니가 없어요")
                    .font(.subheadline)
                    .foregroundStyle(Color.slate500)
            }
            .padding(.vertical, 20)
        }
    }

    private func summaryCard(_ stats: DietStats) -> some View {
        GlassCard {
            HStack(spacing: 16) {
                DietScoreRing(score: stats.averageDayScore, caption: "평균 점수")

                VStack(alignment: .leading, spacing: 4) {
                    // 평균은 기록한 날로만 낸 값이라 분모를 함께 보여준다.
                    Text(vm.recordedDaysText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.slate700)
                    Text("안 적은 날은 평균에 들어가지 않아요.")
                        .font(.caption2)
                        .foregroundStyle(Color.slate400)
                }

                Spacer()
            }
        }
    }

    /// **x축을 날짜로 배치한다** — 기록한 날만 오므로 인덱스로 그리면 간격이 뭉개진다.
    private var trendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("일별 점수")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                GeometryReader { geometry in
                    ZStack {
                        Path { path in
                            for (index, point) in vm.trendPoints.enumerated() {
                                let position = CGPoint(
                                    x: point.x * geometry.size.width,
                                    y: (1 - point.y) * geometry.size.height
                                )
                                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                        }
                        .stroke(Color.blue500, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                        ForEach(vm.trendPoints, id: \.score.id) { point in
                            Circle()
                                .fill(Color.blue500)
                                .frame(width: 6, height: 6)
                                .position(
                                    x: point.x * geometry.size.width,
                                    y: (1 - point.y) * geometry.size.height
                                )
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }

    private func averageCard(_ stats: DietStats) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("하루 평균")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.slate700)

                if let intake = stats.averageIntake, let targets = stats.averageTargets {
                    HStack {
                        Text("칼로리")
                            .font(.caption)
                            .foregroundStyle(Color.slate500)
                        Spacer()
                        Text("\(Int(intake.kcal.rounded()))kcal / \(targets.kcal)kcal")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.slate700)
                    }

                    MacroBar(name: "탄수화물", intakeG: intake.carbsG, targetG: targets.carbsG)
                    MacroBar(name: "단백질", intakeG: intake.proteinG, targetG: targets.proteinG, tint: .green600)
                    MacroBar(name: "지방", intakeG: intake.fatG, targetG: targets.fatG, tint: .orange400)

                    Divider()

                    MacroBar(name: "당류", intakeG: intake.sugarG, targetG: targets.sugarG, tint: .orange400)
                    MacroBar(name: "나트륨", intakeG: intake.sodiumMg, targetG: targets.sodiumMg, unit: "mg", tint: .orange400)
                    MacroBar(name: "식이섬유", intakeG: intake.fiberG, targetG: targets.fiberG, tint: .green600)
                }
            }
        }
    }

    /// `topFoods`는 `FrequentItem`과 같은 모양이라 같은 컴포넌트를 쓴다.
    private func topFoodsCard(_ stats: DietStats) -> some View {
        GlassCard {
            FrequentItemList(items: stats.topFoods)
        }
    }
}
