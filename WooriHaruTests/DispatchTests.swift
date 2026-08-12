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

@MainActor
struct DispatchReviewViewModelTests {
    private func makeViewModel(
        recognition: DispatchRecognition,
        service: FakeDispatchService
    ) -> DispatchReviewViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        return DispatchReviewViewModel(recognition: recognition, service: service, calendar: calendar)
    }

    @Test func 그_달_전체를_보여주되_사진에_없던_날은_미인식이다() {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 2026-08은 31일까지다.
        #expect(vm.entries.count == 31)
        #expect(vm.entries[0].recognized == true)
        #expect(vm.entries[1].recognized == true)
        #expect(vm.entries[2].recognized == false)
        #expect(vm.entries[30].recognized == false)
    }

    @Test func 미인식_날짜는_저장에서_빠진다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()

        let request = try #require(service.savedRequests.first)
        // 서버는 「보낸 날짜만 upsert」한다. 미인식 날짜를 휴무로 채워 보내면
        // 멀쩡한 기존 값이 휴무로 덮인다.
        #expect(request.days.count == 2)
        #expect(request.days.map(\.date) == ["2026-08-01", "2026-08-02"])
        #expect(request.role == "FATHER")
    }

    @Test func 값을_고치면_저장에_반영된다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: true, slot: 2)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].slot == 2)
        #expect(request.days[0].working == true)
    }

    @Test func 미인식이던_날을_직접_채우면_저장에_들어간다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 5, working: false, slot: nil)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days.map(\.date).contains("2026-08-05"))
    }

    @Test func 인식된_날을_미인식으로_되돌리면_저장에서_빠진다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 2, working: false, slot: nil, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.markUnrecognized(day: 2)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days.map(\.date) == ["2026-08-01"])
    }

    @Test func 행_위치로_매칭했으면_배너를_띄운다() {
        let byIndex = sampleRecognition(matchedBy: .rowIndex)
        let vm = makeViewModel(recognition: byIndex, service: FakeDispatchService(recognizeResult: .success(byIndex)))
        // 성명 컬럼이 없어 저장된 행 위치로 맞춘 것이라 사람이 사진과 대조해야 한다.
        #expect(vm.needsRowIndexWarning == true)

        let byName = sampleRecognition(matchedBy: .name)
        let vm2 = makeViewModel(recognition: byName, service: FakeDispatchService(recognizeResult: .success(byName)))
        #expect(vm2.needsRowIndexWarning == false)
    }

    @Test func 서버_경고를_사람이_읽는_문장으로_바꾼다() {
        let recognition = sampleRecognition(warnings: ["ROW_COUNT_CHANGED", "YEAR_MONTH_MISMATCH"])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        #expect(vm.warningMessages.count == 2)
        #expect(vm.warningMessages[0].contains("인원"))
        #expect(vm.warningMessages[1].contains("달"))
    }

    @Test func 저장에_실패하면_메시지를_남기고_완료로_치지_않는다() async {
        let recognition = sampleRecognition()
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        service.saveError = APIError.serverError(statusCode: 400, message: "저장에 실패했습니다")
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()

        #expect(vm.didSave == false)
        #expect(vm.errorMessage != nil)
        #expect(vm.isSaving == false)
    }

    @Test func 저장_성공_후_다시_실패하면_저장됨_표시가_남지_않는다() async {
        let recognition = sampleRecognition()
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()
        #expect(vm.didSave == true)

        service.saveError = APIError.serverError(statusCode: 400, message: "저장에 실패했습니다")
        await vm.save()

        // 첫 저장의 성공 표시가 남아 「저장됨」과 오류가 동시에 뜨면 안 된다.
        #expect(vm.didSave == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func 중복된_날짜가_와도_죽지_않고_하나만_반영한다() {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false),
            DispatchRecognitionDay(day: 1, working: false, slot: nil, note: nil, conflict: false)
        ])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 크래시하지 않고, 뒤에 온 값(휴무)으로 반영된다.
        #expect(vm.entries.count == 31)
        #expect(vm.entries[0].recognized == true)
        #expect(vm.entries[0].working == false)
    }
}
