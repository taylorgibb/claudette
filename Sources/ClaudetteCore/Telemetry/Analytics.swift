import Foundation

/// Core stays vendor-free; the reporter that actually sends is injected.
/// A fork that wants no telemetry passes `DisabledAnalytics`, which is also
/// the default at every injection point and what every build without a
/// project key gets.
public protocol AnalyticsReporting: Sendable {
    func capture(_ event: AnalyticsEvent)
    func captureError(type: String, message: String, stack: String?)
    func flush()
}

public struct DisabledAnalytics: AnalyticsReporting {
    public init() {}
    public func capture(_ event: AnalyticsEvent) {}
    public func captureError(type: String, message: String, stack: String?) {}
    public func flush() {}
}
