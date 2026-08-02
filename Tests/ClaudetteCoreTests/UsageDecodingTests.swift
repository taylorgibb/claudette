import XCTest
@testable import ClaudetteCore

/// `limits[]` is the whole contract: which limits exist depends on the plan,
/// and any of them can be absent.
final class UsageDecodingTests: XCTestCase {
    private let payload = """
    {
      "rate_limit_tier": "default_claude_max_20x",
      "limits": [
        {"kind": "session", "group": "session", "percent": 4,
         "resets_at": "2026-08-02T21:50:00.244749+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_all", "group": "weekly", "percent": 13,
         "resets_at": "2026-08-07T05:00:00.244770+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 12,
         "resets_at": "2026-08-07T05:00:00.245002+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null},
         "is_active": false}
      ]
    }
    """

    func testDecodesEveryLimitKind() throws {
        let snapshot = try UsageSnapshot.decode(from: Data(payload.utf8))
        XCTAssertEqual(snapshot.session?.percentUsed, 4)
        XCTAssertNotNil(snapshot.session?.resetsAt)
        XCTAssertEqual(snapshot.weekly?.percentUsed, 13)
        XCTAssertEqual(snapshot.rateLimitTier, "default_claude_max_20x")
    }

    func testScopedLimitCarriesItsModelName() throws {
        let snapshot = try UsageSnapshot.decode(from: Data(payload.utf8))
        let model = try XCTUnwrap(snapshot.weeklyForModel)
        XCTAssertEqual(model.modelName, "Fable")
        XCTAssertEqual(model.window.percentUsed, 12)
        XCTAssertEqual(snapshot.limits.filter { $0.modelName != nil }.count, 1)
    }

    func testMicrosecondTimestampsParse() throws {
        let json = #"{"limits":[{"kind":"session","percent":33,"resets_at":"2026-08-01T07:00:00.123456Z"}]}"#
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.session?.percentUsed, 33.0)
        XCTAssertNotNil(snapshot.session?.resetsAt)
    }

    func testDecodesEmptyObject() throws {
        let snapshot = try UsageSnapshot.decode(from: Data("{}".utf8))
        XCTAssertTrue(snapshot.limits.isEmpty)
        XCTAssertNil(snapshot.session)
        XCTAssertNil(snapshot.weekly)
        XCTAssertNil(snapshot.weeklyForModel)
    }

    /// An unrecognised kind must not fail the decode and take the whole array
    /// with it — a new limit kind should cost us that one row, no more.
    func testUnknownKindIsKeptAsOther() throws {
        let json = """
        {"limits":[{"kind":"monthly_new_thing","percent":1,"resets_at":null},
                   {"kind":"session","percent":50,"resets_at":null}]}
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.limits[0].kind, .other("monthly_new_thing"))
        XCTAssertEqual(snapshot.session?.percentUsed, 50)
    }

    /// Decoding the array in one go means a single malformed row throws away
    /// every other limit, leaving a snapshot with no windows and no error.
    func testOneMalformedRowCostsOnlyThatRow() throws {
        let json = """
        {"limits":[{"kind":"session","percent":7,"resets_at":null},
                   {"kind":"weekly_all","percent":null,"resets_at":null},
                   "not even an object",
                   {"kind":"weekly_scoped","percent":9,"resets_at":null,
                    "scope":{"model":{"display_name":"Fable"}}}]}
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.limits.count, 2)
        XCTAssertEqual(snapshot.session?.percentUsed, 7)
        XCTAssertEqual(snapshot.weeklyForModel?.modelName, "Fable")
        XCTAssertNil(snapshot.weekly, "the null-percent row is the only casualty")
    }

    func testPersistedUsageRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudette-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("snapshot.json")
        let snapshot = UsageSnapshot(limits: [
            UsageLimit(
                kind: .session,
                window: LimitWindow(percentUsed: 42, resetsAt: Date(timeIntervalSince1970: 1_800_000_000))),
            UsageLimit(kind: .weeklyAllModels, window: LimitWindow(percentUsed: 7, resetsAt: nil)),
        ])
        let persisted = PersistedUsage(snapshot: snapshot, syncedAt: Date(timeIntervalSince1970: 1_790_000_000))
        persisted.save(to: url)
        let loaded = PersistedUsage.load(from: url)
        XCTAssertEqual(loaded?.snapshot.session?.percentUsed, 42)
        XCTAssertEqual(loaded?.syncedAt.timeIntervalSince1970 ?? 0, 1_790_000_000, accuracy: 1)
        try? FileManager.default.removeItem(at: dir)
    }

    func testWindowLengthsComeFromTheKind() {
        XCTAssertEqual(UsageLimit.Kind.session.windowDuration, 5 * 3600)
        XCTAssertEqual(UsageLimit.Kind.weeklyAllModels.windowDuration, 7 * 86_400)
        XCTAssertEqual(UsageLimit.Kind.weeklyPerModel.windowDuration, 7 * 86_400)
    }

    func testPercentAccessorsClampAndInvert() {
        XCTAssertEqual(LimitWindow(percentUsed: 150, resetsAt: nil).fractionUsed, 1.0)
        XCTAssertEqual(LimitWindow(percentUsed: -5, resetsAt: nil).fractionUsed, 0.0)
        // The number the island actually renders is what's left, not what's used.
        XCTAssertEqual(LimitWindow(percentUsed: 17, resetsAt: nil).percentRemaining, 83)
        XCTAssertEqual(LimitWindow(percentUsed: 150, resetsAt: nil).percentRemaining, 0)
    }
}

final class CredentialParsingTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testParsesHealthyCredentials() throws {
        let future = (Date().timeIntervalSince1970 + 3600) * 1000
        let data = json("""
        {"claudeAiOauth": {"accessToken": "sk-ant-oat01-abc", "refreshToken": "r",
         "expiresAt": \(future), "scopes": ["user:inference", "user:profile"],
         "subscriptionType": "max"}}
        """)
        let result = CredentialStore.parse(data, source: .credentialsFile)
        guard case .success(let creds) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(creds.accessToken, "sk-ant-oat01-abc")
        XCTAssertEqual(creds.subscriptionType, "max")
        guard case .success = CredentialStore.validate(creds) else {
            return XCTFail("expected validation to pass")
        }
    }

    func testMcpOnlyKeychainShapeIsDistinctError() {
        let data = json(#"{"mcpOAuth": {"someServer": {"accessToken": "x"}}}"#)
        guard case .failure(let reason) = CredentialStore.parse(data, source: .keychain) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .mcpOnly)
    }

    func testInferenceOnlyScopeFailsValidation() {
        let creds = Credentials(
            accessToken: "t", expiresAt: nil,
            scopes: ["user:inference"], subscriptionType: nil, source: .credentialsFile)
        guard case .failure(let reason) = CredentialStore.validate(creds) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .scopeMissing)
    }

    func testExpiredTokenFailsValidation() {
        let creds = Credentials(
            accessToken: "t", expiresAt: Date(timeIntervalSinceNow: -60),
            scopes: nil, subscriptionType: nil, source: .keychain)
        guard case .failure(let reason) = CredentialStore.validate(creds) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .expired)
    }

    func testGarbageIsMalformed() {
        guard case .failure(let reason) = CredentialStore.parse(json("not json"), source: .credentialsFile) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .malformed)
    }
}
