import SwiftUI

/// 통계 탭 — 「주행」 섹션(월별 차트 넷 + 온도별 전비·시간대·거리 분포·자주 가는 곳)과
/// 「배터리」 섹션(열화 추세)을 묶는다.
///
/// **`VehicleStatsViewModel`은 `/tesla/insights` 하나만 본다.** 월별 차트까지 한 응답에서
/// 나오므로 기간 칩이 화면 전체에 먹는다. 배터리 열화 추세(`healthViewModel`)와 급속/완속
/// 도넛(`totalsViewModel`)만 예외다 — 둘 다 전 기간을 봐야 하는 값이라 칩과 무관하다.
///
/// **기간 칩은 화면 맨 위 하나다.** 카드마다 기간이 다르면 서로 비교가 안 된다.
/// 충전 탭의 월 스와이프는 여기 걸지 않는다 — 이 탭의 기간 단위는 달이 아니다.
struct VehicleStatsTab: View {
    @Bindable var viewModel: VehicleStatsViewModel
    /// 「배터리」 섹션의 열화 추세만 쓴다. 잔존율 카드는 개요 탭에 남는다.
    @Bindable var healthViewModel: VehicleHealthViewModel
    /// 「충전」 섹션의 급속/완속 도넛에만 쓴다. 전 기간 집계라 기간 칩과 무관하다.
    @Bindable var totalsViewModel: ChargeTotalsViewModel

    @State private var selectedHealthKey: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                periodChips.padding(.top, 8)

                // 값이 남아 있는 새로고침 실패는 한 줄로만 알린다 — 1단계 건강 화면과 같다.
                if let error = viewModel.errorMessage, viewModel.insights != nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // **기간 칩과 무관하다.** 세 값 중 어느 것도 `months` 범위를 따르지 않는다 —
                // 역대 최고는 전 기간이고, 평균 둘은 전 기간을 기록이 있는 달 수로 나눈 값이다.
                // 「이 기간에 주행이 없다」는 이유로 감추면 3개월 범위가 빈 사람에게 전 기간
                // 평균까지 사라진다.
                //
                // **게이트가 「응답을 받았는가」 하나로 줄었다.** 1단계의 `showsStats`는
                // 「서버가 아직 이 필드를 안 낸다」까지 함께 가리던 과도기 장치였는데,
                // `/tesla/insights`에서는 셋이 non-null이라 그쪽 조건은 거짓이 될 수 없다.
                // 남은 것은 아래 `content`와 같은 갈림길뿐이다 — 응답 전에 그리면 로딩
                // 스피너 위에 「—」 셋짜리 카드가 먼저 선다.
                if viewModel.hasLoadedInsights {
                    DriveStatsCard(maxSpeedKmh: viewModel.insights?.maxSpeedKmh,
                                   avgMonthlyKm: viewModel.avgMonthlyKm,
                                   avgYearlyKm: viewModel.avgYearlyKm)
                }

