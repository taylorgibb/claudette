import XCTest
@testable import ClaudetteCore

final class PostHogReporterTests: XCTestCase {
    private let host = URL(string: "https://example.invalid")!

    private func makeReporter(transport: StubTransport) -> PostHogReporter {
        PostHogReporter(
            projectToken: "phc_test",
            host: host,
            installID: "11111111-2222-3333-4444-555555555555",
            transport: transport)
    }

    private func batch(from transport: StubTransport) throws -> [[String: Any]] {
        let body = try XCTUnwrap(transport.requests.last?.body)
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: body) as? [String: Any])
        return try XCTUnwrap(object["batch"] as? [[String: Any]])
    }

    func testEventCarriesInstallIDAndSuppressesPersonProfiles() async throws {
        let transport = StubTransport()
        let reporter = makeReporter(transport: transport)
        await reporter.record(.dailyHeartbeat(
            appVersion: "1.0", daysSinceInstallBucket: "1-7", planTier: "max_20x"))
        await reporter.flushAndWait()

        let event = try XCTUnwrap(try batch(from: transport).first)
        XCTAssertEqual(event["event"] as? String, "daily_heartbeat")
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        XCTAssertEqual(properties["distinct_id"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
        XCTAssertEqual(properties["plan_tier"] as? String, "max_20x")
        XCTAssertEqual(
            transport.requests.last?.url.absoluteString, "https://example.invalid/batch")
    }

    func testNothingIsSentWithAnEmptyQueue() async throws {
        let transport = StubTransport()
        await makeReporter(transport: transport).flushAndWait()
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testEventsBatchIntoOneRequest() async throws {
        let transport = StubTransport()
        let reporter = makeReporter(transport: transport)
        await reporter.record(.panelOpened)
        await reporter.record(.costPageViewed(scanDurationBucket: "<100", modelCount: 3))
        await reporter.flushAndWait()

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(try batch(from: transport).count, 2)
    }

    func testErrorTextIsScrubbed() async throws {
        let transport = StubTransport()
        let reporter = makeReporter(transport: transport)
        await reporter.recordError(
            type: "Failure",
            message: "token sk-ant-abc123 for taylor@example.com at /Users/taylor/x",
            stack: nil)
        await reporter.flushAndWait()

        let event = try XCTUnwrap(try batch(from: transport).first)
        let properties = try XCTUnwrap(event["properties"] as? [String: Any])
        let message = try XCTUnwrap(properties["$exception_message"] as? String)
        XCTAssertFalse(message.contains("sk-ant-abc123"))
        XCTAssertFalse(message.contains("taylor@example.com"))
        XCTAssertFalse(message.contains("/Users/taylor"))
        XCTAssertTrue(message.contains("[token]"))
    }

    func testAFailedSendIsDroppedNotRetained() async throws {
        struct Offline: Error {}
        let transport = StubTransport(error: Offline())
        let reporter = makeReporter(transport: transport)
        await reporter.record(.panelOpened)
        await reporter.flushAndWait()
        await reporter.flushAndWait()
        XCTAssertEqual(transport.requests.count, 1, "the dropped event is not resent")
    }
}
