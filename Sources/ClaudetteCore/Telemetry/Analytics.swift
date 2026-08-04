import Foundation

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
