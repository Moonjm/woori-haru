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
