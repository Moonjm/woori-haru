import Foundation
import Testing
@testable import WooriHaru

struct VehicleMathTests {
    /// 분모가 없거나 0이면 계산하지 않는다 — 0으로 내면 「0원에 탔다」가 된다.
    @Test func 주행이_없으면_km당_비용도_전비도_없다() {
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: nil) == nil)
        #expect(VehicleMath.costPerKm(cost: 52300, distanceKm: 0) == nil)
        #expect(VehicleMath.costPerKm(cost: nil, distanceKm: 842) == nil)
        // 전비는 충전량으로 나눈다 — 충전이 없으면 낼 수 없다.
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: 0, distanceKm: 842) == nil)
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: nil, distanceKm: 842) == nil)
        #expect(VehicleMath.kmPerKwh(energyAddedKwh: 186, distanceKm: nil) == nil)
    }

    /// 전비 단위는 km/kWh다 — 국내 제원표와 같아야 자기 차 숫자와 견줄 수 있다.
    @Test func km당_비용과_전비를_계산한다() {
        let costPerKm = VehicleMath.costPerKm(cost: 52300, distanceKm: Decimal(string: "842.3"))
        #expect(VehicleFormat.costPerKm(costPerKm) == "₩62/km")

        let efficiency = VehicleMath.kmPerKwh(
            energyAddedKwh: Decimal(string: "186.4"), distanceKm: Decimal(string: "842.3")
        )
        #expect(VehicleFormat.efficiency(efficiency) == "4.5km/kWh")
    }

    /// 지난달이 비면 증감을 내지 않는다 — 0에서 늘었다고 말할 수 없다.
    @Test func 지난달이_비면_증감이_없다() {
        #expect(VehicleMath.deltaPercent(current: 62, previous: nil) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 0) == nil)
        #expect(VehicleMath.deltaPercent(current: 62, previous: 50) == 24)
        #expect(VehicleMath.deltaPercent(current: 40, previous: 50) == -20)
    }

    @Test func bar를_psi로_바꾼다() {
        #expect(VehicleFormat.pressurePsi(Decimal(string: "2.9")) == "42psi")
        #expect(VehicleFormat.pressurePsi(Decimal(string: "2.5")) == "36psi")
        #expect(VehicleFormat.pressurePsi(nil) == "—")
    }

    /// 제안값은 직전 저장 단가 × 이 건의 사용 전력이다. 첫 건은 직전 단가가 없어 제안이 없다.
    @Test func 제안값은_직전_단가에서_나온다() {
        #expect(VehicleMath.suggestedCost(unitPrice: nil, energyUsedKwh: Decimal(string: "51.8")) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: nil) == nil)
        #expect(VehicleMath.suggestedCost(unitPrice: 272, energyUsedKwh: Decimal(string: "51.8")) == 14090)
    }

    @Test func 기준_시각을_상대로_읽는다() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-30), now: now) == 0)
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(-4 * 3600), now: now) == 240)
        // 시계가 어긋나 미래 시각이 와도 음수를 내지 않는다.
        #expect(VehicleMath.minutesAgo(from: now.addingTimeInterval(120), now: now) == 0)

        #expect(VehicleFormat.relative(minutes: 0) == "방금")
        #expect(VehicleFormat.relative(minutes: 45) == "45분 전")
        #expect(VehicleFormat.relative(minutes: 240) == "4시간 전")
        #expect(VehicleFormat.relative(minutes: 2880) == "2일 전")

        // 지속 시간은 하루 안에서 분을 버리지 않는다 — 카드가 1분마다 다시 그려지는데
        // 시간만 남기면 첫 한 시간 뒤로는 그 갱신이 화면에 드러나지 않는다.
        #expect(VehicleFormat.elapsed(minutes: 0) == "방금")
        #expect(VehicleFormat.elapsed(minutes: 45) == "45분째")
        #expect(VehicleFormat.elapsed(minutes: 192) == "3시간 12분째")
        #expect(VehicleFormat.elapsed(minutes: 61) == "1시간 1분째")
        // 딱 떨어지는 시간에는 「0분」을 붙이지 않는다.
        #expect(VehicleFormat.elapsed(minutes: 240) == "4시간째")
        #expect(VehicleFormat.elapsed(minutes: 60) == "1시간째")
        // 하루를 넘기면 다시 날 단위다.
        #expect(VehicleFormat.elapsed(minutes: 2880) == "2일째")
        #expect(VehicleFormat.elapsed(minutes: 1500) == "1일째")
    }

    /// 서버가 주는 `asOf`는 KST 벽시계 값이다. **기기 시간대로 읽으면 안 된다** —
    /// 이 값만은 「지금」과 빼서 경과 시간을 내므로, 한국 밖에서는 시차만큼 어긋나
    /// 늘 「방금 기준」이 되거나 멀쩡한 값이 오래된 것으로 표시된다.
    @Test func 기준_시각은_기기_시간대와_무관하게_KST로_읽는다() {
        let status = VehicleStatus(
            asOf: "2026-08-13T14:02:00", state: nil, stateSince: nil,
            batteryLevel: nil, usableBatteryLevel: nil, ratedRangeKm: nil, estRangeKm: nil,
            odometerKm: nil, insideTempC: nil, outsideTempC: nil, climateOn: nil,
            locationName: nil, tpmsBar: nil
        )
        // 2026-08-13 14:02 KST = 05:02 UTC
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let expected = utc.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 5, minute: 2))!

        #expect(status.asOfDate == expected)
        #expect(VehicleFormat.parseKST("2026-08-13T14:02:00.500") == expected.addingTimeInterval(0.5))
        #expect(VehicleFormat.parseKST("14:02") == nil)
    }

    /// 배터리 추이 카드의 범위 칩이 낡았을 때 실제 기준 시각을 밝히는 데 쓴다. **기기
    /// 시간대와 무관하게 KST로 찍어야** `parseKST`가 KST 벽시계로 읽은 값을 그대로 되돌려
    /// 찍을 수 있다 — 그렇지 않으면 한국 밖 기기에서 시각이 어긋난다.
    @Test func 시각을_KST_HHmm으로_찍는다() {
        let date = VehicleFormat.parseKST("2026-08-20T13:05:00")!
        #expect(VehicleFormat.clockTime(date) == "13:05")
    }

    /// 모르는 상태 문자열은 원문 그대로 낸다 — 상류가 값을 늘렸다는 사실이 숨으면 안 된다.
    @Test func 모르는_상태는_원문을_낸다() {
        #expect(VehicleFormat.stateLabel("asleep") == "잠자는 중")
        #expect(VehicleFormat.stateLabel("driving") == "주행 중")
        #expect(VehicleFormat.stateLabel("hibernating") == "hibernating")
        #expect(VehicleFormat.stateLabel(nil) == "—")
    }

    @Test func 거리를_읽기_좋게_쓴다() {
        #expect(VehicleFormat.distance(Decimal(string: "842.3")) == "842km")
        #expect(VehicleFormat.odometer(Decimal(string: "41203.8")) == "41,204km")
        #expect(VehicleFormat.distance(nil) == "—")
    }

    @Test func 속도는_정수와_단위로_찍는다() {
        #expect(VehicleFormat.speed(138) == "138km/h")
        #expect(VehicleFormat.speed(0) == "0km/h")
        #expect(VehicleFormat.speed(nil) == ChargeFormat.placeholder)
    }

    /// 실측(2026-08-19) 그대로다 — 총 107,257.8km를 기록이 있는 60개월로 나눈다.
    @Test func 월_평균은_기록이_있는_달_수로_나눈다() {
        let monthly = VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 60)
        #expect(VehicleFormat.distance(monthly) == "1,788km")
    }

    @Test func 연_평균은_월_평균의_열두_배다() {
        let total = Decimal(string: "107257.8")
        let monthly = VehicleMath.avgMonthlyDistanceKm(totalKm: total, months: 60)
        let yearly = VehicleMath.avgYearlyDistanceKm(totalKm: total, months: 60)
        #expect(yearly == monthly.map { $0 * 12 })
        #expect(VehicleFormat.distance(yearly) == "21,452km")
    }

    /// **서버는 주행이 없으면 `recordedMonths: 0`을 그대로 낸다**(1로 보정하지 않는다).
    /// 0으로 나누면 화면이 무너지므로 앱이 나누기 전에 막는다.
    @Test func 분모가_0이면_평균이_없다() {
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 0) == nil)
        #expect(VehicleMath.avgYearlyDistanceKm(totalKm: Decimal(string: "107257.8"), months: 0) == nil)
    }

    @Test func 값이_없으면_평균도_없다() {
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: nil, months: 60) == nil)
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: Decimal(string: "100"), months: nil) == nil)
        #expect(VehicleMath.avgYearlyDistanceKm(totalKm: nil, months: nil) == nil)
    }

    @Test func 총거리가_0이면_평균도_0이다() {
        // 0은 「기록이 없다」가 아니라 「안 탔다」다 — nil로 뭉개지 않는다.
        #expect(VehicleMath.avgMonthlyDistanceKm(totalKm: 0, months: 12) == 0)
    }
}
