import XCTest
@testable import ClaudetteCore

final class UsageDecodingTests: XCTestCase {
    func testDecodesFullResponseWithMicrosecondTimestamps() throws {
        let json = """
        {
          "five_hour":        { "utilization": 33.0, "resets_at": "2026-08-01T07:00:00.123456Z" },
          "seven_day":        { "utilization": 13.0, "resets_at": "2026-08-05T00:59:59Z" },
          "seven_day_opus":   null,
          "seven_day_sonnet": { "utilization": 1.0, "resets_at": "2026-08-04T03:00:00Z" },
          "extra_usage":      { "is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null }
        }
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.fiveHour?.utilization, 33.0)
        XCTAssertNotNil(snapshot.fiveHour?.resetsAt)
        XCTAssertEqual(snapshot.sevenDay?.utilization, 13.0)
        XCTAssertNil(snapshot.sevenDayOpus)
        XCTAssertEqual(snapshot.sevenDaySonnet?.utilization, 1.0)
        XCTAssertEqual(snapshot.extraUsage?.isEnabled, false)
        XCTAssertEqual(snapshot.modelWeekly?.label, "SONNET")
    }

    func testDecodesIntegerUtilization() throws {
        let json = #"{"five_hour": {"utilization": 33, "resets_at": null}}"#
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.fiveHour?.utilization, 33.0)
        XCTAssertNil(snapshot.fiveHour?.resetsAt)
    }

    func testDecodesEmptyObject() throws {
        let snapshot = try UsageSnapshot.decode(from: Data("{}".utf8))
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.sevenDay)
        XCTAssertNil(snapshot.modelWeekly)
    }

    func testOpusPreferredOverSonnetForModelWeekly() throws {
        let json = """
        {"seven_day_opus": {"utilization": 5, "resets_at": null},
         "seven_day_sonnet": {"utilization": 9, "resets_at": null}}
        """
        let snapshot = try UsageSnapshot.decode(from: Data(json.utf8))
        XCTAssertEqual(snapshot.modelWeekly?.label, "OPUS")
        XCTAssertEqual(snapshot.modelWeekly?.window.utilization, 5)
    }

    func testPersistedUsageRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudette-tests-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("snapshot.json")
        let snapshot = UsageSnapshot(
            fiveHour: UsageWindow(utilization: 42, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            sevenDay: UsageWindow(utilization: 7, resetsAt: nil))
        let persisted = PersistedUsage(snapshot: snapshot, syncedAt: Date(timeIntervalSince1970: 1_790_000_000))
        persisted.save(to: url)
        let loaded = PersistedUsage.load(from: url)
        XCTAssertEqual(loaded?.snapshot.fiveHour?.utilization, 42)
        XCTAssertEqual(loaded?.syncedAt.timeIntervalSince1970 ?? 0, 1_790_000_000, accuracy: 1)
        try? FileManager.default.removeItem(at: dir)
    }

    func testFractionUsedClamps() {
        XCTAssertEqual(UsageWindow(utilization: 150, resetsAt: nil).fractionUsed, 1.0)
        XCTAssertEqual(UsageWindow(utilization: -5, resetsAt: nil).fractionUsed, 0.0)
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
        let result = CredentialStore.parse(data, source: .file)
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
            scopes: ["user:inference"], subscriptionType: nil, source: .file)
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
        guard case .failure(let reason) = CredentialStore.parse(json("not json"), source: .file) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(reason, .malformed)
    }
}
