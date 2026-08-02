import Foundation

public enum AnalyticsProperty: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    public var anyValue: Any {
        switch self {
        case .string(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .bool(let v): return v
        }
    }
}

/// The complete event list. Deliberately small: no per-poll events, no
/// free-form string properties, no utilization numbers, no dollar figures.
public enum AnalyticsEvent: Sendable, Equatable {
    case appLaunched(appVersion: String, osVersion: String, arch: String, isNotchedDisplay: Bool, displayCount: Int)
    case dailyHeartbeat(appVersion: String, daysSinceInstallBucket: String, planTier: String)
    case panelOpened(fromState: String)
    case costScreenViewed(scanDurationBucket: String, modelCount: Int)
    case settingChanged(key: String, value: String)
    case usageFetchFailed(statusCode: Int?, failureKind: String, retryCount: Int)
    case credentialsUnavailable(reason: String)
    case costScanFailed(failureKind: String, rootKind: String)
    case unknownModelPriced(modelID: String)

    public var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .dailyHeartbeat: return "daily_heartbeat"
        case .panelOpened: return "panel_opened"
        case .costScreenViewed: return "cost_screen_viewed"
        case .settingChanged: return "setting_changed"
        case .usageFetchFailed: return "usage_fetch_failed"
        case .credentialsUnavailable: return "credentials_unavailable"
        case .costScanFailed: return "cost_scan_failed"
        case .unknownModelPriced: return "unknown_model_priced"
        }
    }

    /// Behavioral events are opt-in; launch/heartbeat/failure events ride the
    /// essential (opt-out) tier. See D5 in the build plan.
    public var isBehavioral: Bool {
        switch self {
        case .panelOpened, .costScreenViewed, .settingChanged:
            return true
        default:
            return false
        }
    }

    public var properties: [String: AnalyticsProperty] {
        switch self {
        case .appLaunched(let appVersion, let osVersion, let arch, let isNotched, let displayCount):
            return [
                "app_version": .string(appVersion),
                "os_version": .string(osVersion),
                "arch": .string(arch),
                "is_notched_display": .bool(isNotched),
                "display_count": .int(displayCount),
            ]
        case .dailyHeartbeat(let appVersion, let bucket, let planTier):
            return [
                "app_version": .string(appVersion),
                "days_since_install": .string(bucket),
                "plan_tier": .string(planTier),
            ]
        case .panelOpened(let fromState):
            return ["from_state": .string(fromState)]
        case .costScreenViewed(let bucket, let modelCount):
            return [
                "scan_duration_ms": .string(bucket),
                "model_count": .int(modelCount),
            ]
        case .settingChanged(let key, let value):
            return ["key": .string(key), "value": .string(value)]
        case .usageFetchFailed(let statusCode, let kind, let retryCount):
            var props: [String: AnalyticsProperty] = [
                "failure_kind": .string(kind),
                "retry_count": .int(retryCount),
            ]
            if let statusCode {
                props["status_code"] = .int(statusCode)
            }
            return props
        case .credentialsUnavailable(let reason):
            return ["reason": .string(reason)]
        case .costScanFailed(let kind, let rootKind):
            return ["failure_kind": .string(kind), "root_kind": .string(rootKind)]
        case .unknownModelPriced(let modelID):
            return ["model_id": .string(modelID)]
        }
    }
}

public enum AnalyticsBuckets {
    public static func daysSinceInstall(_ days: Int) -> String {
        switch days {
        case ..<1: return "0"
        case 1...7: return "1-7"
        case 8...30: return "8-30"
        case 31...90: return "31-90"
        default: return "90+"
        }
    }

    public static func scanDurationMs(_ ms: Int) -> String {
        switch ms {
        case ..<100: return "<100"
        case 100..<500: return "100-500"
        case 500..<2000: return "500-2000"
        case 2000..<10000: return "2000-10000"
        default: return ">10000"
        }
    }
}
