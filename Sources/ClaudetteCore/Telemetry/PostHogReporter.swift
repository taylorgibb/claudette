import Foundation

/// Posts events to PostHog's batch ingestion endpoint over plain HTTP.
///
/// Deliberately not the PostHog SDK. That SDK pulls in PLCrashReporter — a
/// C++/ObjC dependency that has to compile before `swift test` can run a
/// single line of this package's tests, and that configures a process-wide
/// singleton from an initialiser. The app sends nine event shapes and nothing
/// else, so the whole integration is one POST.
///
/// Everything here is best-effort: a failed send is dropped, never retried
/// into a growing queue and never surfaced to the user. Telemetry must not be
/// able to degrade the app.
///
/// This type is only ever constructed when a project key is baked in, so a
/// build without one has no reporter at all rather than an inert one.
public actor PostHogReporter: AnalyticsReporting {
    /// Queued long enough to batch, short enough that a crash loses little.
    private static let batchSize = 20

    private struct QueuedEvent {
        let name: String
        let properties: [String: AnalyticsProperty]
        let timestamp: Date
    }

    private let projectToken: String
    private let host: URL
    private let installID: String
    private let transport: any HTTPTransport
    private var queue: [QueuedEvent] = []

    public init(
        projectToken: String,
        host: URL,
        installID: String,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.projectToken = projectToken
        self.host = host
        self.installID = installID
        self.transport = transport
    }

    // `AnalyticsReporting` is synchronous because call sites are scattered
    // through view code where telemetry must never introduce an await. Each
    // one hands off to the awaitable form below, which is what tests use so
    // they are not racing a detached task.

    public nonisolated func capture(_ event: AnalyticsEvent) {
        Task { await self.record(event) }
    }

    public nonisolated func captureError(type: String, message: String, stack: String?) {
        Task { await self.recordError(type: type, message: message, stack: stack) }
    }

    public nonisolated func flush() {
        Task { await self.flushAndWait() }
    }

    // MARK: - Awaitable forms

    public func record(_ event: AnalyticsEvent) async {
        await enqueue(event)
    }

    public func recordError(type: String, message: String, stack: String?) async {
        await enqueueError(type: type, message: message, stack: stack)
    }

    private func enqueue(_ event: AnalyticsEvent) async {
        queue.append(QueuedEvent(
            name: event.name, properties: event.properties, timestamp: Date()))
        if queue.count >= Self.batchSize {
            await sendQueued()
        }
    }

    private func enqueueError(type: String, message: String, stack: String?) async {
        var properties: [String: AnalyticsProperty] = [
            "$exception_type": .string(Redactor.scrub(type)),
            "$exception_message": .string(Redactor.scrub(message)),
        ]
        if let stack {
            properties["$exception_stack_trace_raw"] = .string(Redactor.scrub(stack))
        }
        queue.append(QueuedEvent(
            name: "$exception", properties: properties, timestamp: Date()))
        await sendQueued()
    }

    /// Sends everything queued. Awaited at termination, and by tests.
    public func flushAndWait() async {
        await sendQueued()
    }

    private func sendQueued() async {
        guard !queue.isEmpty else { return }
        let batch = queue
        queue.removeAll()
        guard let body = try? JSONSerialization.data(withJSONObject: payload(for: batch))
        else { return }
        _ = try? await transport.post(
            host.appendingPathComponent("batch"),
            headers: ["Content-Type": "application/json"],
            body: body)
    }

    private func payload(for batch: [QueuedEvent]) -> [String: Any] {
        [
            "api_key": projectToken,
            "batch": batch.map { event in
                var properties = event.properties.mapValues(\.anyValue)
                properties["distinct_id"] = installID
                // Anonymous events: no person record is created or updated,
                // which is the server-side half of the privacy promise.
                properties["$process_person_profile"] = false
                return [
                    "event": event.name,
                    "properties": properties,
                    "timestamp": ISO8601.format(event.timestamp),
                ]
            },
        ]
    }
}
