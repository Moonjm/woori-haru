import Foundation
import Testing
import UIKit
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

    @Test func 근무_조회_응답을_디코딩한다() throws {
        let json = """
        {"data":{"days":[
          {"date":"2026-08-01","role":"FATHER","working":true,"slot":1,"note":null},
          {"date":"2026-08-01","role":"MOTHER","working":true,"slot":null,"note":null},
          {"date":"2026-08-02","role":"FATHER","working":false,"slot":null,"note":"휴"}
        ]}}
        """
        let response = try JSONDecoder().decode(DataResponse<DispatchShiftRange>.self, from: Data(json.utf8))
        let range = try #require(response.data)

        #expect(range.days.count == 3)
        #expect(range.days[0].role == .father)
        #expect(range.days[1].role == .mother)
        // 엄마는 순번을 넣지 않는다. 근무 판정은 working만 본다.
        #expect(range.days[1].working == true)
        #expect(range.days[1].slot == nil)
    }

    @Test func 인식_응답의_연월은_비어_올_수_있다() throws {
        // 제목이 잘린 사진은 서버가 연월을 못 읽는다. 검수 화면이 채운다.
        let json = """
        {"data":{"yearMonth":null,"hasNameColumn":false,"matchedBy":"ROW_INDEX",
        "rowIndex":2,"rowCount":13,"warnings":["ROSTER_FROM_OTHER_MONTH"],"days":[]}}
        """
        let recognition = try #require(
            try JSONDecoder().decode(DataResponse<DispatchRecognition>.self, from: Data(json.utf8)).data
        )
        #expect(recognition.yearMonth == nil)
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

    @Test func 근무를_연월로_조회한다() async throws {
        let api = MockAPIClient()
        api.stubGet("/dispatch/shifts", result: DataResponse(data: DispatchShiftRange(days: [
            DispatchShiftDay(date: "2026-08-01", role: .father, working: true, slot: 1, note: nil)
        ])))
        let service = DispatchService(api: api)

        let days = try await service.findShifts(yearMonth: "2026-08")

        #expect(days.count == 1)
        #expect(api.getCalls.contains { $0.path == "/dispatch/shifts" && $0.query["yearMonth"] == "2026-08" })
    }

    @Test func 인식은_연월을_보내지_않는다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        _ = try await service.recognize(imageData: Data([0x01]))

        let call = try #require(api.multipartJSONCalls.first)
        // 연월은 서버가 사진에서 읽는다. 앱이 보내면 그 값이 기준이 되어 사진 제목을 덮는다.
        #expect(call.query.isEmpty)
    }

    @Test func 사진은_JPEG로_보낸다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        _ = try await service.recognize(imageData: Data([0x01]))

        let call = try #require(api.multipartJSONCalls.first)
        // 서버는 파트의 mime으로 디코더를 고른다. HEIC 원본을 image/jpeg로 위장해 보내면
        // `ImageIO.read`가 null을 돌려줘 IMAGE_UNREADABLE(400)이 된다 — 화면에서 원본을
        // JPEG로 다시 구운 뒤 넘기기로 한 약속이 이 값이다.
        #expect(call.mimeType == "image/jpeg")
        #expect(call.fileName == "dispatch.jpg")
    }

    @Test func 인식_결과를_그대로_돌려준다() async throws {
        let api = MockAPIClient()
        api.stubMultipartJSON("/dispatch/recognitions", result: DataResponse(data: recognition()))
        let service = DispatchService(api: api)

        let result = try await service.recognize(imageData: Data([0x01]))

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
    /// 인식이 진행 중인 순간에 끼어들 자리. 재진입 가드를 재우지 않고 확인하는 데 쓴다.
    var duringRecognize: (@Sendable () async -> Void)?
    private(set) var recognizeCalls: [Data] = []
    private(set) var savedRequests: [DispatchShiftSaveRequest] = []

    init(recognizeResult: Result<DispatchRecognition, Error>) {
        self.recognizeResult = recognizeResult
    }

    func findShifts(yearMonth: String) async throws -> [DispatchShiftDay] {
        []
    }

    func recognize(imageData: Data) async throws -> DispatchRecognition {
        recognizeCalls.append(imageData)
        await duringRecognize?()
        return try recognizeResult.get()
    }

    func saveShifts(_ request: DispatchShiftSaveRequest) async throws {
        savedRequests.append(request)
        if let saveError { throw saveError }
    }
}

