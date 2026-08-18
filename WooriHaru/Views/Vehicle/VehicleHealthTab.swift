import SwiftUI

/// 건강 탭 — 미니앱을 열면 **여기가 먼저 뜬다.**
///
/// 뷰모델을 둘 받는다. 배터리 건강(`/tesla/battery-health`)과 현재 상태(`/tesla/status`)는
/// 서로 다른 호출이고, **하나가 실패해도 다른 카드는 그린다.**
struct VehicleHealthTab: View {
    @Bindable var healthViewModel: VehicleHealthViewModel
    @Bindable var statusViewModel: VehicleStatusViewModel
    /// 금액 미등록 큐를 여는 진입점. **입력 경로를 바꾸는 것이 아니라 하나 더 다는 것이다.**
    let onOpenQueue: () -> Void

    @State private var selectedTrendKey: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                // 이 앱에서 사람이 실제로 손을 쓰는 일은 금액을 채우는 것 하나뿐이다.
                // 첫 화면이 바뀌어도 그 일이 한 번의 탭 안에 있어야 한다.
                if healthViewModel.missingCostCount > 0 {
                    missingCostBadge
                }

                healthSection

                statusSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable {
            await healthViewModel.reload()
            await healthViewModel.refreshMissingCount()
            await statusViewModel.reload()
        }
    }

    // MARK: - 기준 시각

    /// **1분마다 다시 그린다.** 경과 시간은 화면을 열어 둔 채로도 흐르는데, 뷰모델의 값만 읽으면
    /// 29분에 연 값이 30분을 넘겨도 「29분 전」에 멈춘 채 강조도 켜지지 않는다.
    private var asOfLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let minutes = statusViewModel.minutesAgo(at: context.date)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(minutes.map { "\(VehicleFormat.relative(minutes: $0)) 기준" } ?? "기준 시각 없음")
                    .fontWeight(.bold)
                if let state = statusViewModel.status?.state {
                    Text("· \(VehicleFormat.stateLabel(state))")
                }
                Spacer()
            }
            .font(.caption)
            // 오래된 값도 값이다. 가리지 않고 시각만 눈에 띄게 한다.
            .foregroundStyle(statusViewModel.isStale(at: context.date) ? Color.orange700 : Color.slate500)
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
            .foregroundStyle(Color.orange700)
            .padding(14)
            .background(Color.orange100, in: RoundedRectangle(cornerRadius: 14))
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
                .foregroundStyle(Color.red500)
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
            DegradationTrendChart(
                segments: healthViewModel.trendSegments,
                selectedKey: selectedTrendKey,
                onSelect: { selectedTrendKey = $0 }
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
        } else if !healthViewModel.hasSamples {
            BatteryHealthPlaceholderCard(
                icon: "bolt.badge.clock",
                title: "아직 잴 만한 충전이 없어요",
                message: "80% 이상 충전하면 값이 쌓여요"
            )
        }
    }

    // MARK: - 현재 상태

    @ViewBuilder private var statusSection: some View {
        // 보여줄 값이 남아 있는 새로고침 실패는 한 줄로만 알린다.
        if let error = statusViewModel.errorMessage, statusViewModel.status != nil {
            Text(error)
                .font(.caption)
                .foregroundStyle(Color.red500)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if statusViewModel.isLoading && statusViewModel.status == nil {
            ProgressView().padding(.top, 40)
        } else if let error = statusViewModel.errorMessage, statusViewModel.status == nil {
            statusErrorState(error).padding(.top, 32)
        } else if let status = statusViewModel.status, statusViewModel.hasRecord {
            batteryCard(status)
            TirePressureCard(tpms: status.tpmsBar)
            cabinCard(status)
        } else if statusViewModel.status != nil {
            // 기록이 아직 없는 것과 못 받은 것은 다르다.
            ContentUnavailableView {
                Label("아직 기록이 없어요", systemImage: "car")
            } description: {
                Text("차가 한 번 깨어나면 값이 쌓여요")
            }
            .padding(.top, 32)
        }
    }

    private func batteryCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                row("배터리", status.batteryLevel.map { level in
                    status.usableBatteryLevel.map { "\(level)% (사용 가능 \($0)%)" } ?? "\(level)%"
                } ?? ChargeFormat.placeholder)
                Divider().padding(.vertical, 8)
                row("주행가능", VehicleFormat.distance(status.ratedRangeKm))
                Divider().padding(.vertical, 8)
                row("주행거리", VehicleFormat.odometer(status.odometerKm))
            }
        }
    }

    /// 온도 둘을 타일로 올린다. **에어컨·위치는 지우지 않고 아래 두 줄로 남긴다** —
    /// 설계 스케치가 노린 것은 온도를 크게 보이게 하는 것이지 나머지를 없애는 것이 아니다.
    private func cabinCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    tile(ChargeFormat.temperature(status.insideTempC), "실내 온도")
                    tile(ChargeFormat.temperature(status.outsideTempC), "외기 온도")
                }
                VStack(spacing: 0) {
                    row("에어컨", status.climateOn.map { $0 ? "켜짐" : "꺼짐" } ?? ChargeFormat.placeholder)
                    Divider().padding(.vertical, 8)
                    row("위치", status.locationName ?? ChargeFormat.placeholder)
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3)
                .fontWeight(.heavy)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.slate100, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.slate500)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
        }
    }

    private func statusErrorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("차량 상태를 불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await statusViewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
