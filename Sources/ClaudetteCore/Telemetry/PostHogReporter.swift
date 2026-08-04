import Foundation

public actor PostHogReporter: AnalyticsReporting {
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

    public nonisolated func capture(_ event: AnalyticsEvent) {
        Task { await self.record(event) }
    }

    public nonisolated func captureError(type: String, message: String, stack: String?) {
        Task { await self.recordError(type: type, message: message, stack: stack) }
    }

    public nonisolated func flush() {
        Task { await self.flushAndWait() }
    }

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