private func sampleRecognition(
    yearMonth: String? = "2026-08",
    matchedBy: DispatchMatchedBy = .name,
    warnings: [String] = [],
    days: [DispatchRecognitionDay] = [
        DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
    ]
) -> DispatchRecognition {
    DispatchRecognition(
        yearMonth: yearMonth,
        hasNameColumn: matchedBy == .name,
        matchedBy: matchedBy,
        rowIndex: 2,
        rowCount: 13,
        warnings: warnings,
        days: days
    )
}

/// 단색 이미지는 JPEG로 거의 0바이트가 되어 바이트 상한을 검증할 수 없다. 압축이 잘 안 되는
/// 무늬를 그린다. `Date`·난수를 쓰지 않아 매번 같은 바이트가 나온다.
private func makeNoisyJPEG(width: Int, height: Int) -> Data {
    let size = CGSize(width: width, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        for x in stride(from: 0, to: width, by: 4) {
            for y in stride(from: 0, to: height, by: 4) {
                let hue = CGFloat((x * 7 + y * 13) % 360) / 360
                UIColor(hue: hue, saturation: 1, brightness: 1, alpha: 1).setFill()
                context.fill(CGRect(x: x, y: y, width: 4, height: 4))
            }
        }
    }
    return image.jpegData(compressionQuality: 1.0)!
}

/// 서버 multipart 한도(10MB)를 넘기면 멀쩡한 배차표 사진이 인식에 들어가 보지도 못하고 실패한다.
struct DispatchImageSizeTests {
    @Test func 상한에_여유가_있으면_원본_해상도_최고_품질_그대로다() throws {
        let original = makeNoisyJPEG(width: 800, height: 800)
        let full = try #require(
            UIImage.downsampledJPEG(from: original, maxDimension: .greatestFiniteMagnitude, quality: 0.95)
        )

        let capped = try #require(UIImage.jpegWithinByteLimit(from: original, byteLimit: 10 * 1024 * 1024))

