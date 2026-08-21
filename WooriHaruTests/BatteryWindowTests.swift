import Foundation
import Testing
@testable import WooriHaru

@Suite("배터리 창")
struct BatteryWindowTests {
    /// **실측 3%만 채워져 있다** — 이것으로 선을 그리면 거의 다 끊긴다.
    @Test func 보조_계열은_대부분_비어_있다() {
        let samples = [
            BatterySample(at: "2026-08-18T15:02:00", batteryLevel: 62, usableBatteryLevel: 61),
            BatterySample(at: "2026-08-18T15:07:00", batteryLevel: 61, usableBatteryLevel: nil),
            BatterySample(at: "2026-08-18T15:12:00", batteryLevel: 60, usableBatteryLevel: nil),
        ]
        // 주 계열은 끊기지 않는다.
        #expect(samples.allSatisfy { $0.batteryLevel > 0 })
        // 보조 계열은 있을 때만 점을 찍는다.
        #expect(samples.compactMap(\.usableBatteryLevel).count == 1)
    }

    /// 0km/시간은 「안 샜다」는 거짓말이다.
    @Test func 표본이_없는_팬텀_드레인은_줄을_감춘다() {
        let drain = ParkDrain(ratedKm: 0, hours: 0, samples: 0)
        #expect(VehicleMath.drainPerHour(drain) == nil)
    }

    @Test func 팬텀_드레인은_뷰가_아니라_여기서_나눈다() {
        let drain = ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6)
        let value = try! #require(VehicleMath.drainPerHour(drain))
        #expect(abs(value - Decimal(string: "0.0435")!) < Decimal(string: "0.001")!)
    }

    /// 시간이 흘러도 뜻이 없는 나눗셈(`hours` 0 이하)은 표본이 있어도 nil이다.
    @Test func 기간이_0이면_나누지_않는다() {
        let drain = ParkDrain(ratedKm: 1.0, hours: 0, samples: 3)
        #expect(VehicleMath.drainPerHour(drain) == nil)
    }

    /// BMS 재보정으로 음수 구간이 와도 부호 그대로 나눈다 — 0으로 뭉개지 않는다.
    @Test func 음수_드레인도_부호_그대로_나눈다() {
        let drain = ParkDrain(ratedKm: Decimal(string: "-2.0")!, hours: 10, samples: 2)
        #expect(VehicleMath.drainPerHour(drain) == Decimal(string: "-0.2")!)
    }

    // MARK: - 디코딩

    /// **시각이 `String`이다** — `APIClient`의 `JSONDecoder()`는 날짜 전략이 없어,
    /// `Date`로 선언하면 응답 전체가 디코딩 실패한다. `charges`는 `TimeSegment`를
    /// 그대로 쓴다 — 다시 정의하지 않는다.
    @Test func 시각_문자열이_그대로_디코딩된다() throws {
        let json = Data("""
        {"hours": 48, "from": "2026-08-18T13:00:00", "to": "2026-08-20T13:00:00",
         "samples": [
            {"at": "2026-08-18T13:00:00", "batteryLevel": 62, "usableBatteryLevel": 61},
            {"at": "2026-08-18T13:05:00", "batteryLevel": 61}
         ],
         "charges": [{"from": "2026-08-19T02:00:00", "to": "2026-08-19T05:00:00"}],
         "parkDrain": {"ratedKm": 4.2, "hours": 96.4, "samples": 6}}
        """.utf8)
        let decoded = try JSONDecoder().decode(BatteryWindowResponse.self, from: json)

        #expect(decoded.hours == 48)
        #expect(decoded.from == "2026-08-18T13:00:00")
        #expect(decoded.to == "2026-08-20T13:00:00")
        #expect(decoded.samples.count == 2)
        #expect(decoded.samples[0].usableBatteryLevel == 61)
        #expect(decoded.samples[1].usableBatteryLevel == nil)
        #expect(decoded.charges.count == 1)
        #expect(decoded.charges[0].from == "2026-08-19T02:00:00")
        #expect(decoded.parkDrain.samples == 6)
    }

    /// 기록이 없으면 `samples`가 빈 배열로 온다 — nil이 아니다.
    @Test func 표본이_없어도_빈_배열로_디코딩된다() throws {
        let json = Data("""
        {"hours": 48, "from": "2026-08-18T13:00:00", "to": "2026-08-20T13:00:00",
         "samples": [], "charges": [], "parkDrain": {"ratedKm": 0, "hours": 0, "samples": 0}}
        """.utf8)
        let decoded = try JSONDecoder().decode(BatteryWindowResponse.self, from: json)
        #expect(decoded.samples.isEmpty)
        #expect(decoded.charges.isEmpty)
        #expect(VehicleMath.drainPerHour(decoded.parkDrain) == nil)
    }

    /// `at`은 5분마다 최대 하나라 시각이 유일하다 — `id`로 그대로 쓸 수 있다.
    @Test func 표본_id는_시각이다() {
        let sample = BatterySample(at: "2026-08-18T15:02:00", batteryLevel: 60, usableBatteryLevel: nil)
        #expect(sample.id == "2026-08-18T15:02:00")
        #expect(sample.date == VehicleFormat.parseKST("2026-08-18T15:02:00"))
    }
}

// MARK: - 서비스

struct VehicleServiceBatteryWindowTests {
    private static func window(hours: Int = 48) -> BatteryWindowResponse {
        BatteryWindowResponse(
            hours: hours, from: "2026-08-18T13:00:00", to: "2026-08-20T13:00:00",
            samples: [BatterySample(at: "2026-08-18T13:00:00", batteryLevel: 62, usableBatteryLevel: 61)],
            charges: [], parkDrain: ParkDrain(ratedKm: 4.2, hours: 96.4, samples: 6))
    }

    /// 기본 `hours`는 48이다.
    @Test func 기본은_48시간을_요청한다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window()))
        let service = VehicleService(api: mock)

        let response = try await service.fetchBatteryWindow()

        #expect(response.hours == 48)
        #expect(mock.getCalls.map(\.path) == ["/tesla/battery-window"])
        #expect(mock.getCalls.first?.query == ["hours": "48"])
    }

    @Test func hours를_질의로_보낸다() async throws {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-window", result: DataResponse(data: Self.window(hours: 24)))
        let service = VehicleService(api: mock)

        _ = try await service.fetchBatteryWindow(hours: 24)

        #expect(mock.getCalls.first?.query == ["hours": "24"])
    }

    /// 서버가 200에 빈 본문을 주면 화면이 「표본 없음」으로 착각하지 않게 에러로 끊는다.
    @Test func 본문이_비면_에러다() async {
        let mock = MockAPIClient()
        mock.stubGet("/tesla/battery-window", result: DataResponse<BatteryWindowResponse>(data: nil))
        let service = VehicleService(api: mock)

        await #expect(throws: (any Error).self) {
            _ = try await service.fetchBatteryWindow()
        }
    }
}
