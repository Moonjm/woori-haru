import SwiftUI

/// 상태 탭 — 서버 DB에 쌓인 마지막 값. **기준 시각을 값보다 먼저 읽게 둔다.**
struct VehicleStatusTab: View {
    @Bindable var viewModel: VehicleStatusViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                asOfLine.padding(.top, 8)

                // 보여줄 값이 남아 있는 새로고침 실패는 한 줄로만 알린다 — 「기록 없음」과 「못 받음」이
                // 한 화면으로 뭉개지지 않게 한다. 값이 아예 없을 때는 아래 errorState가 맡는다.
                if let error = viewModel.errorMessage, viewModel.status != nil {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.red500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.isLoading && viewModel.status == nil {
                    ProgressView().padding(.top, 60)
                } else if let error = viewModel.errorMessage, viewModel.status == nil {
                    errorState(error).padding(.top, 48)
                } else if let status = viewModel.status, viewModel.hasRecord {
                    batteryCard(status)
                    cabinCard(status)
                    tpmsCard(status)
                } else if viewModel.status != nil {
                    // 기록이 아직 없는 것과 못 받은 것은 다르다.
                    ContentUnavailableView {
                        Label("아직 기록이 없어요", systemImage: "car")
                    } description: {
                        Text("차가 한 번 깨어나면 값이 쌓여요")
                    }
                    .padding(.top, 48)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 110)
        }
        .refreshable { await viewModel.reload() }
    }

    private var asOfLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text(viewModel.minutesAgo.map { "\(VehicleFormat.relative(minutes: $0)) 기준" } ?? "기준 시각 없음")
                .fontWeight(.bold)
            if let state = viewModel.status?.state {
                Text("· \(VehicleFormat.stateLabel(state))")
            }
            Spacer()
        }
        .font(.caption)
        // 오래된 값도 값이다. 가리지 않고 시각만 눈에 띄게 한다.
        .foregroundStyle(viewModel.isStale ? Color.orange700 : Color.slate500)
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

    private func cabinCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(spacing: 0) {
                row("실내 온도", ChargeFormat.temperature(status.insideTempC))
                Divider().padding(.vertical, 8)
                row("외기 온도", ChargeFormat.temperature(status.outsideTempC))
                Divider().padding(.vertical, 8)
                row("에어컨", status.climateOn.map { $0 ? "켜짐" : "꺼짐" } ?? ChargeFormat.placeholder)
                Divider().padding(.vertical, 8)
                row("위치", status.locationName ?? ChargeFormat.placeholder)
            }
        }
    }

    private func tpmsCard(_ status: VehicleStatus) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("타이어 공기압")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.slate500)
                HStack(spacing: 10) {
                    wheel("FL", status.tpmsBar?.fl)
                    wheel("FR", status.tpmsBar?.fr)
                }
                HStack(spacing: 10) {
                    wheel("RL", status.tpmsBar?.rl)
                    wheel("RR", status.tpmsBar?.rr)
                }
            }
        }
    }

    private func wheel(_ label: String, _ bar: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.slate400)
            Text(VehicleFormat.pressureBar(bar))
                .font(.subheadline)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
            Text(VehicleFormat.pressurePsi(bar))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Color.slate400)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
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

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("불러오지 못했어요", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("다시 시도") { Task { await viewModel.reload() } }
                .buttonStyle(.borderedProminent)
        }
    }
}
