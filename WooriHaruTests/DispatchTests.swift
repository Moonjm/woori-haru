import Foundation
import Testing
@testable import WooriHaru

@MainActor
struct DispatchModelTests {
    /// 서버 `RecognitionResponse`를 그대로 옮긴 응답. 필드가 하나라도 어긋나면 디코딩이 깨진다.
    static let recognitionJSON = """
    {
      "data": {
        "yearMonth": "2026-08",
        "hasNameColumn": true,
        "matchedBy": "NAME",
        "rowIndex": 2,
        "rowCount": 13,
        "warnings": ["ROW_COUNT_CHANGED"],
        "days": [
          { "day": 1, "working": true, "slot": 1, "note": null, "conflict": false },
          { "day": 2, "working": false, "slot": null, "note": null, "conflict": false },
          { "day": 3, "working": false, "slot": null, "note": "*97", "conflict": true }
        ]
      }
    }
    """

    @Test func 인식_응답을_디코딩한다() throws {
        let data = Data(Self.recognitionJSON.utf8)
        let response = try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: data)
        let recognition = try #require(response.data)

        #expect(recognition.yearMonth == "2026-08")
        #expect(recognition.matchedBy == .name)
        #expect(recognition.rowIndex == 2)
        #expect(recognition.rowCount == 13)
        #expect(recognition.warnings == ["ROW_COUNT_CHANGED"])
        #expect(recognition.days.count == 3)
    }

    @Test func 근무_판정은_working만_본다() throws {
        let data = Data(Self.recognitionJSON.utf8)
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: data).data
        )

        // 1일은 slot이 있는 근무, 2일은 휴무, 3일은 note가 있지만 휴무다.
        #expect(recognition.days[0].working == true)
        #expect(recognition.days[0].slot == 1)
        #expect(recognition.days[1].working == false)
        #expect(recognition.days[2].working == false)
        #expect(recognition.days[2].note == "*97")
    }

    @Test func ROW_INDEX_매칭을_디코딩한다() throws {
        let json = """
        {"data":{"yearMonth":"2026-08","hasNameColumn":false,"matchedBy":"ROW_INDEX",
        "rowIndex":2,"rowCount":13,"warnings":[],"days":[]}}
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.matchedBy == .rowIndex)
        #expect(recognition.hasNameColumn == false)
    }

    @Test func 저장_요청을_인코딩한다() throws {
        let request = DispatchShiftSaveRequest(
            role: "FATHER",
            days: [DispatchShiftSaveDay(date: "2026-08-01", working: true, slot: 1, note: nil)]
        )
        let encoded = try JSONEncoder().encode(request)
        let json = try #require(
            try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        #expect(json["role"] as? String == "FATHER")
        let days = try #require(json["days"] as? [[String: Any]])
        #expect(days.count == 1)
        #expect(days[0]["date"] as? String == "2026-08-01")
        #expect(days[0]["working"] as? Bool == true)
        #expect(days[0]["slot"] as? Int == 1)
    }
}

/// `APIClient.appending(query:to:)` — 배차 인식 API가 처음으로 실제 쿼리(`yearMonth`)를
/// 붙이는 자리라, 값에 델리미터가 들어와도 깨지지 않는지 별도로 검증한다.
@MainActor
struct APIClientAppendingQueryTests {
    @Test func 값에_앰퍼샌드가_들어가면_이스케이프된다() throws {
        let result = APIClient.appending(query: ["note": "a&b=c"], to: "/dispatch/recognize")

        let components = try #require(URLComponents(string: "https://example.com" + result))
        let items = try #require(components.queryItems)

        #expect(items.count == 1)
        #expect(items[0].name == "note")
        #expect(items[0].value == "a&b=c")
    }

    @Test func 경로에_이미_물음표가_있으면_앰퍼샌드로_잇는다() throws {
        let result = APIClient.appending(query: ["yearMonth": "2026-08"], to: "/dispatch/recognize?debug=1")

        #expect(result.hasPrefix("/dispatch/recognize?debug=1&"))
        let components = try #require(URLComponents(string: "https://example.com" + result))
        let items = try #require(components.queryItems)
        #expect(items.contains { $0.name == "debug" && $0.value == "1" })
        #expect(items.contains { $0.name == "yearMonth" && $0.value == "2026-08" })
    }

    @Test func 쿼리가_비어있으면_경로가_그대로다() {
        let result = APIClient.appending(query: [:], to: "/dispatch/recognize")
        #expect(result == "/dispatch/recognize")
    }
}

@MainActor
struct DispatchServiceTests {
    private func recognition(yearMonth: String = "2026-08") -> DispatchRecognition {
        DispatchRecognition(
            yearMonth: yearMonth,
            hasNameColumn: true,
            matchedBy: .name,
            rowIndex: 2,
            rowCount: 13,
            warnings: [],
            days: [DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)]
        )
    }

    @Test func 인식은_연월을_쿼리로_보낸다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        _ = try await service.recognize(imageData: Data([0x01, 0x02]), yearMonth: "2026-08")

        let call = try #require(api.multipartJSONCalls.first)
        #expect(call.path == "/dispatch/recognitions")
        // 연월을 안 보내면 서버가 어느 달 기준을 조회할지 모른다.
        #expect(call.query["yearMonth"] == "2026-08")
        #expect(call.fileData == Data([0x01, 0x02]))
    }

    @Test func 인식_결과를_그대로_돌려준다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        let result = try await service.recognize(imageData: Data([0x01]), yearMonth: "2026-08")

        #expect(result.yearMonth == "2026-08")
        #expect(result.matchedBy == .name)
        #expect(result.days.count == 1)
    }

    @Test func 저장은_204라_본문을_기대하지_않는다() async throws {
        let api = MockAPIClient()
        let service = DispatchService(api: api)

        try await service.saveShifts(
            DispatchShiftSaveRequest(
                role: "FATHER",
                days: [DispatchShiftSaveDay(date: "2026-08-01", working: true, slot: 1, note: nil)]
            )
        )

        // postVoid는 recordedPostCalls에 남는다(MockAPIClient 기존 구현).
        #expect(api.postCalls.contains { $0.path == "/dispatch/shifts" })
    }
}

/// 인식만 하는 대역. 호출 인자를 기록하고 미리 정한 결과를 돌려준다.
private final class FakeDispatchService: DispatchServing, @unchecked Sendable {
    var recognizeResult: Result<DispatchRecognition, Error>
    var saveError: Error?
    private(set) var recognizeCalls: [(imageData: Data, yearMonth: String)] = []
    private(set) var savedRequests: [DispatchShiftSaveRequest] = []

    init(recognizeResult: Result<DispatchRecognition, Error>) {
        self.recognizeResult = recognizeResult
    }

    func recognize(imageData: Data, yearMonth: String) async throws -> DispatchRecognition {
        recognizeCalls.append((imageData, yearMonth))
        return try recognizeResult.get()
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        savedRequests.append(request)
        if let saveError { throw saveError }
    }
}

private func sampleRecognition(
    matchedBy: DispatchMatchedBy = .name,
    warnings: [String] = [],
    days: [DispatchRecognitionDay] = [
        DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
    ]
) -> DispatchRecognition {
    DispatchRecognition(
        yearMonth: "2026-08",
        hasNameColumn: matchedBy == .name,
        matchedBy: matchedBy,
        rowIndex: 2,
        rowCount: 13,
        warnings: warnings,
        days: days
    )
}

@MainActor
struct DispatchUploadViewModelTests {
    @Test func 사진이_없으면_인식할_수_없다() {
        let vm = DispatchUploadViewModel(service: FakeDispatchService(recognizeResult: .success(sampleRecognition())))
        #expect(vm.canRecognize == false)

        vm.setImage(Data([0x01]))
        #expect(vm.canRecognize == true)
    }

    @Test func 인식에_성공하면_결과를_들고_완료된다() async {
        let service = FakeDispatchService(recognizeResult: .success(sampleRecognition()))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01, 0x02]))
        vm.yearMonth = "2026-08"

        await vm.recognize()

        #expect(vm.phase == .completed)
        #expect(vm.recognition?.yearMonth == "2026-08")
        #expect(service.recognizeCalls.first?.yearMonth == "2026-08")
        // 원본 바이트가 그대로 가야 한다 — 줄이면 인식이 망가진다.
        #expect(service.recognizeCalls.first?.imageData == Data([0x01, 0x02]))
    }

    @Test func 인식에_실패하면_서버_메시지를_그대로_보여준다() async {
        let error = APIError.serverError(statusCode: 400, message: "배차표 사진에서 대상 기사를 찾지 못했습니다. 사진을 확인해 주세요.")
        let service = FakeDispatchService(recognizeResult: .failure(error))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        // 서버 메시지가 이미 사용자용 한국어다. 앱이 다시 쓰지 않는다.
        #expect(vm.errorMessage?.contains("대상 기사를 찾지 못했습니다") == true)
    }

    @Test func 기본_연월은_이번_달이다() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!

        #expect(DispatchUploadViewModel.defaultYearMonth(now: date, calendar: calendar) == "2026-08")
    }

    @Test func 한자리_월은_0을_채운다() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        // "2026-3"으로 보내면 서버의 YearMonth 파싱이 400을 낸다.
        #expect(DispatchUploadViewModel.defaultYearMonth(now: date, calendar: calendar) == "2026-03")
    }
}
