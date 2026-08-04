import Foundation

public struct UsageState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case initializing
        case ok
        case credentialsUnavailable(CredentialFailureReason)
        case unauthorized
        case scopeMissing
        case rateLimited(until: Date?)
        case offline
        case serverError(status: Int?)
    }

    public var phase: Phase = .initializing
    public var snapshot: UsageSnapshot?
    public var syncedAt: Date?
    public var isRefreshing = false
    public var lastHTTPStatus: Int?
    public var planTier: String?
    public var pollInterval: TimeInterval = Intervals.usagePoll

    public init() {}

    public func isStale(now: Date = Date()) -> Bool {
        guard let syncedAt else { return true }
        return now.timeIntervalSince(syncedAt) > pollInterval * 2
    }
}

public actor UsageService {
    public static let userAgent = "claude-code/2.1.2"

    private let transport: any HTTPTransport
    private let credentials: any CredentialProviding
    private let persistenceURL: URL?
    private let analytics: any AnalyticsReporting

    private var state = UsageState()
    private var continuations: [UUID: AsyncStream<UsageState>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var suspended = false
    private var started = false
    private var rateLimitBackoff: TimeInterval = 0
    private var retryCount = 0

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        credentials: any CredentialProviding = CredentialStore(),
        persistenceURL: URL?,
        analytics: any AnalyticsReporting = DisabledAnalytics()
    ) {
        self.transport = transport
        self.credentials = credentials
        self.persistenceURL = persistenceURL
        self.analytics = analytics
    }

    public func stateUpdates() -> AsyncStream<UsageState> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: UsageState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    public func start(pollInterval: TimeInterval) async {
        guard !started else { return }
        started = true
        state.pollInterval = pollInterval
        if let url = persistenceURL, let persisted = PersistedUsage.load(from: url) {
            state.snapshot = persisted.snapshot
            state.syncedAt = persisted.syncedAt
        }
        publish()
        await fetch()
    }

    public func setPollInterval(_ interval: TimeInterval) {
        state.pollInterval = interval
        publish()
        schedule(after: jittered(interval))
    }

    public func suspend() {
        suspended = true
        pollTask?.cancel()
        pollTask = nil
        inFlight?.cancel()
        inFlight = nil
    }

    public func resume() async {
        guard suspended else { return }
        suspended = false
        await fetch()
    }

    public func refreshNow() async {
        await fetch()
    }

    public func currentState() -> UsageState { state }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publish() {
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func jittered(_ interval: TimeInterval) -> TimeInterval {
        max(30, interval + Double.random(in: -20...20))
    }

    private func schedule(after seconds: TimeInterval) {
        guard !suspended else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.fetch()
        }
    }

    private func fetch() async {
        guard !suspended else { return }
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { [weak self] () -> Void in
            await self?.performFetch()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performFetch() async {
        state.isRefreshing = true
        publish()

        defer {
            state.isRefreshing = false
            publish()
        }

        let creds: Credentials
        switch await credentials.load() {
        case .failure(let reason):
            state.phase = reason == .scopeMissing ? .scopeMissing : .credentialsUnavailable(reason)
            analytics.capture(.credentialsUnavailable(reason: reason.rawValue))
            schedule(after: jittered(state.pollInterval))
            return
        case .success(let loaded):
            creds = loaded
        }

        let headers: [String: String] = [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": Self.userAgent,
            "Content-Type": "application/json",
        ]

        let reply: HTTPResponse
        do {
            reply = try await transport.get(Endpoints.usage, headers: headers)
        } catch {
            retryCount += 1
            state.phase = .offline
            analytics.capture(.usageFetchFailed(
                statusCode: nil, failureKind: "network", retryCount: retryCount))
            schedule(after: jittered(state.pollInterval))
            return
        }

        state.lastHTTPStatus = reply.status

        switch reply.status {
        case 200:
            do {
                let snapshot = try UsageSnapshot.decode(from: reply.data)
                let now = Date()
                state.phase = .ok
                state.snapshot = snapshot
                state.syncedAt = now
                if let tier = snapshot.rateLimitTier {
                    state.planTier = tier
                }
                rateLimitBackoff = 0
                retryCount = 0
                if let url = persistenceURL {
                    PersistedUsage(snapshot: snapshot, syncedAt: now).save(to: url)
                }
                schedule(after: jittered(state.pollInterval))
            } catch {
                retryCount += 1
                state.phase = .serverError(status: 200)
                analytics.capture(.usageFetchFailed(
                    statusCode: 200, failureKind: "decode", retryCount: retryCount))
                schedule(after: jittered(state.pollInterval))
            }

        case 401:
            state.phase = .unauthorized
            analytics.capture(.usageFetchFailed(
                statusCode: 401, failureKind: "unauthorized", retryCount: retryCount))
            schedule(after: Intervals.authRetry)

        case 403:
            state.phase = .scopeMissing
            analytics.capture(.credentialsUnavailable(
                reason: CredentialFailureReason.scopeMissing.rawValue))
            schedule(after: Intervals.authRetry)

        case 429:
            rateLimitBackoff = rateLimitBackoff == 0
                ? Intervals.rateLimitBackoffFloor
                : min(rateLimitBackoff * 2, Intervals.rateLimitBackoffCeiling)
            var delay = rateLimitBackoff
            if let retryAfter = reply.headers["retry-after"], let seconds = TimeInterval(retryAfter) {
                delay = max(delay, seconds)
            }
            delay = min(delay, Intervals.rateLimitBackoffCeiling)
            state.phase = .rateLimited(until: Date().addingTimeInterval(delay))
            analytics.capture(.usageFetchFailed(
                statusCode: 429, failureKind: "rate_limited", retryCount: retryCount))
            schedule(after: delay)

        default:
            retryCount += 1
            state.phase = .serverError(status: reply.status)
            analytics.capture(.usageFetchFailed(
                statusCode: reply.status, failureKind: "http", retryCount: retryCount))
            schedule(after: jittered(state.pollInterval))
        }
    }
}
