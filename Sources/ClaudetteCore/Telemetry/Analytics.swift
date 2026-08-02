import Foundation

/// Two consent tiers (build plan D5): essential (launch, heartbeat, failure
/// events) defaults on and is disclosed on first launch; behavioral
/// (panel/cost/setting events) defaults off.
public struct TelemetryPolicy: Sendable, Equatable {
    public var essential: Bool
    public var behavioral: Bool

    public init(essential: Bool = true, behavioral: Bool = false) {
        self.essential = essential
        self.behavioral = behavioral
    }

    public var anyEnabled: Bool { essential || behavioral }

    public func allows(_ event: AnalyticsEvent) -> Bool {
        event.isBehavioral ? behavioral : essential
    }
}

/// Core stays SDK-free; the app target provides the PostHog implementation.
public protocol Analytics: Sendable {
    func capture(_ event: AnalyticsEvent)
    func captureError(type: String, message: String, stack: String?)
    func setPolicy(_ policy: TelemetryPolicy)
    func flush()
}

public struct NoopAnalytics: Analytics {
    public init() {}
    public func capture(_ event: AnalyticsEvent) {}
    public func captureError(type: String, message: String, stack: String?) {}
    public func setPolicy(_ policy: TelemetryPolicy) {}
    public func flush() {}
}
