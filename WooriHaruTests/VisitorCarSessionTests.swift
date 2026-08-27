import Foundation
import Testing
@testable import WooriHaru

struct VisitorCarSessionTests {

    private func makeService(
        transport: FakeVisitorCarTransport,
        credentials: VisitorCarCredentials? = VisitorCarCredentials(id: "10010101", password: "비밀")
    ) -> VisitorCarService {
        VisitorCarService(
            transport: transport,
            credentials: FakeCredentialStore(stored: credentials),
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )
    }

    // MARK: - 로그인

    @Test func 성공_리다이렉트면_로그인이_끝난다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        try await service.login(id: "10010101", password: "비밀")

        #expect(store.saveCount == 1)
        #expect(store.load()?.id == "10010101")
    }

    /// **서버가 준 한국어를 그대로 띄운다.** 앱이 문구를 새로 짓지 않는다.
    @Test func 실패_리다이렉트의_메시지를_그대로_올린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginFailure(message: "아이디 또는 비밀번호가 잘못되었습니다."))
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginFailed("아이디 또는 비밀번호가 잘못되었습니다.")) {
            try await service.login(id: "10010101", password: "틀린것")
        }
        // 실패한 자격증명을 저장하면 다음 재로그인이 영원히 실패한다.
        #expect(store.saveCount == 0)
    }

    /// **`Location`이 없는 302는 「판단할 수 없음」이다** — 거절이 아니다. 「로그인
    /// 리다이렉트가 아니면 성공」으로 읽으면 이 경우가 성공으로 둔갑해 확인되지 않은
    /// 자격증명이 Keychain에 저장된다. 그렇다고 「거절」(`loginFailed`)로 읽어서도 안 된다 —
    /// 서버가 아이디·비밀번호를 틀렸다고 말한 적이 없기 때문이다(R1).
    @Test func 위치_없는_302는_판단할_수_없는_로그인이다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", VisitorCarHTTPResponse(status: 302, location: nil, body: Data()))
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            try await service.login(id: "10010101", password: "비밀")
        }
        #expect(store.saveCount == 0)
    }

    /// **문서화된 도착지가 아닌 302도 「판단할 수 없음」이다.** 점검 페이지 등 다른 곳으로
    /// 튀는 302를 성공으로 읽으면 확인되지 않은 자격증명이 Keychain에 저장된다. 이 경우도
    /// 서버가 거절한 게 아니므로 `loginFailed`가 아니라 `loginUnavailable`이다(R1).
    @Test func 다른_경로로_가는_302는_판단할_수_없는_로그인이다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(
            "/do-login",
            VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/maintenance", body: Data())
        )
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            try await service.login(id: "10010101", password: "비밀")
        }
        #expect(store.saveCount == 0)
    }

    /// 302가 아닌 응답(5xx 등)도 「판단할 수 없음」이다 — 성공 판정은 `/nxpmsc/book-car`
    /// 302 하나뿐이지만, 실패로 보이는 건 전부 거절(`loginFailed`)은 아니다(R1).
    @Test func 리다이렉트가_아니면_판단할_수_없는_로그인이다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", VisitorCarHTTPResponse(status: 500, location: nil, body: Data()))
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            try await service.login(id: "10010101", password: "비밀")
        }
        #expect(store.saveCount == 0)
    }

    /// **성공 리다이렉트가 `;jsessionid=…`를 달고 와도 받아들인다.** `URLComponents`는
    /// 매트릭스 파라미터를 경로에서 떼지 않는다 — 실패 리다이렉트는 이미 이 접미사를
    /// 달고 오는 것이 관찰됐으니, 성공 쪽도 언젠가 그럴 수 있다(R2).
    @Test func 성공_경로에_세션ID_접미사가_붙어도_받아들인다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(
            "/do-login",
            VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/book-car;jsessionid=ABC123", body: Data())
        )
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        try await service.login(id: "10010101", password: "비밀")

        #expect(store.saveCount == 1)
    }

    /// **다른 경로에 세션ID 접미사가 붙어도 여전히 거부한다.** 접미사를 떼는 것이 경로
    /// 비교 자체를 느슨하게 만들면 안 된다 — 딱 `/nxpmsc/book-car` 하나만 허용해야
    /// fail-closed가 유지된다(R2).
    @Test func 다른_경로에_세션ID_접미사가_붙으면_여전히_거부한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(
            "/do-login",
            VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/maintenance;jsessionid=ABC123", body: Data())
        )
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            try await service.login(id: "10010101", password: "비밀")
        }
        #expect(store.saveCount == 0)
    }

    // MARK: - 세션 만료

    /// 302를 만나면 **다시 로그인하고 원 요청을 한 번 더** 보낸다.
    @Test func 만료되면_재로그인하고_다시_보낸다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enqueue("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.enqueue("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        let minutes = try await service.remainingMinutes()

        #expect(minutes == 6000)
        #expect(transport.callCount("/do-login") == 1)
        #expect(transport.callCount("/book-car") == 2)
    }

    /// **되풀이하지 않는다.** 두 번째도 튕기면 자격증명이 틀린 것이고,
    /// 무한히 다시 붙으면 계정이 잠길 수 있다.
    @Test func 재로그인_후에도_튕기면_포기한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.sessionExpired) {
            _ = try await service.remainingMinutes()
        }
        #expect(transport.callCount("/do-login") == 1)
        #expect(transport.callCount("/book-car") == 2)
    }

    /// 세대가 사이트에서 비밀번호를 바꾸면 저장된 자격증명으로 하는 **조용한** 재로그인이
    /// 거절된다. `loginFailed`가 그대로 올라가면 홈 뷰모델이 로그인 카드로 접지 않는다
    /// (`needsLogin`은 `notLoggedIn`·`sessionExpired`만 본다) — `sessionExpired`로 바꿔야
    /// 빠져나갈 길이 생긴다. 저장된 자격증명도 지워야 로그인 카드가 곧바로 쓸모 있다.
    @Test func 재로그인이_거절되면_세션만료로_바뀌고_저장된_계정을_지운다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", FakeVisitorCarTransport.loginFailure(message: "비밀번호가 바뀌었습니다."))
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "옛비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.sessionExpired) {
            _ = try await service.remainingMinutes()
        }
        #expect(store.load() == nil)
    }

    /// **조용한 재로그인 중 서버가 500을 주면 계정을 지키고 `sessionExpired`도 보고하지
    /// 않는다.** 일시적 오류를 거절로 오인해 멀쩡한 자격증명을 지우면, 다음 방문 때
    /// 사용자가 로그인 카드부터 다시 시작해야 한다(R1).
    @Test func 재로그인_중_500이_오면_계정을_지키고_판단할_수_없음을_보고한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", VisitorCarHTTPResponse(status: 500, location: nil, body: Data()))
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            _ = try await service.remainingMinutes()
        }
        // **일시적 오류가 멀쩡한 자격증명을 지우면 안 된다** — 여기가 이 라운드의 핵심이다.
        #expect(store.load()?.id == "10010101")
    }

    /// **조용한 재로그인 중 알 수 없는 곳(`/nxpmsc/login`도 `/nxpmsc/book-car`도 아닌 302)으로
    /// 튀어도 계정을 지킨다.** 판단할 수 없는 응답과 명시적 거절은 다르다(R1).
    @Test func 재로그인_중_알_수_없는_경로로_튀면_계정을_지키고_판단할_수_없음을_보고한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        transport.stub("/do-login", VisitorCarHTTPResponse(status: 302, location: "/nxpmsc/maintenance", body: Data()))
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await #expect(throws: VisitorCarError.loginUnavailable) {
            _ = try await service.remainingMinutes()
        }
        #expect(store.load()?.id == "10010101")
    }

    @Test func 저장된_계정이_없으면_로그인이_필요하다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.loginRedirect())
        let service = makeService(transport: transport, credentials: nil)

        await #expect(throws: VisitorCarError.notLoggedIn) {
            _ = try await service.remainingMinutes()
        }
        #expect(transport.callCount("/do-login") == 0)
    }

    /// 화면 넷이 동시에 뜨면 만료를 동시에 만난다. **로그인은 하나여야 한다.**
    ///
    /// **세션 대역을 켜고 시험한다.** 큐에 302를 넷 쌓아 두는 방식으로는 이 성질을 잴 수
    /// 없다 — 그건 「로그인에 성공했는데도 여전히 튕기는」 상황이고, 그때는 로그인을 네 번
    /// 하는 것이 오히려 맞다. 우리가 붙잡고 싶은 것은 **한 번 붙고 나면 나머지는 그냥 통과**다.
    @Test func 동시_요청이_로그인을_하나만_던진다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.enableSession()
        transport.stub("/book-car", FakeVisitorCarTransport.ok(VisitorCarFixture.bookCarPage))
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { _ = try? await service.remainingMinutes() }
            }
        }

        #expect(transport.callCount("/do-login") == 1)
    }

    /// **낡은 302는 다시 로그인하지 않는다.** 요청 A가 302를 만나 재로그인을 끝낸
    /// *뒤에*, 그 로그인이 있기 전에 나갔던 요청 B의 302가 뒤늦게 도착하는 상황을
    /// 흉내 낸다 — B는 A가 이미 세션을 살려 놓은 것을 알아채고 조용히 넘어가야 한다.
    /// 실제 동시성을 흉내 내는 대신 `seenGeneration`을 손으로 낡게 넘겨 결정론적으로 확인한다.
    @Test func 낡은_세대로_들어온_재로그인_요청은_다시_로그인하지_않는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        // 요청 A: 302를 만나 재로그인해서 세대가 0→1로 오른다.
        try await service.reLogin(seenGeneration: 0)
        #expect(transport.callCount("/do-login") == 1)

        // 요청 B: A보다 먼저 나갔던 요청의 302다 — 세대는 여전히 0을 봤다.
        // 하지만 그 사이 로그인이 이미 끝나 세션은 살아 있다. 다시 로그인할 이유가 없다.
        try await service.reLogin(seenGeneration: 0)

        #expect(transport.callCount("/do-login") == 1)
    }

    /// 진짜로 늦게 시작한 요청(세대를 새로 찍은 요청)이 302를 만나면 **정상적으로
    /// 다시 로그인한다** — F1의 최적화가 정상 경로를 깨지 않았는지 확인한다.
    @Test func 최신_세대로_들어온_재로그인_요청은_정상적으로_로그인한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let service = makeService(transport: transport)

        try await service.reLogin(seenGeneration: 0)
        #expect(transport.callCount("/do-login") == 1)

        // 이번엔 로그인이 끝난 **뒤에** 세대를 새로 찍었다고 가정한다 — 진짜 만료다.
        try await service.reLogin(seenGeneration: 1)

        #expect(transport.callCount("/do-login") == 2)
    }

    // MARK: - 잔여시간·세대

    /// 마크업이 바뀌면 크래시가 아니라 「불러오지 못했습니다」다.
    @Test func 잔여시간_필드가_없으면_오류다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car", FakeVisitorCarTransport.ok("<html>바뀐 화면</html>"))
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.remainingTimeUnavailable) {
            _ = try await service.remainingMinutes()
        }
    }

    /// 동·호는 계정이 바뀌지 않는 한 그대로다 — **두 번째부터는 캐시를 쓴다.**
    @Test func 세대_정보를_한_번만_읽는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        let service = makeService(transport: transport)

        let first = try await service.household()
        let second = try await service.household()

        #expect(first == second)
        #expect(first.dong == "1001")
        #expect(transport.callCount("/book-car/getOriginal") == 1)
    }

    // MARK: - 등록

    /// 등록 폼은 필드 **열셋**을 다 실어야 한다. 하나라도 빠지면 서버가 조용히 다르게 저장한다.
    @Test func 등록_폼에_열세_필드를_싣는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/post", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let service = makeService(transport: transport)
        let day = Date(timeIntervalSince1970: 1784300400)

        try await service.register(
            VisitorCarRegisterRequest(carNo: "12가3456", startDate: day, endDate: day, visitReason: "택배")
        )

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/post" })?.fields)
        #expect(sent.count == 13)
        #expect(sent["carNo"] == "12가3456")
        #expect(sent["compName"] == "1001")
        #expect(sent["deptName"] == "0101")
        #expect(sent["parkingLot"] == "1")
        #expect(sent["bookStartDate"] == "2026-07-18")
        #expect(sent["bookEndDate"] == "2026-07-18")
        #expect(sent["address"] == "택배")
        #expect(sent["id"] == "")
        #expect(sent["siteName"] == "none")
        #expect(sent["selectParkingZone"] == "true")
        // **휴대폰은 빈 값으로 보낸다** — 서버가 요구하지 않는 것을 확인했다.
        #expect(sent["tel"] == "")
        #expect(sent["name"] == "")
    }

    @Test func 수정은_id를_채워_보낸다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        transport.stub("/book-car/put", FakeVisitorCarTransport.ok(VisitorCarFixture.successResult))
        let service = makeService(transport: transport)
        let day = Date(timeIntervalSince1970: 1784300400)

        try await service.update(
            id: 25752,
            VisitorCarRegisterRequest(carNo: "12가3456", startDate: day, endDate: day, visitReason: "")
        )

        let sent = try #require(transport.formFields.last(where: { $0.path == "/book-car/put" })?.fields)
        #expect(sent["id"] == "25752")
    }

    /// `result != "success"`면 **서버 `message`를 그대로** 올린다.
    @Test func 거절되면_서버_메시지를_그대로_올린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub(
            "/book-car/delete",
            FakeVisitorCarTransport.ok(#"{"result":"fail","message":"입차 후 삭제 불가능합니다."}"#)
        )
        let service = makeService(transport: transport)

        await #expect(throws: VisitorCarError.rejected("입차 후 삭제 불가능합니다.")) {
            try await service.delete(id: 25752)
        }
    }

    // MARK: - 조회

    /// **날짜 포맷이 엔드포인트별로 갈린다.** 진입 현황에 날짜만 보내면 500이다.
    @Test func 조회_바디의_날짜_포맷이_갈린다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/web/book-car/pageList", FakeVisitorCarTransport.ok(VisitorCarFixture.emptyBookingPage))
        transport.stub("/web/car/reserved-vehicle-entry-status-by-generation-page",
                       FakeVisitorCarTransport.ok(VisitorCarFixture.emptyBookingPage))
        let service = makeService(transport: transport)
        let from = Date(timeIntervalSince1970: 1784300400)
        let to = Date(timeIntervalSince1970: 1784386799)

        _ = try await service.bookings(from: from, to: to, carNo: "", page: 0, size: 10)
        _ = try await service.entries(from: from, to: to, carNo: "", page: 0, size: 10)

        let bookingBody = try #require(transport.jsonBodies.first { $0.path == "/web/book-car/pageList" }?.body)
        let entryBody = try #require(
            transport.jsonBodies.first { $0.path == "/web/car/reserved-vehicle-entry-status-by-generation-page" }?.body
        )
        let booking = try #require(try JSONSerialization.jsonObject(with: bookingBody) as? [String: Any])
        let entry = try #require(try JSONSerialization.jsonObject(with: entryBody) as? [String: Any])

        #expect(booking["startDate"] as? String == "2026-07-18")
        #expect(booking["userId"] as? String == "10010101")
        #expect(entry["startDate"] as? String == "2026-07-18 00:00:00")
        #expect(entry["endDate"] as? String == "2026-07-18 23:59:59")
    }

    /// 다른 세대 계정으로 로그인했을 수 있다. **세대 캐시가 살아 있으면 이전 세대의
    /// 동·호로 등록이 나간다** — 파서가 빈 동·호에 `nil`을 돌려주면서까지 막으려던 피해다.
    @Test func 로그인하면_세대_캐시를_버리고_다시_읽는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        transport.stub("/book-car/getOriginal", FakeVisitorCarTransport.ok(VisitorCarFixture.registerForm))
        let defaults = UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        let stale = VisitorCarHousehold(dong: "9999", ho: "9999", parkingLot: "1", parkingZone: "1")
        defaults.set(try JSONEncoder().encode(stale), forKey: "visitorCar.household")
        let service = VisitorCarService(transport: transport, credentials: FakeCredentialStore(), defaults: defaults)

        try await service.login(id: "10010101", password: "비밀")
        let household = try await service.household()

        #expect(household.dong == "1001")
        #expect(transport.callCount("/book-car/getOriginal") == 1)
    }

    // MARK: - P1: 로그인 도중 로그아웃

    /// **로그인이 응답을 기다리는 사이 로그아웃이 먼저 끝나면, 뒤늦게 재개된 로그인이
    /// 지워진 자격증명을 되살리면 안 된다.** `actor`는 재진입이 가능해서 실제로 이런
    /// 순서가 벌어질 수 있다 — 진짜 동시성으로 재현하는 대신, 로그아웃을 먼저 실행해
    /// 세대를 0→1로 올려 두고, 로그인은 자기가 나가기 전에 봤던 세대(0)를 그대로 들고
    /// 이어진다고 손으로 흉내 낸다(`seenGeneration: 0`) — 스케줄링 순서에 기대지 않는다.
    @Test func 로그인_도중_로그아웃하면_자격증명을_되살리지_않는다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "옛비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        // 사용자가 설정에서 로그아웃한다 — 세대가 0→1로 오르고 자격증명이 지워진다.
        await service.logout()
        #expect(store.load() == nil)

        // 그 전에 나가 있던 로그인이 뒤늦게 성공 응답을 받고 재개된다. 자기가 나가기
        // 전 세대(0)를 그대로 들고 있으므로 지금 세대(1)와 어긋난다 — 결과를 버린다.
        await #expect(throws: VisitorCarError.notLoggedIn) {
            try await service.login(id: "10010101", password: "새비밀", seenGeneration: 0)
        }

        // 되살아나지 않는다. 지워진 채로 남는다.
        #expect(store.load() == nil)
        #expect(store.saveCount == 0)
    }

    /// **정상 경로(로그아웃이 끼지 않은 경우)는 그대로 저장하고 세대를 올린다** — P1의
    /// 변경이 평범한 로그인까지 버리지 않는지 확인한다.
    @Test func 로그아웃_없이_끝난_로그인은_정상적으로_저장한다() async throws {
        let transport = FakeVisitorCarTransport()
        transport.stub("/do-login", FakeVisitorCarTransport.loginSuccess())
        let store = FakeCredentialStore()
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        try await service.login(id: "10010101", password: "비밀", seenGeneration: 0)

        #expect(store.load()?.id == "10010101")
        #expect(store.saveCount == 1)
        // 세대가 실제로 올랐는지는 다음 재로그인이 "낡은 세대(0)"로 판정되는지로
        // 간접 확인한다 — 이미 세대 1이므로 `/do-login`을 다시 부르지 않아야 한다.
        try await service.reLogin(seenGeneration: 0)
        #expect(transport.callCount("/do-login") == 1)
    }

    /// **조용한 재로그인이 응답을 받은 뒤 로그아웃이 먼저 끝나 있으면, 방금 세운 쿠키를
    /// 지운다.** 재로그인 자체는 자격증명을 저장하지 않지만 서버에 새 세션 쿠키를 남긴다
    /// — 로그아웃이 지운 쿠키 저장소에 뒤늦게 쿠키가 다시 채워지면 로그아웃한 사용자가
    /// 조용히 다시 로그인된 세션을 손에 쥔다. `commitReLogin(seenGeneration:)`을 직접 불러
    /// 「재로그인 성공 직후 로그아웃이 끼어든」 순간을 결정론적으로 재현한다.
    @Test func 재로그인_완료_후_로그아웃이_끼면_쿠키를_지운다() async throws {
        let transport = FakeVisitorCarTransport()
        let service = makeService(transport: transport)

        // 재로그인이 세대 0을 보고 시작해 서버 응답까지 받았다(새 쿠키가 섰다). 그런데
        // 그 사이 로그아웃이 세대를 0→1로 올렸다.
        await service.logout()
        let clearedByLogout = transport.clearCookiesCount

        await service.commitReLogin(seenGeneration: 0)

        // 로그아웃이 지운 것과 별개로, 재로그인이 방금 세운 쿠키를 스스로 한 번 더 지운다.
        #expect(transport.clearCookiesCount == clearedByLogout + 1)
    }

    /// **로그아웃이 끼지 않은 정상 경로는 쿠키를 지키고 세대를 올린다.**
    @Test func 재로그인_완료_후_로그아웃이_없으면_쿠키를_지키고_세대를_올린다() async throws {
        let transport = FakeVisitorCarTransport()
        let service = makeService(transport: transport)

        await service.commitReLogin(seenGeneration: 0)

        #expect(transport.clearCookiesCount == 0)
        // 세대가 올랐는지는 다음 `reLogin`이 "낡은 세대(0)"로 판정돼 아무것도 부르지
        // 않는 것으로 간접 확인한다.
        try await service.reLogin(seenGeneration: 0)
        #expect(transport.callCount("/do-login") == 0)
    }

    @Test func 로그아웃하면_계정과_쿠키를_버린다() async throws {
        let transport = FakeVisitorCarTransport()
        let store = FakeCredentialStore(stored: VisitorCarCredentials(id: "10010101", password: "비밀"))
        let service = VisitorCarService(
            transport: transport,
            credentials: store,
            defaults: UserDefaults(suiteName: "visitorcar.tests.\(UUID().uuidString)")!
        )

        await service.logout()

        #expect(store.load() == nil)
        #expect(transport.clearCookiesCount == 1)
    }
}
