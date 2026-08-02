import XCTest
@testable import ClaudetteCore

final class CostReportTests: XCTestCase {
    private let prices = PriceTable(models: ["m": ModelPrice(input: 1_000_000, output: 1_000_000)])

    private func dayKey(daysAgo: Int, from now: Date) -> String {
        DayKey.from(Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!)
    }

    func testWindowExcludesOldDaysAndZeroFills() {
        let now = Date()
        let days: [String: [String: TokenTally]] = [
            dayKey(daysAgo: 0, from: now): ["m": TokenTally(input: 3)],
            dayKey(daysAgo: 29, from: now): ["m": TokenTally(input: 2)],
            dayKey(daysAgo: 40, from: now): ["m": TokenTally(input: 500)],
        ]
        let report = CostReport.build(from: days, prices: prices, windowDays: 30, now: now)
        XCTAssertEqual(report.days.count, 30)
        XCTAssertEqual(report.totalDollars, 5, accuracy: 1e-9)
        XCTAssertEqual(report.days.last?.dollars ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(report.days.first?.dollars ?? 0, 2, accuracy: 1e-9)
        // Zero-filled middle.
        XCTAssertEqual(report.days[10].dollars, 0)
    }

    func testModelSharesSumToOne() {
        let now = Date()
        let table = PriceTable(models: [
            "a": ModelPrice(input: 1_000_000, output: 0),
            "b": ModelPrice(input: 1_000_000, output: 0),
        ])
        let days = [dayKey(daysAgo: 1, from: now): [
            "a": TokenTally(input: 75),
            "b": TokenTally(input: 25),
        ]]
        let report = CostReport.build(from: days, prices: table, now: now)
        XCTAssertEqual(report.models[0].model, "a")
        XCTAssertEqual(report.models[0].share, 0.75, accuracy: 1e-9)
        XCTAssertEqual(report.models.map(\.share).reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testComparisonMultipleAndBreakEven() {
        let now = Date()
        // $10/day for 30 days against a $100 subscription.
        var days: [String: [String: TokenTally]] = [:]
        for back in 0..<30 {
            days[dayKey(daysAgo: back, from: now)] = ["m": TokenTally(input: 10)]
        }
        let report = CostReport.build(from: days, prices: prices, now: now)
        XCTAssertEqual(report.totalDollars, 300, accuracy: 1e-6)

        let comparison = CostComparison(report: report, monthlyPrice: 100)
        XCTAssertEqual(comparison.effectiveMultiple ?? 0, 3.0, accuracy: 1e-9)
        // Crosses $100 on the 10th day of the window.
        XCTAssertEqual(comparison.breakEvenDayKey, report.days[9].dayKey)
    }

    func testComparisonNeverCrossing() {
        let now = Date()
        let days = [dayKey(daysAgo: 0, from: now): ["m": TokenTally(input: 5)]]
        let report = CostReport.build(from: days, prices: prices, now: now)
        let comparison = CostComparison(report: report, monthlyPrice: 100)
        XCTAssertNil(comparison.breakEvenDayKey)
        XCTAssertEqual(comparison.effectiveMultiple ?? 0, 0.05, accuracy: 1e-9)
    }

    func testPlanTierResolution() {
        XCTAssertEqual(PlanTier.resolve("default_claude_max_5x")?.id, "max_5x")
        XCTAssertEqual(PlanTier.resolve("default_claude_max_20x")?.id, "max_20x")
        XCTAssertEqual(PlanTier.resolve("max")?.id, "max_5x")
        XCTAssertEqual(PlanTier.resolve("pro")?.id, "pro")
        XCTAssertEqual(PlanTier.resolve("default_claude_pro")?.id, "pro")
        XCTAssertNil(PlanTier.resolve(nil))
        XCTAssertNil(PlanTier.resolve("enterprise_weird"))
    }
}

final class UsageServiceTests: XCTestCase {
    struct StubTransport: HTTPTransport {
        let reply: HTTPReply
        func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { reply }
    }

    struct StubCredentials: CredentialProviding {
        let result: Result<Credentials, CredentialFailureReason>
        func load() -> Result<Credentials, CredentialFailureReason> { result }
    }

    private let goodCreds = Credentials(
        accessToken: "token", expiresAt: nil, scopes: ["user:profile"],
        subscriptionType: "max", source: .file)

    private func firstState(
        matching predicate: @escaping @Sendable (UsageState) -> Bool,
        from service: UsageService
    ) async -> UsageState? {
        let stream = await service.states()
        let task = Task { () -> UsageState? in
            for await state in stream where predicate(state) {
                return state
            }
            return nil
        }
        Task { await service.start(pollInterval: 300) }
        let timeout = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            task.cancel()
        }
        let result = await task.value
        timeout.cancel()
        return result
    }

    func testSuccessfulFetchPublishesSnapshot() async {
        let body = #"{"five_hour": {"utilization": 33.0, "resets_at": "2026-08-01T07:00:00.123456Z"}}"#
        let service = UsageService(
            transport: StubTransport(reply: HTTPReply(status: 200, data: Data(body.utf8))),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .ok }, from: service)
        XCTAssertEqual(state?.snapshot?.fiveHour?.utilization, 33.0)
        XCTAssertEqual(state?.planTier, "max")
        XCTAssertEqual(state?.credentialSource, .file)
    }

    func test401MovesToUnauthorized() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPReply(status: 401, data: Data())),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .unauthorized }, from: service)
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.lastHTTPStatus, 401)
    }

    func test403MovesToScopeMissing() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPReply(status: 403, data: Data())),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .scopeMissing }, from: service)
        XCTAssertNotNil(state)
    }

    func testMissingCredentialsSurfaceReason() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPReply(status: 200, data: Data())),
            credentials: StubCredentials(result: .failure(.mcpOnly)),
            persistenceURL: nil)
        let state = await firstState(
            matching: { $0.phase == .credentialsUnavailable(.mcpOnly) }, from: service)
        XCTAssertNotNil(state)
    }

    func testRateLimitedSetsRetryDate() async {
        let reply = HTTPReply(status: 429, data: Data(), headers: ["retry-after": "600"])
        let service = UsageService(
            transport: StubTransport(reply: reply),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: {
            if case .rateLimited = $0.phase { return true }
            return false
        }, from: service)
        guard case .rateLimited(let until) = state?.phase else {
            return XCTFail("expected rateLimited")
        }
        XCTAssertNotNil(until)
        XCTAssertGreaterThan(until!.timeIntervalSinceNow, 500)
    }

    func testStaleness() {
        var state = UsageState()
        state.pollInterval = 300
        XCTAssertTrue(state.isStale())
        state.syncedAt = Date(timeIntervalSinceNow: -100)
        XCTAssertFalse(state.isStale())
        state.syncedAt = Date(timeIntervalSinceNow: -700)
        XCTAssertTrue(state.isStale())
    }
}