        // 상한에 걸리지 않았는데 품질을 깎으면 인식만 나빠진다.
        #expect(capped.count == full.count)
    }

    @Test func 상한을_넘으면_해상도가_아니라_품질을_먼저_낮춘다() throws {
        let original = makeNoisyJPEG(width: 800, height: 800)
        let full = try #require(
            UIImage.downsampledJPEG(from: original, maxDimension: .greatestFiniteMagnitude, quality: 0.95)
        )
        let lower = try #require(
            UIImage.downsampledJPEG(from: original, maxDimension: .greatestFiniteMagnitude, quality: 0.5)
        )
        #expect(lower.count < full.count, "전제가 깨졌다 — 품질을 낮췄는데 커졌다")

        let capped = try #require(
            UIImage.jpegWithinByteLimit(
                from: original,
                byteLimit: lower.count,
                qualities: [0.95, 0.5],
                dimensions: [.greatestFiniteMagnitude]
            )
        )

        #expect(capped.count <= lower.count)
        // **해상도는 마지막에 포기한다.** 배차표는 한 칸이 몇 픽셀이라 줄이면 인식이 무너진다.
        let image = try #require(UIImage(data: capped))
        #expect(max(image.size.width, image.size.height) == 800)
    }

    @Test func 어느_단계도_상한에_못_들어가면_가장_작은_것을_준다() throws {
        let original = makeNoisyJPEG(width: 400, height: 400)

        let capped = try #require(UIImage.jpegWithinByteLimit(from: original, byteLimit: 1))

        // 여기서 nil을 주면 화면이 「사진을 읽지 못했습니다」를 띄우는데, 읽기는 멀쩡히 됐다.
        #expect(capped.count > 1)
    }

    @Test func 이미지가_아닌_데이터는_nil() {
        #expect(UIImage.jpegWithinByteLimit(from: Data("not an image".utf8)) == nil)
    }
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

        await vm.recognize()

        #expect(vm.phase == .completed)
        #expect(vm.recognition?.yearMonth == "2026-08")
        // 원본 바이트가 그대로 가야 한다 — 줄이면 인식이 망가진다.
        #expect(service.recognizeCalls.first == Data([0x01, 0x02]))
    }

    @Test func 인식에_실패하면_서버_메시지를_그대로_보여준다() async {
        // **`APIClient`가 실제로 만드는 모양이어야 한다.** `rawMultipartFetch`는 실패 본문
        // 전체를 `message`에 담으므로, 손으로 만든 한 줄짜리 메시지를 넣으면 봉투 JSON이
        // 그대로 노출되는 결함을 못 잡는다.
        let envelope = """
        {"status":400,"message":"배차표 사진에서 대상 기사를 찾지 못했습니다. 사진을 확인해 주세요.",\
        "timestamp":"2026-08-12T10:00:00","code":"400","error":"TARGET_NOT_FOUND"}
        """
        let error = APIError.serverError(statusCode: 400, message: envelope)
        let service = FakeDispatchService(recognizeResult: .failure(error))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        // 서버 메시지가 이미 사용자용 한국어다. 앱이 다시 쓰지 않는다.
        #expect(vm.errorMessage == "배차표 사진에서 대상 기사를 찾지 못했습니다. 사진을 확인해 주세요.")
        // 봉투가 새어 나오면 안 된다.
        #expect(vm.errorMessage?.contains("TARGET_NOT_FOUND") == false)
        #expect(vm.errorMessage?.contains("timestamp") == false)
    }

    @Test func 봉투가_아니면_기존_메시지로_떨어진다() async {
        let error = APIError.serverError(statusCode: 502, message: "<html>Bad Gateway</html>")
        let service = FakeDispatchService(recognizeResult: .failure(error))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))

        await vm.recognize()

        #expect(vm.phase == .failed)
        #expect(vm.errorMessage == "<html>Bad Gateway</html>")
    }

    @Test func 인식_중에_다시_불러도_요청은_한_번만_나간다() async {
        let service = FakeDispatchService(recognizeResult: .success(sampleRecognition()))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))
        service.duringRecognize = { [vm] in
            // 이미 인식 중이다. 두 번째 호출은 그대로 돌아가야 한다 — 유료 인식이 두 번 나간다.
            await vm.recognize()
        }

        await vm.recognize()

        #expect(service.recognizeCalls.count == 1)
        #expect(vm.phase == .completed)
    }

    @Test func 인식_중에_사진을_바꾸면_이전_결과를_버린다() async {
        let service = FakeDispatchService(recognizeResult: .success(sampleRecognition()))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))
        service.duringRecognize = { [vm] in
            // 사진을 잘못 골라 곧바로 다시 고른 상황. 이전 인식이 아직 돌아오지 않았다.
            await MainActor.run { vm.setImage(Data([0x09])) }
        }

        await vm.recognize()

        // 완료를 세우면 **이전 사진의 인식 결과와 새 사진의 미리보기가 섞인** 검수 화면이
        // 열리고, 그대로 저장하면 다른 사진의 근무가 들어간다.
        #expect(vm.phase == .idle)
        #expect(vm.recognition == nil)
    }

    @Test func 사진을_비우면_인식할_수_없다() {
        let vm = DispatchUploadViewModel(service: FakeDispatchService(recognizeResult: .success(sampleRecognition())))
        vm.setImage(Data([0x01]))
        #expect(vm.canRecognize == true)

        // 새 사진을 고른 순간 화면이 부른다. 비우지 않으면 로딩이 끝나기 전에 「인식하기」가
        // 눌려 이전 사진이 나간다.
        vm.clearImage()

        #expect(vm.imageData == nil)
        #expect(vm.canRecognize == false)
        // 오류가 아니다 — 새 사진을 불러오는 중일 뿐이다.
        #expect(vm.errorMessage == nil)
    }

    @Test func 인식_중에_사진을_바꾸면_이전_실패도_보여주지_않는다() async {
        let error = APIError.serverError(statusCode: 400, message: """
        {"status":400,"message":"배차표 사진에서 대상 기사를 찾지 못했습니다.","code":"400","error":"TARGET_NOT_FOUND"}
        """)
        let service = FakeDispatchService(recognizeResult: .failure(error))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))
        service.duringRecognize = { [vm] in
            await MainActor.run { vm.setImage(Data([0x09])) }
        }

        await vm.recognize()

        // 방금 고른 사진이 실패한 줄 알게 된다. 실패한 것은 바뀌기 전 사진이다.
        #expect(vm.phase == .idle)
        #expect(vm.errorMessage == nil)
        #expect(vm.canRecognize == true)
    }

    @Test func 취소는_실패로_치지_않는다() async {
        let service = FakeDispatchService(recognizeResult: .failure(CancellationError()))
        let vm = DispatchUploadViewModel(service: service)
        vm.setImage(Data([0x01]))

        await vm.recognize()

        // 화면을 떠난 것이지 실패가 아니다. 영문 시스템 메시지를 띄우지 않는다.
        #expect(vm.phase != .failed)
        #expect(vm.errorMessage == nil)
    }

    @Test func 사진을_읽지_못하면_조용히_넘기지_않는다() {
        let vm = DispatchUploadViewModel(service: FakeDispatchService(recognizeResult: .success(sampleRecognition())))
        vm.setImage(Data([0x01]))

        vm.setImageLoadFailed()

        #expect(vm.imageData == nil)
        #expect(vm.canRecognize == false)
        #expect(vm.errorMessage != nil)
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

    @Test func 보낼_날짜가_없으면_요청하지_않는다() async {
        // 서버 `ShiftSaveRequest.days`에 `@NotEmpty`가 걸려 있어 빈 배열은 400이다.
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        #expect(vm.canSave == true)
        vm.markUnrecognized(day: 1)
        #expect(vm.canSave == false)

        await vm.save()

        #expect(service.savedRequests.isEmpty)
        #expect(vm.didSave == false)
        #expect(vm.errorMessage != nil)
    }

    @Test func 인식_결과가_비어_오면_저장이_막힌다() {
        let recognition = sampleRecognition(days: [])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        #expect(vm.canSave == false)
    }

    @Test func 근무_여부를_뒤집으면_원문_note를_버린다() async throws {
        // OCR이 「1번」 칸을 휴무로 잘못 읽고 note에 "휴"를 실어 온 경우.
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: false, slot: nil, note: "휴", conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: true, slot: 1)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        // note를 남기면 웹 달력이 근무 뱃지에 원문을 붙여 「1번 휴」로 찍는다.
        #expect(request.days[0].working == true)
        #expect(request.days[0].slot == 1)
        #expect(request.days[0].note == nil)
    }

    @Test func 휴무를_휴무로_두면_원문_note는_남는다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: false, slot: nil, note: "간담회", conflict: true)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: false, slot: nil)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].note == "간담회")
        #expect(vm.entries[0].conflict == false)
    }

    @Test func 순번만_고쳐도_원문_note를_버린다() async throws {
        // OCR이 2번 칸을 1번으로 읽으면서 원문 "*97"을 함께 실어 온 경우.
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: "*97", conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: true, slot: 2)

        // 검수 화면 라벨은 note를 순번보다 우선한다. 남겨 두면 「2번」을 고른 뒤에도
        // 화면에 `*97`이 그대로 보여 사용자가 고쳐진 줄 모른다.
        #expect(vm.entries[0].note == nil)

        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].slot == 2)
        #expect(request.days[0].note == nil)
    }

    @Test func 인식값을_그대로_확정하면_원문_note는_남는다() async throws {
        let recognition = sampleRecognition(days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: "*97", conflict: true)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setWorking(day: 1, working: true, slot: 1)
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].note == "*97")
    }

    @Test func 저장_실패_메시지에서_봉투를_벗긴다() async {
        let recognition = sampleRecognition()
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        service.saveError = APIError.serverError(
            statusCode: 400,
            message: #"{"status":400,"message":"저장에 실패했습니다","code":"400","error":"INVALID_REQUEST"}"#
        )
        let vm = makeViewModel(recognition: recognition, service: service)

        await vm.save()

        #expect(vm.errorMessage == "저장에 실패했습니다")
    }

    @Test func 요일을_함께_보여준다() {
        let recognition = sampleRecognition()
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 2026-08-01은 토요일이다. 사진의 표가 요일 머리글로 정렬돼 있어 대조에 쓰인다.
        #expect(vm.entries[0].weekday == "토")
        #expect(vm.entries[1].weekday == "일")
        #expect(vm.entries[2].weekday == "월")
        #expect(vm.entries[30].weekday == "월")
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

    @Test func 연월을_못_읽었으면_저장이_잠긴다() {
        let recognition = sampleRecognition(yearMonth: nil)
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 날짜 값은 멀쩡히 있지만 어느 달인지 모른다. 그대로 저장하면 날짜를 만들 수 없다.
        #expect(vm.yearMonth == "")
        #expect(vm.canSave == false)

        vm.setYearMonth("2026-08")
        #expect(vm.canSave == true)
    }

    @Test func 연월_형식이_어긋나면_저장이_잠긴다() {
        let recognition = sampleRecognition(yearMonth: nil)
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 서버 YearMonth 파싱은 2026-3에 400을 낸다.
        for invalid in ["2026-3", "2026-13", "26-08", "2026-08-01", ""] {
            vm.setYearMonth(invalid)
            #expect(vm.isYearMonthValid == false, "\(invalid)는 막아야 한다")
            #expect(vm.canSave == false, "\(invalid)는 막아야 한다")
        }
    }

    @Test func 확정한_연월로_날짜를_만든다() async throws {
        let recognition = sampleRecognition(yearMonth: nil, days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let service = FakeDispatchService(recognizeResult: .success(recognition))
        let vm = makeViewModel(recognition: recognition, service: service)

        vm.setYearMonth("2026-09")
        await vm.save()

        let request = try #require(service.savedRequests.first)
        #expect(request.days[0].date == "2026-09-01")
    }

    @Test func 연월을_채우면_요일과_말일이_맞춰진다() {
        let recognition = sampleRecognition(yearMonth: nil, days: [
            DispatchRecognitionDay(day: 1, working: true, slot: 1, note: nil, conflict: false)
        ])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        // 연월을 모르면 며칠까지인지도 모른다. 넉넉히 31일로 두고 시작한다.
        #expect(vm.entries.count == 31)
        #expect(vm.entries[0].weekday == "")

        vm.setYearMonth("2026-02")

        // 2026년 2월은 28일까지고 1일은 일요일이다.
        #expect(vm.entries.count == 28)
        #expect(vm.entries[0].weekday == "일")
        // 고쳐 둔 값은 남아야 한다 — 연월을 나중에 채운다고 검수한 내용이 날아가면 안 된다.
        #expect(vm.entries[0].working == true)
        #expect(vm.entries[0].slot == 1)
    }

    @Test func 다른_달_기준을_빌려_썼으면_알린다() {
        let recognition = sampleRecognition(yearMonth: nil, warnings: ["ROSTER_FROM_OTHER_MONTH"])
        let vm = makeViewModel(recognition: recognition, service: FakeDispatchService(recognizeResult: .success(recognition)))

        #expect(vm.warningMessages == [
            "저장된 줄 위치를 다른 달 것으로 맞췄습니다. 순번이 밀리지 않았는지 사진과 대조해 주세요."
        ])
    }

    @Test func 요일은_넘겨받은_달력으로_센다() {
        // 기본 인자가 `.dispatchGregorian`인 것은 그레고리력 기기에서 테스트로 구별할 수
        // 없다(`.current`와 같은 값을 낸다). 대신 계산이 `Calendar.current`에 박혀 있지
        // 않다는 것을 확인한다 — 박혀 있으면 무엇을 넘기든 그레고리력 요일이 나온다.
        let recognition = sampleRecognition(yearMonth: "2026-08")
        let service = FakeDispatchService(recognizeResult: .success(recognition))

        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        let symbols = ["일", "월", "화", "수", "목", "금", "토"]
        let buddhistDate = buddhist.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let expected = symbols[buddhist.component(.weekday, from: buddhistDate) - 1]
        #expect(expected != "토", "전제가 깨졌다 — 그레고리력과 같은 요일이면 이 테스트는 아무것도 못 잡는다")

        let vm = DispatchReviewViewModel(recognition: recognition, service: service, calendar: buddhist)
        #expect(vm.entries[0].weekday == expected)

        // 그레고리력을 넘기면 실제 요일이 나온다. 2026-08-01은 토요일이다.
        let gregorianVM = DispatchReviewViewModel(recognition: recognition, service: service)
        #expect(gregorianVM.entries[0].weekday == "토")
    }
}
