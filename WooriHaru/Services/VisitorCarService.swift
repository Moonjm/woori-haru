import Foundation

// MARK: - 등록 요청

struct VisitorCarRegisterRequest: Sendable, Equatable {
    var carNo: String
    var startDate: Date
    var endDate: Date
    var visitReason: String = ""

    /// 등록 폼이 요구하는 **열세 필드**. 하나라도 빠지면 서버가 조용히 다르게 저장한다.
    /// 값이 필요 없는 칸(`name`·`tel`)도 빈 문자열로 실어 보낸다 — 웹 폼이 그렇게 보낸다.
    func fields(household: VisitorCarHousehold, id: Int?) -> [String: String] {
        [
            "id": id.map(String.init) ?? "",
            "siteName": "none",
            "selectParkingZone": "true",
            "parkingLot": household.parkingLot,
            "parkingZone": household.parkingZone,
            "name": "",
            "carNo": carNo,
            // **빈 값으로 통과한다.** 웹 JS는 막지만 서버는 요구하지 않는다 —
            // 폼 HTML에 「필수입력항목에서 휴대폰 제거」 주석이 남아 있고, 실제로 등록해 확인했다.
            "tel": "",
            "compName": household.dong,
            "deptName": household.ho,
            "address": visitReason,
            "bookStartDate": VisitorCarDateFormat.day.string(from: startDate),
            "bookEndDate": VisitorCarDateFormat.day.string(from: endDate),
        ]
    }
}

// MARK: - 조회 요청

private struct VisitorCarBookingQuery: Encodable, Sendable {
    let page: Int
    let size: Int
    let sort = "desc"
    let sortName = "startDate"
    let userId: String
    /// **`yyyy-MM-dd`** — 이쪽은 날짜만 받는다.
    let startDate: String
    let endDate: String
    let carNo1: String
    let insertType = ""
    let visitReason = ""
    let otherInfo = ""
}

private struct VisitorCarEntryQuery: Encodable, Sendable {
    let page: Int
    let size: Int
    let sort = "desc"
    let sortName = "updateDate"
    let userId: String
    let parkingZoneIdCode = ""
    let carNo: String
    /// **`yyyy-MM-dd HH:mm:ss`** — 날짜만 보내면 500이 떨어진다.
    let startDate: String
    let endDate: String
}

// MARK: - 서비스

protocol VisitorCarServing: Sendable {
    func login(id: String, password: String) async throws
    func logout() async
    func remainingMinutes() async throws -> Int
    func household() async throws -> VisitorCarHousehold
    func register(_ request: VisitorCarRegisterRequest) async throws
    func update(id: Int, _ request: VisitorCarRegisterRequest) async throws
    func delete(id: Int) async throws
    func bookings(from: Date, to: Date, carNo: String, page: Int, size: Int) async throws
        -> VisitorCarPage<VisitorCarBooking>
    func entries(from: Date, to: Date, carNo: String, page: Int, size: Int) async throws
        -> VisitorCarPage<VisitorCarEntry>
}

