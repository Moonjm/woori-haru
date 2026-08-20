import SwiftUI

/// 개요 탭 — 미니앱을 열면 **여기가 먼저 뜬다.**
///
/// 뷰모델을 넷 받는다. 배터리 건강(`/tesla/battery-health`)·현재 상태(`/tesla/status`)·
/// 충전 누적·상태 타임라인(`/tesla/state-timeline`)은 서로 다른 호출이고,
/// **하나가 실패해도 다른 카드는 그린다.**
struct VehicleOverviewTab: View {
    @Bindable var healthViewModel: VehicleHealthViewModel
    @Bindable var statusViewModel: VehicleStatusViewModel
    @Bindable var totalsViewModel: ChargeTotalsViewModel
    @Bindable var timelineViewModel: StateTimelineViewModel
    /// 금액 미등록 큐를 여는 진입점. **입력 경로를 바꾸는 것이 아니라 하나 더 다는 것이다.**
    let onOpenQueue: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                // 이 앱에서 사람이 실제로 손을 쓰는 일은 금액을 채우는 것 하나뿐이다.
                // 첫 화면이 바뀌어도 그 일이 한 번의 탭 안에 있어야 한다.
                if healthViewModel.missingCostCount > 0 {
                    missingCostBadge
                }

                // 「지금 어떤가」를 전부 위로 올린다 — 순서가 한 가지 뜻을 갖게 한다.
                // 「지금 → 최근」이 한 방향으로 읽혀야 하므로 타이어·실내는 타임라인 뒤로 뺀다.
                statusSection
                timelineSection
                statusDetailSection

                // 값이 하나도 없는 채로 실패하면 네 「—」만 남아 "아직 로딩 중"과 갈리지 않는다 —
                // 한 줄로 알린다. 값이 있는 새로고침 실패는 조용히 있던 값을 그대로 보여준다.
                if totalsViewModel.totals == nil, let error = totalsViewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ChargeTotalsCard(totals: totalsViewModel.totals,
                                 odometerKm: statusViewModel.status?.odometerKm,
                                 fastWonPerKwh: totalsViewModel.fastWonPerKwh,
                                 slowWonPerKwh: totalsViewModel.slowWonPerKwh)

                healthSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable {
            // 다섯 다 병렬로 부른다 — `healthViewModel.reload()`와 `.refreshMissingCount()`는
            // 같은 뷰모델 인스턴스를 건드리지만 쓰는 값이 겹치지 않는다(`samples`/`isLoaded`/
            // `errorMessage` vs `missingCostCount`). 나머지 셋은 아예 다른 뷰모델이라 무관하다.
            async let health: Void = healthViewModel.reload()
            async let missingCount: Void = healthViewModel.refreshMissingCount()
            async let status: Void = statusViewModel.reload()
            async let totals: Void = totalsViewModel.reload()
            async let timeline: Void = timelineViewModel.reload()
            _ = await (health, missingCount, status, totals, timeline)
        }
    }

    // MARK: - 기준 시각

    /// **1분마다 다시 그린다.** 경과 시간은 화면을 열어 둔 채로도 흐르는데, 뷰모델의 값만 읽으면
    /// 29분에 연 값이 30분을 넘겨도 「29분 전」에 멈춘 채 강조도 켜지지 않는다.
    ///
    /// 상태 글자는 여기 두지 않는다 — 바로 아래 `BatteryNowCard`가 같은 말을 더 크게,
    /// 지속 시간까지 붙여 한다. 둘 다 두면 같은 값이 한 화면에 두 번 뜬다.
    private var asOfLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minutes = statusViewModel.minutesAgo(at: context.date)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(minutes.map { "\(VehicleFormat.relative(minutes: $0)) 기준" } ?? "기준 시각 없음")
                    .fontWeight(.bold)
                Spacer()
            }
            .font(.caption)
            // 오래된 값도 값이다. 가리지 않고 시각만 눈에 띄게 한다.
            .foregroundStyle(statusViewModel.isStale(at: context.date) ? VehicleTheme.warning : VehicleTheme.textSecondary)
        }
    }

    private var missingCostBadge: some View {
        Button(action: onOpenQueue) {
            HStack(spacing: 8) {
                Image(systemName: "wonsign.circle")
                Text("금액 미등록 \(healthViewModel.missingCostCount)건")
                    .fontWeight(.bold)
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(VehicleTheme.warning)
            .padding(14)
            .background(VehicleTheme.warning.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 배터리 건강

    /// **네 갈래다** — 값 있음(+새로고침 실패 시 배너 한 줄) / 못 받았고 값도 없음 / 아직 안 받음 / 표본 없음.
    /// 「기록 없음」과 「못 받음」을 한 화면으로 뭉개지 않는 지금 관례를 따른다.
    /// **있던 값을 새로고침 실패로 지우지 않는다** — 값이 있으면 카드를 그대로 두고, 오류는
    /// `statusSection`과 같은 자리에 같은 모양으로 한 줄만 얹는다.
    @ViewBuilder private var healthSection: some View {
        if let error = healthViewModel.errorMessage, healthViewModel.hasSamples {
            Text(error)
                .font(.caption)
                .foregroundStyle(VehicleTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if healthViewModel.hasSamples {
            BatteryHealthCard(
                remainingPercent: healthViewModel.remainingPercent,
                degradationPercent: healthViewModel.degradationPercent,
                fullRangeKm: healthViewModel.latest?.fullRangeKm,
                capacityKwh: healthViewModel.latestCapacityKwh,
                rangeLostKm: healthViewModel.rangeLostKm
            )
        } else if let error = healthViewModel.errorMessage {
            BatteryHealthPlaceholderCard(
                icon: "exclamationmark.triangle",
                title: "배터리 건강을 불러오지 못했어요",
                message: error,
                retry: { Task { await healthViewModel.reload() } }
            )
        } else if !healthViewModel.isLoaded {
            BatteryHealthPlaceholderCard(
                icon: "bolt.badge.clock",
                title: "불러오는 중",
                message: "충전 기록에서 값을 뽑고 있어요"
            )
        } else {
            // 표본 없음 — 위에서 이미 `hasSamples`·오류·`isLoaded` 갈래를 다 처리했으니
            // 남는 것은 「받았고 오류도 없는데 표본이 비었다」뿐이다.
            BatteryHealthPlaceholderCard(
                icon: "bolt.badge.clock",
                title: "아직 잴 만한 충전이 없어요",
                message: "80% 이상 충전하면 값이 쌓여요"
            )
        }
    }

    // MARK: - 현재 상태

    /// **다섯 갈래다** — 값 있음(+새로고침 실패 시 배너 한 줄) / 응답은 왔는데 기록 없음 /
    /// 불러오는 중 / 못 받음 / 취소된 첫 로드. 마지막 둘이 갈라져 있어야 「다시 시도」가
    /// 눌린 티가 난다.
    @ViewBuilder private var statusSection: some View {
        // 보여줄 값이 남아 있는 새로고침 실패는 한 줄로만 알린다.
        if let error = statusViewModel.errorMessage, statusViewModel.status != nil {
            Text(error)
                .font(.caption)
                .foregroundStyle(VehicleTheme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let status = statusViewModel.status, statusViewModel.hasRecord {
            // 값이 먼저다 — 새로고침이 실패해도 보이던 카드를 오류 화면으로 바꾸지 않는다.
            //
            // **1분마다 다시 그린다.** 「3시간 12분째」는 화면을 열어 둔 채로도 흘러간다 —
            // 기준 시각 줄이 같은 이유로 `TimelineView`를 쓴다.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                BatteryNowCard(status: status,
                               minutesInState: minutesInState(status, at: context.date))
            }
        } else if statusViewModel.status != nil {
            // 응답은 왔는데 위치 기록이 없다 — 못 받은 것과 다르다.
            BatteryNowPlaceholderCard(icon: "car",
                                      title: "아직 기록이 없어요",
                                      message: "차가 한 번 깨어나면 값이 쌓여요")
        } else if statusViewModel.isLoading {
            // **로딩이 오류보다 먼저다.** 재시도를 눌렀는데 오류 패널이 그대로 서 있으면
            // 누른 것이 먹혔는지 알 길이 없다 — `errorMessage`는 다음 성공까지 남는다.
            // 통계 탭이 같은 이유로 같은 순서를 쓴다.
            BatteryNowPlaceholderCard(icon: "car",
                                      title: "불러오는 중",
                                      message: "차량 상태를 받고 있어요")
        } else if let error = statusViewModel.errorMessage {
            BatteryNowPlaceholderCard(icon: "exclamationmark.triangle",
                                      title: "차량 상태를 불러오지 못했어요",
                                      message: error,
                                      retry: { Task { await statusViewModel.reload() } })
        } else {
            // 취소된 첫 로드는 값도 오류도 없이 끝난다(CancellationError는 조용히 리턴한다).
            // 주인공 자리를 비우지 않는다.
            BatteryNowPlaceholderCard(icon: "car",
                                      title: "불러오는 중",
                                      message: "차량 상태를 받고 있어요")
        }
    }

    /// 타이어·실내는 **값이 있을 때만** 선다 — 주인공 패널이 플레이스홀더로 서 있는데
    /// 그 아래에 빈 카드 둘이 남으면 「못 받았다」는 말이 흐려진다.
    @ViewBuilder private var statusDetailSection: some View {
        if let status = statusViewModel.status, statusViewModel.hasRecord {
            TirePressureCard(tpms: status.tpmsBar)
            cabinCard(status)
        }
    }

    /// `stateSince`부터 흐른 분. **KST로 읽는다** — 서버가 KST 벽시계 값을 주는데
    /// 기기 시간대로 읽으면 시차만큼 어긋난다. `asOf`와 같은 이유다.
    private func minutesInState(_ status: VehicleStatus, at date: Date) -> Int? {
        guard let since = status.stateSince.flatMap(VehicleFormat.parseKST) else { return nil }
        return VehicleMath.minutesAgo(from: since, now: date)
    }

    // MARK: - 최근 24시간

    /// **다섯으로 갈린다** — 값 있음(+새로고침 실패 시 배너 한 줄) / 기록 없음 /
    /// 불러오는 중 / 못 받음 / 아직 안 받음(아무것도 안 그린다).
    ///
    /// `statusSection`과 같은 순서를 쓴다 — **로딩이 오류보다 먼저다.** 「다시 시도」를
    /// 눌러도 `errorMessage`는 다음 성공까지 남으므로, 로딩 갈래가 없으면 오류 카드가
    /// 그대로 서 있어 누른 것이 먹혔는지 알 수 없다.
    ///
    /// 로딩 갈래는 **오류를 한 번 띄운 뒤의 재시도에만** 선다. 첫 로드에는 이 절이 아무것도
    /// 그리지 않는 편이 맞다 — 그때는 위 진한 패널이 이미 「불러오는 중」을 말하고 있어
    /// 스피너가 둘이면 화면이 시끄럽다. 이 절은 **할 말이 생기기 전까지 자리를 차지하지 않고,**
    /// 한 번 문제를 말한 뒤에는 그 자리에서 진행 상황까지 말한다.
    ///
    /// `from`·`to`를 못 읽으면 비율을 낼 수 없어 첫 갈래에 못 든다. 그때는 아래 갈래로 흘러가
    /// **오류가 없는 한 아무것도 그리지 않는다** — 「못 받음」으로 승격시키지 않는다.
    @ViewBuilder private var timelineSection: some View {
        if let timeline = timelineViewModel.timeline,
           let from = VehicleFormat.parseKST(timeline.from),
           let to = VehicleFormat.parseKST(timeline.to) {
            if let error = timelineViewModel.errorMessage {
                // 값이 있는 새로고침 실패는 띠를 그대로 두고 한 줄만 알린다.
                Text(error)
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if timelineViewModel.hasSegments {
                StateTimelineChart(bars: timelineViewModel.bars,
                                   from: from, to: to)
            } else {
                GlassCard {
                    Text("최근 \(StateTimelineMath.hours(from: from, to: to))시간 기록이 없어요")
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if timelineViewModel.isLoading, timelineViewModel.errorMessage != nil {
            // **로딩이 오류보다 먼저다.** `errorMessage`는 다음 성공까지 남으므로, 이 갈래가
            // 없으면 「다시 시도」를 눌러도 오류 카드가 그대로 서 있어 눌린 티가 안 난다.
            // 오류 카드와 같은 자리·같은 어휘로 선다.
            GlassCard {
                Text("불러오는 중")
                    .font(.caption)
                    .foregroundStyle(VehicleTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let error = timelineViewModel.errorMessage {
            GlassCard {
                HStack(spacing: 8) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(VehicleTheme.textSecondary)
                    Spacer(minLength: 8)
                    Button("다시 시도") { Task { await timelineViewModel.reload() } }
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }
        }
        // 값도 오류도 없으면(첫 로드 중이거나, 취소돼 끝났거나, 서버에 아직 이 경로가
        // 없으면) 아무것도 그리지 않는다 — 위 진한 패널이 이미 「불러오는 중」을 말한다.
    }

    /// 온도 둘을 타일로 올린다. 1단계에서는 **위치를 여기 말고 보여줄 데가 없어서** 아래 줄로
    /// 남겼지만, 4단계에서 위치는 `BatteryNowCard`로 올라갔다 — 같은 값을 한 화면에 두 번 두지
    /// 않는다. 에어컨만 온도 타일 아래 남는다.
    private func cabinCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tile(ChargeFormat.temperature(status.insideTempC), "실내 온도")
                    tile(ChargeFormat.temperature(status.outsideTempC), "외기 온도")
                }
                row("에어컨", status.climateOn.map { $0 ? "켜짐" : "꺼짐" } ?? ChargeFormat.placeholder)
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(VehicleTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(VehicleTheme.tileFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(VehicleTheme.textSecondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(VehicleTheme.textPrimary)
        }
    }
}
