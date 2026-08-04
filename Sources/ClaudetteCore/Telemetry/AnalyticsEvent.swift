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

public enum AnalyticsEvent: Sendable, Equatable {
    case appLaunched(appVersion: String, osVersion: String, arch: String, isNotchedDisplay: Bool, displayCount: Int)
    case dailyHeartbeat(appVersion: String, daysSinceInstallBucket: String, planTier: String)
    case panelOpened
    case costPageViewed(scanDurationBucket: String, modelCount: Int)
    case settingChanged(key: String, value: String)
    case usageFetchFailed(statusCode: Int?, failureKind: String, retryCount: Int)
    case credentialsUnavailable(reason: String)
    case costScanFailed(failureKind: String)
    case unpricedModelSeen(modelID: ModelID)

    public var name: String {
        switch self {
        case .appLaunched: return "app_launched"
        case .dailyHeartbeat: return "daily_heartbeat"
        case .panelOpened: return "panel_opened"
        case .costPageViewed: return "cost_page_viewed"
        case .settingChanged: return "setting_changed"
        case .usageFetchFailed: return "usage_fetch_failed"
        case .credentialsUnavailable: return "credentials_unavailable"
        case .costScanFailed: return "cost_scan_failed"
        case .unpricedModelSeen: return "unpriced_model_seen"
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
        case .panelOpened:
            return [:]
        case .costPageViewed(let bucket, let modelCount):
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
        case .costScanFailed(let kind):
            return ["failure_kind": .string(kind)]
        case .unpricedModelSeen(let modelID):
            return ["model_id": .string(modelID)]
        }
    }
}

public enum AnalyticsBuckets {
    public static func daysSinceInstallBucket(_ days: Int) -> String {
        switch days {
        case ..<1: return "0"
        case 1...7: return "1-7"
        case 8...30: return "8-30"
        case 31...90: return "31-90"
        default: return "90+"
        }
    }

    public static func scanDurationBucket(ms: Int) -> String {
        switch ms {
        case ..<100: return "<100"
        case 100..<500: return "100-500"
        case 500..<2000: return "500-2000"
        case 2000..<10000: return "2000-10000"
        default: return ">10000"
        }
    }
}