/// 방문차량 사이트를 다루는 문. **`actor`인 이유는 재로그인을 하나로 모으기 위해서다** —
/// 화면 넷이 동시에 뜨면 세션 만료를 동시에 만나고, 그대로 두면 로그인을 넷 던진다.
actor VisitorCarService: VisitorCarServing {
    static let shared = VisitorCarService()

    private let transport: any VisitorCarTransport
    private let credentials: any VisitorCarCredentialStoring
    private let defaults: UserDefaults
    private let householdKey = "visitorCar.household"

    /// 진행 중인 로그인. 뒤늦게 온 요청은 새로 던지지 않고 이것을 기다린다.
    private var loginTask: Task<Void, any Error>?

    init(
        transport: any VisitorCarTransport = VisitorCarHTTPTransport(),
        credentials: any VisitorCarCredentialStoring = VisitorCarKeychainStore(),
        defaults: UserDefaults = .standard
    ) {
        self.transport = transport
        self.credentials = credentials
        self.defaults = defaults
    }

    // MARK: - 로그인

    func login(id: String, password: String) async throws {
        try await performLogin(id: id, password: password)
        // **성공한 뒤에 저장한다.** 틀린 자격증명을 넣어 두면 이후 재로그인이 영원히 실패한다.
        try credentials.save(VisitorCarCredentials(id: id, password: password))
        // **세대 캐시를 버린다.** 다른 계정으로 로그인했을 수 있다 — 이전 세대의 동·호가
        // 남아 있으면 그걸로 등록이 나가 다른 세대 이름으로 예약이 들어간다.
        defaults.removeObject(forKey: householdKey)
    }

    func logout() async {
        credentials.clear()
        defaults.removeObject(forKey: householdKey)
        await transport.clearCookies()
    }

    // MARK: - 조회

    func remainingMinutes() async throws -> Int {
        let response = try await send { try await self.transport.page(path: "/book-car") }
        guard let minutes = VisitorCarHTMLParser.remainingMinutes(html: response.text) else {
            throw VisitorCarError.remainingTimeUnavailable
        }
        return minutes
    }

    /// 동·호는 계정이 바뀌지 않는 한 그대로다. **한 번 읽고 담아 둔다** —
    /// 매번 부르면 등록 한 번에 왕복이 둘이 된다.
    func household() async throws -> VisitorCarHousehold {
        if let data = defaults.data(forKey: householdKey),
           let cached = try? JSONDecoder().decode(VisitorCarHousehold.self, from: data) {
            return cached
        }

        let response = try await send {
            try await self.transport.form(path: "/book-car/getOriginal", fields: ["id": ""])
        }
        guard let household = VisitorCarHTMLParser.household(html: response.text) else {
            // **빈 동·호로 등록하면 다른 세대 이름으로 예약이 들어간다.** 여기서 막는다.
            throw VisitorCarError.householdUnavailable
        }

        if let data = try? JSONEncoder().encode(household) {
            defaults.set(data, forKey: householdKey)
        }
        return household
    }

    func bookings(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarBooking> {
        let query = VisitorCarBookingQuery(
            page: page,
            size: size,
            userId: try userId(),
            startDate: VisitorCarDateFormat.day.string(from: from),
            endDate: VisitorCarDateFormat.day.string(from: to),
            carNo1: carNo
        )
        let response = try await send {
            try await self.transport.json(path: "/web/book-car/pageList", body: query)
        }
        return try decodePage(response.body)
    }

    func entries(
        from: Date, to: Date, carNo: String, page: Int, size: Int
    ) async throws -> VisitorCarPage<VisitorCarEntry> {
        let query = VisitorCarEntryQuery(
            page: page,
            size: size,
            userId: try userId(),
            carNo: carNo,
            startDate: VisitorCarDateFormat.second.string(from: from),
            endDate: VisitorCarDateFormat.second.string(from: to)
        )
        let response = try await send {
            try await self.transport.json(
                path: "/web/car/reserved-vehicle-entry-status-by-generation-page",
                body: query
            )
        }
        return try decodePage(response.body)
    }

    // MARK: - 등록·수정·삭제

    func register(_ request: VisitorCarRegisterRequest) async throws {
        let fields = request.fields(household: try await household(), id: nil)
        try await submit(path: "/book-car/post", fields: fields)
    }

    func update(id: Int, _ request: VisitorCarRegisterRequest) async throws {
        let fields = request.fields(household: try await household(), id: id)
        try await submit(path: "/book-car/put", fields: fields)
    }

    func delete(id: Int) async throws {
        try await submit(path: "/book-car/delete", fields: ["id": String(id)])
    }

    // MARK: - Private

    /// 302를 만나면 **한 번만** 다시 로그인하고 원 요청을 재시도한다.
    ///
    /// 두 번째도 튕기면 포기한다 — 자격증명이 틀렸다는 뜻이고, 무한히 다시 붙으면
    /// 계정이 잠길 수 있다.
    private func send(
        _ perform: () async throws -> VisitorCarHTTPResponse
    ) async throws -> VisitorCarHTTPResponse {
        let first = try await perform()
        guard first.isLoginRedirect else { return try checkStatus(first) }

        try await reLogin()

        let second = try await perform()
        if second.isLoginRedirect { throw VisitorCarError.sessionExpired }
        return try checkStatus(second)
    }

    /// 302 처리 **뒤에** 본다. 등록·수정·삭제·조회가 500이나 로그인 아닌 HTML을 받으면
    /// 날것의 `DecodingError`가 UI까지 올라가 영어 문구가 뜬다 — 여기서 먼저 가른다.
    private func checkStatus(_ response: VisitorCarHTTPResponse) throws -> VisitorCarHTTPResponse {
        guard response.status >= 400 else { return response }
        throw VisitorCarError.server(response.status)
    }

    /// 진행 중인 로그인이 있으면 **그것을 기다린다.** 동시에 만료를 만난 요청들이
    /// 로그인을 각자 던지지 않게 하는 자리다.
    private func reLogin() async throws {
        do {
            if let existing = loginTask {
                try await existing.value
            } else {
                guard let saved = credentials.load() else { throw VisitorCarError.notLoggedIn }

                let task = Task { [transport] in
                    try await Self.performLogin(
                        transport: transport,
                        id: saved.id,
                        password: saved.password
                    )
                }
                loginTask = task
                defer { loginTask = nil }
                try await task.value
            }
        } catch VisitorCarError.loginFailed {
            // **조용한 재로그인의 실패는 `sessionExpired`로 올린다.** `loginFailed`가 그대로
            // 올라가면 홈 뷰모델이 로그인 카드로 접지 않아(needsLogin은 notLoggedIn·sessionExpired만
            // 본다), 사용자가 붉은 글씨만 보고 빠져나갈 길을 못 찾는다. 저장된 자격증명도
            // 지운다 — 틀린 것이 확인됐으니 남겨 둘 이유가 없고, 지워야 로그인 카드가
            // 곧바로 쓸모 있어진다. **이 변환은 여기(조용한 재로그인)에만 한다** — 사용자가
            // 로그인 카드에서 직접 부르는 `login(id:password:)`는 `loginFailed`를 그대로
            // 올려야 서버가 준 한국어 문구가 카드에 뜬다.
            credentials.clear()
            throw VisitorCarError.sessionExpired
        }
    }

    private func performLogin(id: String, password: String) async throws {
        try await Self.performLogin(transport: transport, id: id, password: password)
    }

    /// **성공과 실패가 둘 다 302다.** 상태코드로 가를 수 없어 `Location`을 본다.
    private static func performLogin(
        transport: any VisitorCarTransport,
        id: String,
        password: String
    ) async throws {
        let response = try await transport.form(
            path: "/do-login",
            fields: ["id": id, "password": password, "loginUserLogout": "N"]
        )

        if response.isLoginRedirect {
            let message = VisitorCarHTMLParser.loginErrorMessage(location: response.location ?? "")
            throw VisitorCarError.loginFailed(message ?? "아이디 또는 비밀번호를 확인해 주세요.")
        }
        guard response.status == 302 else { throw VisitorCarError.server(response.status) }
    }

    private func userId() throws -> String {
        guard let id = credentials.load()?.id else { throw VisitorCarError.notLoggedIn }
        return id
    }

    private func decodePage<T: Decodable & Sendable>(_ data: Data) throws -> VisitorCarPage<T> {
        do {
            return try JSONDecoder().decode(VisitorCarPageResponse<T>.self, from: data).data
        } catch {
            // 여기까지 왔는데 디코딩이 깨지면 사이트가 바뀐 것이다.
            // **원문을 실어 올리지 않는다** — 로그인 페이지 HTML이 통째로 담겨 올 수 있고,
            // 거기에는 세션 값이 섞여 있다. 무엇이 깨졌는지는 파서 테스트가 말한다.
            throw VisitorCarError.network("응답을 읽지 못했습니다.")
        }
    }

    /// 등록·수정·삭제의 공통 꼬리. `result != "success"`면 **서버 `message`를 그대로** 올린다.
    private func submit(path: String, fields: [String: String]) async throws {
        let response = try await send {
            try await self.transport.form(path: path, fields: fields)
        }
        let result = try JSONDecoder().decode(VisitorCarResult.self, from: response.body)
        guard result.isSuccess else {
            throw VisitorCarError.rejected(result.message ?? "요청이 거절되었습니다.")
        }
    }
}
