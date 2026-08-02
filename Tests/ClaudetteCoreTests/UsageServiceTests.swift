import XCTest
@testable import ClaudetteCore

final class UsageServiceTests: XCTestCase {
    struct StubCredentials: CredentialProviding {
        let result: Result<Credentials, CredentialFailureReason>
        func load() -> Result<Credentials, CredentialFailureReason> { result }
    }

    private let goodCreds = Credentials(
        accessToken: "token", expiresAt: nil, scopes: ["user:profile"],
        subscriptionType: "max", source: .credentialsFile)

    private func firstState(
        matching predicate: @escaping @Sendable (UsageState) -> Bool,
        from service: UsageService
    ) async -> UsageState? {
        let stream = await service.stateUpdates()
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
        let body = #"{"limits":[{"kind":"session","percent":33.0,"resets_at":"2026-08-01T07:00:00.123456Z"}]}"#
        let service = UsageService(
            transport: StubTransport(reply: HTTPResponse(status: 200, data: Data(body.utf8))),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .ok }, from: service)
        XCTAssertEqual(state?.snapshot?.session?.percentUsed, 33.0)
        XCTAssertEqual(state?.planTier, "max")
        XCTAssertEqual(state?.credentialSource, .credentialsFile)
    }

    func test401MovesToUnauthorized() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPResponse(status: 401, data: Data())),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .unauthorized }, from: service)
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.lastHTTPStatus, 401)
    }

    func test403MovesToScopeMissing() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPResponse(status: 403, data: Data())),
            credentials: StubCredentials(result: .success(goodCreds)),
            persistenceURL: nil)
        let state = await firstState(matching: { $0.phase == .scopeMissing }, from: service)
        XCTAssertNotNil(state)
    }

    func testMissingCredentialsSurfaceReason() async {
        let service = UsageService(
            transport: StubTransport(reply: HTTPResponse(status: 200, data: Data())),
            credentials: StubCredentials(result: .failure(.mcpOnly)),
            persistenceURL: nil)
        let state = await firstState(
            matching: { $0.phase == .credentialsUnavailable(.mcpOnly) }, from: service)
        XCTAssertNotNil(state)
    }

    func testRateLimitedSetsRetryDate() async {
        let reply = HTTPResponse(status: 429, data: Data(), headers: ["retry-after": "600"])
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

/// `actor` prevents data races, not overlapping calls: every `await` is a
/// suspension point where another caller can enter.
final class UsageServiceConcurrencyTests: XCTestCase {
    /// Blocks until released, so several fetches are provably in flight at
    /// once if the service allows it.
    private final class GatedTransport: HTTPTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var _callCount = 0
        private let gate = DispatchSemaphore(value: 0)

        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return _callCount
        }

        func open() { gate.signal() }

        private func recordCall() {
            lock.lock()
            _callCount += 1
            lock.unlock()
        }

        func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
            recordCall()
            await withCheckedContinuation { continuation in
                DispatchQueue.global().async {
                    self.gate.wait()
                    continuation.resume()
                }
            }
            return HTTPResponse(status: 200, data: Data(#"{"limits":[]}"#.utf8))
        }

        func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
            HTTPResponse(status: 200, data: Data())
        }
    }

    private let creds = Credentials(
        accessToken: "token", expiresAt: nil, scopes: ["user:profile"],
        subscriptionType: "max", source: .credentialsFile)

    private struct StubCredentials: CredentialProviding {
        let result: Result<Credentials, CredentialFailureReason>
        func load() -> Result<Credentials, CredentialFailureReason> { result }
    }

    /// A manual refresh landing during a scheduled poll used to fire a second
    /// request at a rate-limit-sensitive endpoint, and the first one's `defer`
    /// cleared `isRefreshing` while the second was still running.
    func testConcurrentRefreshesCoalesceIntoOneRequest() async {
        let transport = GatedTransport()
        let service = UsageService(
            transport: transport,
            credentials: StubCredentials(result: .success(creds)),
            persistenceURL: nil)

        async let first: Void = service.refreshNow()
        async let second: Void = service.refreshNow()
        async let third: Void = service.refreshNow()

        // Let all three reach the actor before releasing the request.
        try? await Task.sleep(for: .milliseconds(80))
        transport.open()
        transport.open()
        transport.open()
        _ = await (first, second, third)

        XCTAssertEqual(transport.callCount, 1, "three refreshes, one request")
        let state = await service.currentState()
        XCTAssertFalse(state.isRefreshing)
    }

    /// A fetch that completes after `suspend()` used to re-arm the poll timer
    /// unconditionally, quietly resuming polling through sleep.
    func testSuspendStopsPollingEvenIfAFetchWasInFlight() async {
        let transport = GatedTransport()
        let service = UsageService(
            transport: transport,
            credentials: StubCredentials(result: .success(creds)),
            persistenceURL: nil)

        async let inFlight: Void = service.refreshNow()
        try? await Task.sleep(for: .milliseconds(50))
        await service.suspend()
        transport.open()
        await inFlight

        // Nothing further may start while suspended.
        await service.refreshNow()
        XCTAssertEqual(transport.callCount, 1)
    }
}
