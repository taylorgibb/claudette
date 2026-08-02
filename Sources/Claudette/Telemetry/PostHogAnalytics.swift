import Foundation
@preconcurrency import PostHog
import ClaudetteCore

/// The only file that imports PostHog. Anonymous events, no person
/// profiles, policy-gated per event tier, redacted error capture.
final class PostHogAnalytics: Analytics, @unchecked Sendable {
    private let lock = NSLock()
    private var policy: TelemetryPolicy

    init(apiKey: String, host: String, distinctID: String, policy: TelemetryPolicy) {
        self.policy = policy

        let config = PostHogConfig(projectToken: apiKey, host: host)
        // Anonymous events only; no person record per user.
        config.personProfiles = .never
        // We send our own lifecycle events, deliberately.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.flushAt = 20
        config.flushIntervalSeconds = 60
        let installUUID = UUID(uuidString: distinctID) ?? UUID()
        config.getAnonymousId = { _ in installUUID }
        PostHogSDK.shared.setup(config)

        if !policy.anyEnabled {
            PostHogSDK.shared.optOut()
        }
    }

    private var currentPolicy: TelemetryPolicy {
        lock.lock()
        defer { lock.unlock() }
        return policy
    }

    func capture(_ event: AnalyticsEvent) {
        guard currentPolicy.allows(event) else { return }
        PostHogSDK.shared.capture(
            event.name,
            properties: event.properties.mapValues { $0.anyValue })
    }

    func captureError(type: String, message: String, stack: String?) {
        guard currentPolicy.essential else { return }
        var properties: [String: Any] = [
            "$exception_type": Redactor.scrub(type),
            "$exception_message": Redactor.scrub(message),
        ]
        if let stack {
            properties["$exception_stack_trace_raw"] = Redactor.scrub(stack)
        }
        PostHogSDK.shared.capture("$exception", properties: properties)
    }

    func setPolicy(_ newPolicy: TelemetryPolicy) {
        lock.lock()
        let wasEnabled = policy.anyEnabled
        policy = newPolicy
        lock.unlock()

        if newPolicy.anyEnabled, !wasEnabled {
            PostHogSDK.shared.optIn()
        } else if !newPolicy.anyEnabled, wasEnabled {
            PostHogSDK.shared.optOut()
        }
    }

    func flush() {
        PostHogSDK.shared.flush()
    }
}

/// Routes uncaught exceptions through the redactor. A C-function handler
/// can't capture context, hence the static reference.
enum ExceptionReporter {
    nonisolated(unsafe) static var analytics: (any Analytics)?

    static func install(_ analytics: any Analytics) {
        Self.analytics = analytics
        NSSetUncaughtExceptionHandler { exception in
            ExceptionReporter.analytics?.captureError(
                type: exception.name.rawValue,
                message: exception.reason ?? "uncaught exception",
                stack: exception.callStackSymbols.joined(separator: "\n"))
            ExceptionReporter.analytics?.flush()
        }
    }
}
