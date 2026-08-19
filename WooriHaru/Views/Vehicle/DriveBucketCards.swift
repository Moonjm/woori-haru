import SwiftUI

/// 온도별 전비 — 가로 막대. 1단계와 같이 손으로 그린다(Swift Charts를 들이지 않는 관례).
///
/// **막대 길이는 전비에 비례하고, 0에서 시작하지 않는다.** 6.0과 7.6은 26% 차이인데
/// 0부터 그리면 둘 다 긴 막대가 되어 차이가 안 보인다. 가장 낮은 버킷을 짧게 남기고
/// 나머지를 그 위에 얹는다.
struct TemperatureEfficiencyCard: View {
    let rows: [VehicleDriveViewModel.TemperatureRow]
    /// **거리 카드와 다른 수다** — 주행가능거리 소모가 0 이하인 주행이 여기선 빠진다.
    let driveCount: Int

    /// 막대가 아무리 짧아도 이만큼은 남긴다 — 0이면 라벨만 뜬 빈 줄로 보인다.
    private static let minimumRatio: CGFloat = 0.12

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header("온도별 전비", "\(driveCount)회 기준")
                ForEach(rows) { row in
                    bar(row)
                }
                Text("주행가능거리가 준 만큼으로 환산한 값이라 실제 충전량과는 조금 달라요.")
                    .font(.caption2)
                    .foregroundStyle(Color.slate400)
            }
        }
    }

    private var maxValue: Decimal { rows.compactMap(\.kmPerKwh).max() ?? 0 }
    private var minValue: Decimal { rows.compactMap(\.kmPerKwh).min() ?? 0 }

    private func bar(_ row: VehicleDriveViewModel.TemperatureRow) -> some View {
        // 값이 없으면 비율도 없다(nil). 최소 폭(minimumRatio)을 값 없는 버킷에도 적용하면
        // 「—」 옆에 짧은 막대가 남아 「조금 탔다」로 읽힌다 — 그래서 최소 폭은 값이
        // 있는 행에만 건다.
        let ratio: CGFloat? = {
            guard let value = row.kmPerKwh else { return nil }
            guard maxValue > minValue else { return 1 }
            let span = maxValue - minValue
            let scaled = (value - minValue) / span
            let raw = CGFloat(truncating: scaled as NSDecimalNumber)
            return Self.minimumRatio + raw * (1 - Self.minimumRatio)
        }()
        // 가장 좋은 버킷을 진하게 — 「언제가 제일 멀리 가나」가 이 카드의 질문이다.
        let isBest = row.kmPerKwh != nil && row.kmPerKwh == maxValue
        return HStack(spacing: 8) {
            Text(row.bucket.label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .frame(width: 54, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    .fill(isBest ? Color.blue600 : Color.blue300)
                    // 값이 없는 행은 ratio가 nil이라 폭 0 — 막대 자체가 보이지 않는다.
                    .frame(width: ratio.map { max(3, proxy.size.width * $0) } ?? 0)
            }
            .frame(height: 14)
            Text(VehicleFormat.efficiency(row.kmPerKwh))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .frame(width: 74, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.bucket.label) \(VehicleFormat.efficiency(row.kmPerKwh)), \(DriveFormat.count(row.bucket.driveCount))")
    }
}

/// 한 번에 얼마나 — 건수 분포. **여기는 0에서 시작한다.** 건수는 절대량이라
/// 「0~5km가 압도적으로 많다」가 이 카드가 보여 줘야 하는 사실이다.
struct DistanceDistributionCard: View {
    let buckets: [DistanceBucket]
    /// **전비 카드와 다른 수다.** 여기선 걸러 내는 주행이 없다.
    let driveCount: Int

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                header("한 번에 얼마나", "\(driveCount)회 기준")
                ForEach(buckets) { bucket in
                    bar(bucket)
                }
            }
        }
    }

    private var maxCount: Int { buckets.map(\.driveCount).max() ?? 0 }

    private func bar(_ bucket: DistanceBucket) -> some View {
        let ratio = maxCount > 0 ? CGFloat(bucket.driveCount) / CGFloat(maxCount) : 0
        return HStack(spacing: 8) {
            Text(bucket.label)
                .font(.caption2)
                .foregroundStyle(Color.slate500)
                .frame(width: 66, alignment: .leading)
            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: 4)
                    // 0인 버킷도 자리를 지킨다 — 건너뛰면 분포가 어긋나 보인다.
                    .fill(bucket.driveCount == 0 ? Color.slate200 : Color.green600)
                    .frame(width: max(3, proxy.size.width * ratio))
            }
            .frame(height: 14)
            Text(DriveFormat.count(bucket.driveCount))
                .font(.caption2)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(Color.slate900)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bucket.label) \(DriveFormat.count(bucket.driveCount))")
    }
}

/// 두 카드가 같은 머리 모양을 쓴다 — 제목 왼쪽, 모수 오른쪽.
/// **모수를 카드마다 따로 적는다.** 두 카드의 총합이 다르기 때문이다.
private func header(_ title: String, _ trailing: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.slate500)
        Spacer(minLength: 8)
        Text(trailing)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(Color.slate400)
    }
}

#Preview("버킷 카드") {
    let buckets = [
        // **`Decimal`에 부동소수 리터럴을 쓰지 않는다** — Double을 거쳐 값이 틀어진다.
        TemperatureBucket(fromC: nil, toC: 0, driveCount: 82,
                          distanceKm: Decimal(string: "2424.8")!,
                          ratedRangeUsedKm: Decimal(string: "2939.2")!),
        TemperatureBucket(fromC: 0, toC: 10, driveCount: 229,
                          distanceKm: Decimal(string: "6507.3")!,
                          ratedRangeUsedKm: Decimal(string: "7097.1")!),
        TemperatureBucket(fromC: 10, toC: 20, driveCount: 244,
                          distanceKm: Decimal(string: "5990.4")!,
                          ratedRangeUsedKm: Decimal(string: "5723.9")!),
        TemperatureBucket(fromC: 20, toC: 30, driveCount: 266,
                          distanceKm: Decimal(string: "5748.4")!,
                          ratedRangeUsedKm: Decimal(string: "5798.5")!),
        TemperatureBucket(fromC: 30, toC: nil, driveCount: 0,
                          distanceKm: 0, ratedRangeUsedKm: 0),
    ]
    let efficiency = Decimal(string: "0.1367")!
    let rows = buckets.map { bucket in
        VehicleDriveViewModel.TemperatureRow(
            bucket: bucket,
            kmPerKwh: VehicleMath.kmPerKwh(distanceKm: bucket.distanceKm,
                                           ratedRangeUsedKm: bucket.ratedRangeUsedKm,
                                           efficiencyKwhPerKm: efficiency)
        )
    }
    return ScrollView {
        VStack(spacing: 12) {
            TemperatureEfficiencyCard(rows: rows, driveCount: 939)
            DistanceDistributionCard(buckets: [
                DistanceBucket(fromKm: 0, toKm: 5, driveCount: 620, distanceKm: 1802),
                DistanceBucket(fromKm: 5, toKm: 20, driveCount: 210, distanceKm: 2400),
                DistanceBucket(fromKm: 20, toKm: 50, driveCount: 90, distanceKm: 2700),
                DistanceBucket(fromKm: 50, toKm: 100, driveCount: 36, distanceKm: 2500),
                DistanceBucket(fromKm: 100, toKm: nil, driveCount: 3, distanceKm: 412),
            ], driveCount: 959)
        }
        .padding(16)
    }
    .background(Color.slate50)
}
