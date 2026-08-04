import XCTest
@testable import ClaudetteCore

final class ClaudeOAuthTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("oauth-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var store: OAuthTokenStore {
        OAuthTokenStore(url: directory.appendingPathComponent("oauth-tokens.json"))
    }

    func testPKCEChallengeIsBase64URL() {
        let pkce = ClaudeOAuth.PKCE.generate()
        XCTAssertEqual(pkce.challenge.count, 43)
        for value in [pkce.verifier, pkce.challenge, pkce.state] {
            XCTAssertFalse(value.contains("+"))
            XCTAssertFalse(value.contains("/"))
            XCTAssertFalse(value.contains("="))
        }
        XCTAssertNotEqual(ClaudeOAuth.PKCE.generate().verifier, pkce.verifier)
    }

    func testAuthorizeURLCarriesTheFlow() throws {
        let pkce = ClaudeOAuth.PKCE.generate()
        let components = try XCTUnwrap(URLComponents(
            url: ClaudeOAuth.authorizeURL(pkce), resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], ClaudeOAuth.clientID)
        XCTAssertEqual(query["redirect_uri"], ClaudeOAuth.redirectURI)
        XCTAssertEqual(query["code_challenge"], pkce.challenge)
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["state"], pkce.state)
        XCTAssertEqual(query["scope"], ClaudeOAuth.scope)
    }

    func testParsesTokenResponse() throws {
        let now = Date()
        let tokens = try ClaudeOAuth.parseTokens(Data("""
        {"token_type": "Bearer", "access_token": "at-1", "refresh_token": "rt-1",
         "expires_in": 28800, "scope": "user:profile user:inference"}
        """.utf8), now: now)
        XCTAssertEqual(tokens.accessToken, "at-1")
        XCTAssertEqual(tokens.refreshToken, "rt-1")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(28_800))
        XCTAssertEqual(tokens.scopes, ["user:profile", "user:inference"])
    }

    func testRejectsBodyWithoutAccessToken() {
        XCTAssertThrowsError(try ClaudeOAuth.parseTokens(Data("{}".utf8)))
    }

    func testParsesCallbackRequest() {
        let callback = OAuthCallbackServer.parse(
            "GET /callback?code=abc123&state=xyz HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(callback, OAuthCallbackServer.Callback(code: "abc123", state: "xyz"))
        XCTAssertNil(OAuthCallbackServer.parse("GET /favicon.ico HTTP/1.1\r\n\r\n"))
        XCTAssertNil(OAuthCallbackServer.parse("GET /callback?error=denied HTTP/1.1\r\n\r\n"))
        XCTAssertNil(OAuthCallbackServer.parse("POST /callback?code=x HTTP/1.1\r\n\r\n"))
    }

    func testStoreRoundTripsOwnerOnly() throws {
        let tokens = OAuthTokens(
            accessToken: "at-1", refreshToken: "rt-1",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            scopes: ["user:profile"])
        store.save(tokens)
        XCTAssertEqual(store.load(), tokens)
        XCTAssertTrue(store.isSignedIn)
        let attrs = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("oauth-tokens.json").path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.int16Value, 0o600)
        store.clear()
        XCTAssertNil(store.load())
    }

    private func credentialStore(transport: StubTransport) -> CredentialStore {
        CredentialStore(oauthTokens: store, transport: transport)
    }

    func testFreshOAuthTokensWinWithoutRefresh() async {
        store.save(OAuthTokens(
            accessToken: "at-live", refreshToken: "rt-1",
            expiresAt: Date().addingTimeInterval(3600), scopes: nil))
        let transport = StubTransport(status: 500, body: "")
        switch await credentialStore(transport: transport).load() {
        case .success(let creds):
            XCTAssertEqual(creds.accessToken, "at-live")
        case .failure(let reason):
            XCTFail("Expected oauth credentials, got \(reason)")
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testExpiringTokenIsRefreshedAndPersisted() async {
        store.save(OAuthTokens(
            accessToken: "at-old", refreshToken: "rt-1",
            expiresAt: Date().addingTimeInterval(30), scopes: nil))
        let transport = StubTransport(status: 200, body: """
        {"access_token": "at-new", "refresh_token": "rt-2", "expires_in": 28800}
        """)
        switch await credentialStore(transport: transport).load() {
        case .success(let creds):
            XCTAssertEqual(creds.accessToken, "at-new")
        case .failure(let reason):
            XCTFail("Expected refreshed credentials, got \(reason)")
        }
        XCTAssertEqual(transport.requests.map(\.url), [Endpoints.oauthToken])
        XCTAssertEqual(store.load()?.refreshToken, "rt-2")
    }

    func testRevokedRefreshTokenClearsTheStore() async {
        store.save(OAuthTokens(
            accessToken: "at-old", refreshToken: "rt-dead",
            expiresAt: Date().addingTimeInterval(30), scopes: nil))
        let transport = StubTransport(status: 401, body: "")
        let result = await credentialStore(transport: transport).load()
        XCTAssertEqual(result, .failure(.expired))
        XCTAssertNil(store.load())
    }

    func testNetworkFailureDuringRefreshKeepsGoing() async {
        store.save(OAuthTokens(
            accessToken: "at-old", refreshToken: "rt-1",
            expiresAt: Date().addingTimeInterval(30), scopes: nil))
        let transport = StubTransport(error: URLError(.notConnectedToInternet))
        switch await credentialStore(transport: transport).load() {
        case .success(let creds):
            XCTAssertEqual(creds.accessToken, "at-old")
        case .failure(let reason):
            XCTFail("Expected stale-but-valid credentials, got \(reason)")
        }
        XCTAssertEqual(store.load()?.accessToken, "at-old")
    }
}

final class OAuthCallbackServerLiveTests: XCTestCase {
    func testServesCallbackOverLoopback() async throws {
        let server = try OAuthCallbackServer(port: 54545)
        let fetch = Task { () -> (Int, Bool) in
            try await Task.sleep(nanoseconds: 200_000_000)
            let (data, response) = try await URLSession.shared.data(
                from: URL(string: "http://127.0.0.1:54545/callback?code=abc&state=xyz")!)
            return (
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8)?.contains("connected") == true)
        }
        let callback = try await server.waitForCallback()
        XCTAssertEqual(callback, OAuthCallbackServer.Callback(code: "abc", state: "xyz"))
        let (status, pageOK) = try await fetch.value
        XCTAssertEqual(status, 200)
        XCTAssertTrue(pageOK)
    }
}