                // **여섯 섹션 순서는 스펙대로 확정이다:** 주행 → 충전 → 주차 → 배터리 →
                // 위치 → 기록. `content`(거리 분포·시간대 히트맵·온도별 전비, 그리고
                // 「이 기간에 주행 기록이 없어요」 안내)는 별도 섹션이 아니라 **「주행」의
                // 나머지 카드 셋이다** — `StatsDriveSection`의 일곱 장과 합쳐 브리프가 세는
                // 「🚗 주행 10장」이 여기서 나온다. 그래서 `StatsChargeSection`보다 먼저,
                // `StatsDriveSection` 바로 뒤에 둔다 — 옮기지 않는다.
                //
                // **헤더를 여기서 낸다.** `StatsDriveSection`(월별 넷, `hasDriveMonths`
                // 게이트)과 `content`(온도별 전비 등, `hasDrives` 게이트)는 각자 다른
                // 소스를 보는 별개 게이트를 유지한다 — 합치지 않는다(`content`의 주석
                // 참고). 그런데 「🚗 주행」 헤더는 그 둘 중 **하나라도 있으면** 서야 해서
                // `viewModel.showsDriveSection`(둘의 OR)으로 딱 한 번만 판단한다. 기간
                // 경계를 걸친 주행 하나만 있는 기간(`hasDrives=true`,
                // `hasDriveMonths=false`)이 실제로 나오는데, 헤더를 `StatsDriveSection`
                // 안에 `hasDriveMonths`로만 걸면 그 기간에 `content`의 카드 셋이 헤더 없이
                // 뜬다.
                if viewModel.showsDriveSection {
                    driveHeader
                }
                StatsDriveSection(viewModel: viewModel)
                content
                StatsChargeSection(viewModel: viewModel, totalsViewModel: totalsViewModel)
                StatsParkSection(viewModel: viewModel)
                batterySection
                StatsPlaceSection(viewModel: viewModel)
                StatsRecordSection(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await viewModel.reload() }
    }

    private var periodChips: some View {
        HStack(spacing: 8) {
            ForEach(DrivePeriod.allCases) { period in
                chip(period)
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(_ period: DrivePeriod) -> some View {
        let selected = viewModel.period == period
        return Button {
            Task { await viewModel.select(period) }
        } label: {
            Text(period.label)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(selected ? VehicleTheme.accentBright : VehicleTheme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule()
                            .fill(VehicleTheme.accent.opacity(0.20))
                            .overlay(Capsule().strokeBorder(VehicleTheme.accent.opacity(0.45), lineWidth: 1))
                    } else {
                        Capsule().fill(VehicleTheme.tileFill)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// `StatsDriveSection`이 예전에 이 헤더를 `hasDriveMonths` 하나로만 걸었던 자리 —
    /// 이제는 `viewModel.showsDriveSection`으로 이 파일에서 낸다(위 호출부 주석 참고).
    private var driveHeader: some View {
        HStack {
            Text("🚗 주행")
                .font(.subheadline)
                .fontWeight(.heavy)
                .foregroundStyle(VehicleTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    /// **네 갈래다** — 못 받음 / 아직 안 받음 / 그 기간에 주행 없음 / 값 있음.
    /// 「기록 없음」과 「못 받음」을 한 화면으로 뭉개지 않는 관례를 따른다.
    @ViewBuilder private var content: some View {
        // 로딩이 오류보다 먼저다 — 기간을 바꾸는 동안 옛 오류를 보여 주면
        // 「못 받음」과 「아직 안 받음」이 뒤바뀐다.
        if viewModel.isLoading && viewModel.insights == nil {
            ProgressView().padding(.top, 60)
        } else if let error = viewModel.errorMessage, viewModel.insights == nil {
            errorState(error).padding(.top, 48)
        } else if !viewModel.hasDrives && !viewModel.hasDriveMonths {
            // **둘 다 거짓일 때만 안내를 띄운다.** `hasDrives`(거리 버킷)와
            // `hasDriveMonths`(월별 값)는 서로 다른 소스를 본다 — 서버 쪽 `distanceBuckets`는
            // `end_date` 기준에 `distance > 0` 필터가 있고, `monthly`는 `start_date` 기준에
            // 그 필터가 없다(서버 DTO 자체 주석: 자정을 걸친 주행만큼 둘의 합이 다를 수
            // 있다). 그래서 「거리 0인 주행만 있는 기간」이면 `hasDriveMonths=true`인데
            // `hasDrives=false`가 되는 모순 조합이 생긴다 — 어느 한쪽만 보고 게이트를
            // 걸면 「🚗 주행」 카드 일곱 장 아래에 「이 기간에 주행 기록이 없어요」가
            // 뜨는 자기모순 화면이 나온다. 둘 다 거짓일 때만 안내를 띄우면 그 조합
            // 자체가 화면에 나올 수 없다.
            //
            // **다음 사람에게:** 이 둘을 하나로 합치고 싶어질 수 있다 — 합치지 않는다.
            // 각자 다른 카드 셋의 게이트다(`hasDrives`는 이 파일의 `content`, `hasDriveMonths`는
            // `StatsDriveSection`의 월별 차트 넷) — 여기서는 「안내문을 띄울지」만 판단할 뿐,
            // 두 섹션의 존재 여부를 대신 정하지 않는다.
            //
            // 카드마다 비우지 않고 화면 하나로 말한다.
            ContentUnavailableView {
                Label("이 기간에 주행 기록이 없어요", systemImage: "car")
            } description: {
                Text("기간을 늘려 보세요")
            }
            .padding(.top, 48)
        } else {
            cards
        }
    }

    @ViewBuilder private var cards: some View {
        // `cars.efficiency`가 없으면 전비를 낼 수 없다. 카드째 감춘다 —
        // 다섯 줄이 전부 「—」인 카드는 자리만 차지한다.
        if viewModel.showsEfficiency {
            TemperatureEfficiencyCard(rows: viewModel.temperatureRows,
                                      driveCount: viewModel.temperatureDriveCount)
        }
        // 거리 카드와 같은 모수(959)를 쓴다 — 전비 카드의 939와는 다르다.
        DriveTimeHeatmap(count: { viewModel.heatCount(weekday: $0, hour: $1) },
                         maxCount: viewModel.maxHeatCount,
                         driveCount: viewModel.distanceDriveCount)
        DistanceDistributionCard(buckets: viewModel.insights?.distanceBuckets ?? [],
                                 driveCount: viewModel.distanceDriveCount)
    }

    /// 열화 추세 — 「지금 어떤가」가 아니라 「어떻게 변해왔나」라 개요가 아니라 여기다.
    /// **기간 칩을 따르지 않는다** — 열화는 전 기간을 봐야 기울기가 보인다.
    ///
    /// **헤더를 단다.** 바로 위가 「🔌 충전」 카드들이라 헤더가 없으면 열화 추세가
    /// 충전 섹션의 다섯째 카드로 읽힌다. 헤더는 내용과 함께만 선다 —
    /// 열화 추세가 없으면 제목만 남은 빈 섹션이 된다.
    @ViewBuilder private var batterySection: some View {
        if !healthViewModel.trendSegments.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Text("🔋 배터리")
                        .font(.subheadline)
                        .fontWeight(.heavy)
                        .foregroundStyle(VehicleTheme.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 4)

                DegradationTrendChart(segments: healthViewModel.trendSegments,
                                      selectedKey: selectedHealthKey,
                                      onSelect: { selectedHealthKey = $0 })
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("주행 인사이트를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(VehicleTheme.background)
        }
    }
}
