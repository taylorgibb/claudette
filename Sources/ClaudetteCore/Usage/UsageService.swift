import Foundation

public struct UsageState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case initializing
        /// Last fetch succeeded; `snapshot`/`syncedAt` are current.
        case ok
        case credentialsUnavailable(CredentialFailureReason)
        /// HTTP 401 — polling drops to a slow retry in case Claude Code
        /// refreshes the token underneath us.
        case unauthorized
        /// HTTP 403 — token lacks `user:profile`.
        case scopeMissing
        case rateLimited(until: Date?)
        case offline(String)
    }

    public var phase: Phase = .initializing
    /// Last good snapshot; kept through error phases so the UI can render
    /// dimmed stale data instead of a blank.
    public var snapshot: UsageSnapshot?
    public var syncedAt: Date?
    public var isRefreshing = false
    public var lastHTTPStatus: Int?
    public var credentialSource: CredentialSource?
    /// e.g. "default_claude_max_5x" (usage response) or "max" (credentials).
    public var planTier: String?
    public var pollInterval: TimeInterval = 300

    public init() {}

    /// Stale = older than two poll intervals; the UI dims the numbers.
    public func isStale(now: Date = Date()) -> Bool {
        guard let syncedAt else { return true }
        return now.timeIntervalSince(syncedAt) > pollInterval * 2
    }
}

/// Owns the usage polling loop. Single URLSession, exponential backoff on
/// 429, slow retry on 401, jittered schedule, snapshot persistence.
public actor UsageService {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Without a `claude-code/*` UA the endpoint applies a much tighter
    /// rate-limit bucket and returns persistent 429s.
    public static let userAgent = "claude-code/2.1.2"

    private let transport: any HTTPTransport
    private let credentials: any CredentialProviding
    private let persistenceURL: URL?
    private let analytics: any Analytics

    private var state = UsageState()
    private var continuations: [UUID: AsyncStream<UsageState>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var suspended = false
    private var started = false
    private var rateLimitBackoff: TimeInterval = 0
    private var retryCount = 0

    public init(
        transport: any HTTPTransport = URLSessionTransport(),
        credentials: any CredentialProviding = CredentialStore(),
        persistenceURL: URL?,
        analytics: any Analytics = NoopAnalytics()
    ) {
        self.transport = transport
        self.credentials = credentials
        self.persistenceURL = persistenceURL
        self.analytics = analytics
    }

    // MARK: - Public surface

    public func states() -> AsyncStream<UsageState> {
        let (stream, continuation) = AsyncStream.makeStream(of: UsageState.self)
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
        await tick()
    }

    public func setPollInterval(_ interval: TimeInterval) {
        state.pollInterval = interval
        publish()
        schedule(after: jittered(interval))
    }

    /// Suspend while the screen is locked or asleep.
    public func suspend() {
        suspended = true
        pollTask?.cancel()
        pollTask = nil
    }

    public func resume() async {
        guard suspended else { return }
        suspended = false
        await tick()
    }

    /// Manual refresh (sync label click). Re-arms the schedule from now.
    public func refreshNow() async {
        await tick()
    }

    public func diagnostics() -> UsageState { state }

    // MARK: - Polling

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    private func publish() {
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }

    private func jittered(_ interval: TimeInterval) -> TimeInterval {
        // ±20s so multiple machines on one account don't sync up.
        max(30, interval + Double.random(in: -20...20))
    }

    private func schedule(after seconds: TimeInterval) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.tick()
        }
    }

    private func tick() async {
        guard !suspended else { return }
        state.isRefreshing = true
        publish()

        defer {
            state.isRefreshing = false
            publish()
        }

        let creds: Credentials
        switch credentials.load() {
        case .failure(let reason):
            state.phase = reason == .scopeMissing ? .scopeMissing : .credentialsUnavailable(reason)
            state.credentialSource = nil
            analytics.capture(.credentialsUnavailable(reason: reason.rawValue))
            schedule(after: jittered(state.pollInterval))
            return
        case .success(let loaded):
            creds = loaded
        }
        state.credentialSource = creds.source
        if state.planTier == nil {
            state.planTier = creds.subscriptionType
        }

        let headers: [String: String] = [
            "Authorization": "Bearer \(creds.accessToken)",
            "anthropic-beta": "oauth-2025-04-20",
            "User-Agent": Self.userAgent,
            "Content-Type": "application/json",
        ]

        let reply: HTTPReply
        do {
            reply = try await transport.get(Self.endpoint, headers: headers)
        } catch {
            retryCount += 1
            state.phase = .offline(error.localizedDescription)
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
                state.phase = .offline("Unexpected response shape")
                analytics.capture(.usageFetchFailed(
                    statusCode: 200, failureKind: "decode", retryCount: retryCount))
                schedule(after: jittered(state.pollInterval))
            }

        case 401:
            state.phase = .unauthorized
            analytics.capture(.usageFetchFailed(
                statusCode: 401, failureKind: "unauthorized", retryCount: retryCount))
            // Retry every 30 minutes in case Claude Code refreshed the token.
            schedule(after: 30 * 60)

        case 403:
            state.phase = .scopeMissing
            analytics.capture(.credentialsUnavailable(reason: CredentialFailureReason.scopeMissing.rawValue))
            schedule(after: 30 * 60)

        case 429:
            // Exponential backoff from 5 min, cap 60 min, honour retry-after.
            rateLimitBackoff = rateLimitBackoff == 0 ? 300 : min(rateLimitBackoff * 2, 3600)
            var delay = rateLimitBackoff
            if let retryAfter = reply.headers["retry-after"], let seconds = TimeInterval(retryAfter) {
                delay = max(delay, seconds)
            }
            delay = min(delay, 3600)
            state.phase = .rateLimited(until: Date().addingTimeInterval(delay))
            analytics.capture(.usageFetchFailed(
                statusCode: 429, failureKind: "rate_limited", retryCount: retryCount))
            schedule(after: delay)

        default:
            retryCount += 1
            state.phase = .offline("HTTP \(reply.status)")
            analytics.capture(.usageFetchFailed(
                statusCode: reply.status, failureKind: "http", retryCount: retryCount))
            schedule(after: jittered(state.pollInterval))
        }
    }
}
