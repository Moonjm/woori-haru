import SwiftUI

/// 통계 탭 — 온도별 전비·시간대·거리 분포·자주 가는 곳. 네 카드가 **한 응답**에서 나온다.
///
/// **기간 칩은 화면 맨 위 하나다.** 카드마다 기간이 다르면 서로 비교가 안 된다.
/// 충전 탭의 월 스와이프는 여기 걸지 않는다 — 이 탭의 기간 단위는 달이 아니다.
struct VehicleStatsTab: View {
    @Bindable var viewModel: VehicleStatsViewModel

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
                if viewModel.showsStats {
                    DriveStatsCard(maxSpeedKmh: viewModel.insights?.maxSpeedKmh,
                                   avgMonthlyKm: viewModel.avgMonthlyKm,
                                   avgYearlyKm: viewModel.avgYearlyKm)
                }

                content
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

    /// **네 갈래다** — 못 받음 / 아직 안 받음 / 그 기간에 주행 없음 / 값 있음.
    /// 「기록 없음」과 「못 받음」을 한 화면으로 뭉개지 않는 관례를 따른다.
    @ViewBuilder private var content: some View {
        // 로딩이 오류보다 먼저다 — 기간을 바꾸는 동안 옛 오류를 보여 주면
        // 「못 받음」과 「아직 안 받음」이 뒤바뀐다.
        if viewModel.isLoading && viewModel.insights == nil {
            ProgressView().padding(.top, 60)
        } else if let error = viewModel.errorMessage, viewModel.insights == nil {
            errorState(error).padding(.top, 48)
        } else if !viewModel.hasDrives {
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
        // **지오펜스가 없는 것이 이 차량의 기본 상태다**(`geofences` 0행). 등록하기
        // 전까지 이 카드는 늘 감춰진다 — 「가끔 비는 경우」가 아니다.
        if viewModel.showsPlaces {
            placesCard
        }
    }

    private var placesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("자주 가는 곳")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(VehicleTheme.textSecondary)
                // 서버가 지오펜스 id로 묶어 같은 이름이 둘 올 수 있는데 응답에는 id가
                // 없다 — 위치로 아이디를 삼는다. 서버 랭킹 그대로인 읽기 전용 목록이라
                // (건수 내림차순 상위 10개) 선택·애니메이션 상태가 없어 위치가 안전하다.
                ForEach(Array((viewModel.insights?.places ?? []).enumerated()), id: \.offset) { _, place in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // **이름만 낸다** — 주소는 서버가 싣지 않는다.
                        Text(place.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(VehicleTheme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(DriveFormat.count(place.driveCount))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textSecondary)
                        Text(VehicleFormat.distance(place.distanceKm))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(VehicleTheme.textTertiary)
                            .frame(width: 66, alignment: .trailing)
                    }
                }
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
