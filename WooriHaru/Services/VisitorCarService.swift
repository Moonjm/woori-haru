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

    /// **성공한 로그인마다 하나씩 오른다.** 뒤늦게 도착한 302가 이미 끝난 로그인
    /// 이전에 나간 요청의 것인지 가리는 데 쓴다 — `send(_:)`가 요청을 보내기 직전 값을
    /// 들고 있다가, 재로그인에 넘겨 「내가 본 302가 최신 로그인보다 오래됐는가」를 묻는다.
    private var loginGeneration = 0

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
        // **이 로그인도 세대를 올린다.** 사용자가 로그인 카드에서 직접 붙는 것도 새 세션을
        // 여는 일이다 — 여기서 올리지 않으면, 이 로그인 직전에 나갔던 뒤늦은 302가 자기
        // 세대를 낡은 것으로 잘못 판정해 불필요한 재로그인을 또 던질 수 있다.
        loginGeneration += 1
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
        // **요청을 내보내기 전에 세대를 찍어 둔다.** 이 요청이 받은 302가 지금 붙잡고 있는
        // 세션 이전 것인지, 그 사이 다른 요청이 이미 로그인을 끝내 놨는지를 나중에
        // `reLogin(seenGeneration:)`이 이 값으로 가른다.
        let generation = loginGeneration
        let first = try await perform()
        guard first.isLoginRedirect else { return try checkStatus(first) }

        try await reLogin(seenGeneration: generation)

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
    ///
    /// `seenGeneration`은 이 302를 만든 요청이 나가기 **직전의** 세대다. 그 요청이
    /// 느려서 302가 늦게 도착한 사이 다른 요청이 이미 로그인을 끝냈다면
    /// (`loginGeneration > seenGeneration`), 이 302는 그 로그인이 있기 전의 낡은 세션에
    /// 대고 보낸 요청의 결과일 뿐이다 — 세션은 이미 살아 있으므로 다시 로그인할 필요가
    /// 없다. **호출자(`send`)가 원 요청을 재시도하는 것으로 충분하다.** 여기서 다시
    /// 로그인하면 이미 살아 있는 세션 위에 평문 비밀번호를 한 번 더 얹어 보내고
    /// `JSESSIONID`를 불필요하게 새로 발급받아, 그 사이 물려 있는 다른 재시도를 흔든다.
    ///
    /// 테스트가 이 세대 판정을 직접 걸 수 있도록 `private`이 아니라 내부 접근으로 둔다.
    func reLogin(seenGeneration: Int) async throws {
        guard loginGeneration <= seenGeneration else { return }
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
                // **이 로그인을 우리가 직접 시작했을 때만 세대를 올린다.** 남의 `loginTask`를
                // 기다리기만 한 다른 호출자들도 이 분기를 타면, 로그인 한 번의 성공이
                // 여러 번 세어져 세대가 실제 로그인 횟수보다 빨리 앞서 간다.
                loginGeneration += 1
            }
        } catch VisitorCarError.loginFailed {
            // **조용한 재로그인의 "거절"만 `sessionExpired`로 올린다.** `loginFailed`가 그대로
            // 올라가면 홈 뷰모델이 로그인 카드로 접지 않아(needsLogin은 notLoggedIn·sessionExpired만
            // 본다), 사용자가 붉은 글씨만 보고 빠져나갈 길을 못 찾는다. 저장된 자격증명도
            // 지운다 — 서버가 명시적으로 거절했으니(=`loginFailed`) 남겨 둘 이유가 없고,
            // 지워야 로그인 카드가 곧바로 쓸모 있어진다. **이 변환은 여기(조용한 재로그인)에만
            // 한다** — 사용자가 로그인 카드에서 직접 부르는 `login(id:password:)`는
            // `loginFailed`를 그대로 올려야 서버가 준 한국어 문구가 카드에 뜬다.
            //
            // **`loginUnavailable`은 이 `catch`가 잡지 않는다** — 여기서 걸러지지 않고
            // 그대로 위로 전파된다. 일시적 500·점검 페이지처럼 서버가 자격증명을 거절한
            // 적이 없는 경우까지 여기서 자격증명을 지우면, 서버가 잠깐 아팠을 뿐인데
            // 멀쩡한 계정이 지워지고 사용자가 로그인 카드로 튕겨 나간다.
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
            // **서버가 명시적으로 거절했다.** `Location`이 `/nxpmsc/login`으로 시작하면
            // 아이디·비밀번호가 틀렸다는 뜻이다 — `reLogin`이 이 경우에만 저장된
            // 자격증명을 지운다(아래 `loginUnavailable`과 여기를 갈라 둔 이유).
            let message = VisitorCarHTMLParser.loginErrorMessage(location: response.location ?? "")
            throw VisitorCarError.loginFailed(message ?? "아이디 또는 비밀번호를 확인해 주세요.")
        }

        // **성공은 `/nxpmsc/book-car`로 가는 302 하나뿐이다.** 「로그인 리다이렉트가
        // 아니면 성공」으로 읽으면 fail-open이 된다 — `Location`이 없는 302나 점검·오류
        // 페이지로 가는 302까지 성공으로 둔갑해, 확인되지 않은 자격증명을 Keychain에
        // 써 버린다(`isLoginRedirect`는 이미 파싱 실패에 대해 fail-closed인데, 그
        // 위를 부르는 이 자리만 여태 fail-open이었다). 여기서는 반대로 문 하나만 열어
        // 둔다: 확실히 아는 성공 도착지가 아니면 전부 실패로 본다.
        // **트레이드오프를 받아들인다:** 사이트가 언젠가 로그인 성공 후 도착 페이지를
        // 바꾸면 이 코드도 함께 깨진다 — 다만 그 깨짐은 로그인 카드에 오류로 시끄럽게
        // 드러나 한 커밋으로 고칠 수 있다. 검증하지 않은 자격증명을 Keychain에 조용히
        // 저장해 두고 사용자가 나중에야 이유 모를 실패에 갇히는 쪽이 훨씬 나쁘다.
        // **`/nxpmsc/book-car`는 계정 하나로 관찰한 값이다** — 다른 계정에서 로그인이
        // 안 되면 이 도착지부터 의심한다(설계 문서 「확인하지 않은 것」 참고).
        //
        // **경로는 매트릭스 파라미터를 떼고 비교한다.** `URLComponents`는 `;jsessionid=…`를
        // 경로에서 벗겨내지 않는다 — 실패 리다이렉트는 이미 이 접미사를 달고 오는 것이
        // 관찰됐다(`/nxpmsc/login;jsessionid=…`). 성공 쪽에서는 아직 본 적 없지만, 서버가
        // 같은 세션 메커니즘으로 붙이는 값이라 언젠가 붙지 않는다는 보장이 없다. 떼고
        // 비교해도 fail-closed는 그대로다 — 여전히 경로 하나만 허용한다.
        guard response.status == 302,
              let location = response.location,
              let path = URLComponents(string: location)?.path,
              stripMatrixParameters(from: path) == "/nxpmsc/book-car"
        else {
            // **여기 걸리는 것은 "거절"이 아니라 "판단할 수 없음"이다.** 302가 아니거나,
            // 302인데 `Location`이 없거나, `book-car`도 `login`도 아닌 낯선 곳으로 튄
            // 경우다 — 일시적 500, 점검 페이지, 알 수 없는 리다이렉트가 여기 해당한다.
            // 서버가 아이디·비밀번호를 거절했다고 말한 적이 없으므로 `loginFailed`로
            // 올리면 안 된다 — 올리면 `reLogin`이 그걸 거절로 오인해 멀쩡한 자격증명을
            // 지운다. 서버가 이 경우엔 메시지를 주지 않으므로 문구는 여기서 직접 짓는다.
            throw VisitorCarError.loginUnavailable
        }
    }

    /// `;jsessionid=…` 같은 매트릭스 파라미터를 경로에서 뗀다 — `;` 앞부분만 남긴다.
    private static func stripMatrixParameters(from path: String) -> String {
        String(path.prefix(while: { $0 != ";" }))
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
