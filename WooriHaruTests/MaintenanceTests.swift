import Foundation
import Testing
@testable import WooriHaru

struct MaintenanceModelTests {
    /// 서버 `BillResponse`를 그대로 옮긴 응답. 필드가 하나라도 어긋나면 디코딩이 깨진다.
    static let billJSON = """
    {
      "data": {
        "yearMonth": "2026-08",
        "dong": "101",
        "ho": "1502",
        "areaM2": 84.97,
        "items": [
          { "name": "일반관리비", "amount": 121500 },
          { "name": "세대전기료", "amount": 48320 }
        ],
        "usage": {
          "electricityKwh": 312.5,
          "waterM3": 14.2,
          "hotWaterM3": null,
          "heatingGcal": null,
          "foodKg": 8.4
        },
        "chargedAmount": 169820,
        "discountTotal": 1200,
        "unpaidAmount": 0,
        "unpaidLateFee": 0,
        "dueAmount": 168620,
        "dueDate": "2026-08-31"
      }
    }
    """

    @Test func 한_달_관리비를_디코딩한다() throws {
        let data = Data(Self.billJSON.utf8)
        let response = try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: data)
        let bill = try #require(response.data)

        #expect(bill.yearMonth == "2026-08")
        #expect(bill.items.count == 2)
        #expect(bill.items[0].amount == Decimal(121500))
        #expect(bill.dueAmount == Decimal(168620))
        #expect(bill.dueDate == "2026-08-31")
    }

    /// 못 읽은 사용량은 **0이 아니라 nil이다.** 0으로 접히면 통계에서
    /// 「안 쓴 달」과 「못 읽은 달」이 같은 막대가 된다.
    @Test func 없는_사용량은_nil로_남는다() throws {
        let data = Data(Self.billJSON.utf8)
        let bill = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: data).data
        )
        let usage = try #require(bill.usage)

        #expect(usage.electricityKwh == Decimal(string: "312.5"))
        #expect(usage.hotWaterM3 == nil)
        #expect(usage.heatingGcal == nil)
    }

    /// `usage` 키가 통째로 빠진 응답에도 나머지가 살아야 한다 — 한 달이 디코딩을
    /// 깨뜨리면 목록 화면 전체가 빈다.
    @Test func usage가_없어도_디코딩된다() throws {
        let json = """
        {
          "data": {
            "yearMonth": "2026-07",
            "dong": null, "ho": null, "areaM2": null,
            "items": [{ "name": "일반관리비", "amount": 100 }],
            "chargedAmount": 100, "discountTotal": 0,
            "unpaidAmount": 0, "unpaidLateFee": 0,
            "dueAmount": 100, "dueDate": null
          }
        }
        """
        let bill = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBill>.self, from: Data(json.utf8)).data
        )
        #expect(bill.usage == nil)
        #expect(bill.dueDate == nil)
    }

    /// 인식 결과는 `yearMonth`가 **옵셔널**이다 — 고지서 제목이 잘리면 서버가 못 읽는다.
    @Test func 인식_결과를_디코딩한다() throws {
        let json = """
        {
          "data": {
            "yearMonth": null,
            "dong": "101", "ho": "1502", "areaM2": 84.97,
            "items": [{ "name": "일반관리비", "amount": 121500 }],
            "usage": { "electricityKwh": 312.5, "waterM3": null,
                       "hotWaterM3": null, "heatingGcal": null, "foodKg": null },
            "chargedAmount": 121500, "discountTotal": 0,
            "unpaidAmount": 0, "unpaidLateFee": 0,
            "dueAmount": 121500, "dueDate": null,
            "sumMatched": false,
            "warnings": ["항목 합계가 부과액과 맞지 않습니다"]
          }
        }
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.yearMonth == nil)
        #expect(recognition.sumMatched == false)
        #expect(recognition.warnings == ["항목 합계가 부과액과 맞지 않습니다"])
    }

    /// 목록 응답은 `bills` 배열로 한 겹 더 싸여 온다.
    @Test func 목록을_디코딩한다() throws {
        let json = """
        { "data": { "bills": [
            { "yearMonth": "2026-08", "dong": null, "ho": null, "areaM2": null,
              "items": [], "chargedAmount": 10, "discountTotal": 0,
              "unpaidAmount": 0, "unpaidLateFee": 0, "dueAmount": 10, "dueDate": null }
        ] } }
        """
        let list = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceBillList>.self, from: Data(json.utf8)).data
        )
        #expect(list.bills.count == 1)
        #expect(list.bills[0].yearMonth == "2026-08")
    }

    /// 추이 응답. `dueAmount`가 없다 — 통계는 부과액 기준이다.
    @Test func 추이를_디코딩한다() throws {
        let json = """
        { "data": { "months": [
            { "yearMonth": "2025-08", "chargedAmount": 150000,
              "items": [{ "name": "일반관리비", "amount": 100000 }],
              "usage": { "electricityKwh": 300, "waterM3": null,
                         "hotWaterM3": null, "heatingGcal": null, "foodKg": null } }
        ] } }
        """
        let trend = try #require(
            try JSONDecoder().decode(DataResponse<MaintenanceTrend>.self, from: Data(json.utf8)).data
        )
        #expect(trend.months.count == 1)
        #expect(trend.months[0].chargedAmount == Decimal(150000))
    }

    /// 비운 사용량 칸은 **키째 빠져야 한다.** 0으로 나가면 서버에 「0을 썼다」가 저장된다.
    @Test func 저장_요청에서_빈_사용량은_키가_빠진다() throws {
        let request = MaintenanceBillSaveRequest(
            yearMonth: "2026-08",
            items: [MaintenanceBillItemRequest(name: "일반관리비", amount: 100)],
            chargedAmount: 100, dueAmount: 100,
            dong: nil, ho: nil, areaM2: nil,
            usage: MaintenanceUsage(electricityKwh: Decimal(312),
                                    waterM3: nil, hotWaterM3: nil,
                                    heatingGcal: nil, foodKg: nil),
            discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0, dueDate: nil
        )
        let data = try JSONEncoder().encode(request)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let usage = try #require(json["usage"] as? [String: Any])

        #expect(usage["electricityKwh"] != nil)
        #expect(usage["waterM3"] == nil)
        #expect(json["dong"] == nil)
    }
}

@MainActor
struct MaintenanceServiceTests {
    private func makeBill(_ yearMonth: String) -> MaintenanceBill {
        MaintenanceBill(yearMonth: yearMonth, dong: nil, ho: nil, areaM2: nil,
                        items: [], usage: nil,
                        chargedAmount: 0, discountTotal: 0,
                        unpaidAmount: 0, unpaidLateFee: 0,
                        dueAmount: 0, dueDate: nil)
    }

    @Test func 목록을_받아_bills를_꺼낸다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/bills",
                    result: DataResponse(data: MaintenanceBillList(bills: [makeBill("2026-08")])))
        let service = MaintenanceService(api: api)

        let bills = try await service.fetchBills()

        #expect(bills.map(\.yearMonth) == ["2026-08"])
        #expect(api.getCalls.map(\.path) == ["/maintenance/bills"])
    }

    @Test func 상세는_연월을_경로에_넣는다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/bills/2026-08", result: DataResponse(data: makeBill("2026-08")))
        let service = MaintenanceService(api: api)

        let bill = try await service.fetchBill(yearMonth: "2026-08")

        #expect(bill.yearMonth == "2026-08")
        #expect(api.getCalls.map(\.path) == ["/maintenance/bills/2026-08"])
    }

    /// 추이는 `months`를 쿼리로 싣는다. 기본 13은 **전년 동월이 범위에 들어오라고** 고른 값이다.
    @Test func 추이는_months를_쿼리로_보낸다() async throws {
        let api = MockAPIClient()
        api.stubGet("/maintenance/trends", result: DataResponse(data: MaintenanceTrend(months: [])))
        let service = MaintenanceService(api: api)

        _ = try await service.fetchTrends(months: 13)

        #expect(api.getCalls.first?.query == ["months": "13"])
    }

    /// 인식은 multipart다. **`image/jpeg`로 보낸다** — 서버가 이 값으로 디코더를 고르는데
    /// HEIC 원본을 jpeg로 위장해 보내면 `IMAGE_UNREADABLE`이 된다.
    @Test func 인식은_jpeg_multipart로_나간다() async throws {
        let api = MockAPIClient()
        let recognition = MaintenanceRecognition(
            yearMonth: "2026-08", dong: nil, ho: nil, areaM2: nil,
            items: [], usage: nil, chargedAmount: 0, discountTotal: 0,
            unpaidAmount: 0, unpaidLateFee: 0, dueAmount: 0, dueDate: nil,
            sumMatched: true, warnings: []
        )
        api.stubMultipartJSON("/maintenance/recognitions", result: DataResponse(data: recognition))
        let service = MaintenanceService(api: api)

        _ = try await service.recognize(imageData: Data([0xFF, 0xD8]))

        let call = try #require(api.multipartJSONCalls.first)
        #expect(call.path == "/maintenance/recognitions")
        #expect(call.mimeType == "image/jpeg")
        #expect(call.fileName.hasSuffix(".jpg"))
    }

    /// 인식 응답이 비면 200이라도 실패다 — nil을 들고 검수 화면을 열 수 없다.
    @Test func 빈_인식_응답은_에러다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/maintenance/recognitions",
                              result: DataResponse<MaintenanceRecognition>(data: nil))
        let service = MaintenanceService(api: api)

        await #expect(throws: (any Error).self) {
            _ = try await service.recognize(imageData: Data())
        }
    }

    @Test func 저장과_수정과_삭제가_각_경로로_나간다() async throws {
        let api = MockAPIClient()
        let service = MaintenanceService(api: api)
        let request = MaintenanceBillSaveRequest(
            yearMonth: "2026-08",
            items: [MaintenanceBillItemRequest(name: "일반관리비", amount: 100)],
            chargedAmount: 100, dueAmount: 100,
            dong: nil, ho: nil, areaM2: nil, usage: nil,
            discountTotal: 0, unpaidAmount: 0, unpaidLateFee: 0, dueDate: nil
        )

        try await service.saveBill(request)
        try await service.updateBill(yearMonth: "2026-08", request)
        try await service.deleteBill(yearMonth: "2026-08")

        #expect(api.postCalls.map(\.path) == ["/maintenance/bills"])
        #expect(api.putVoidCalls.map(\.path) == ["/maintenance/bills/2026-08"])
        #expect(api.deleteCalls == ["/maintenance/bills/2026-08"])
    }
}
