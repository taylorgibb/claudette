import Foundation

public enum Endpoints {
    public static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let oauthAuthorize = URL(string: "https://claude.ai/oauth/authorize")!
    public static let oauthToken = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    public static let priceTable = URL(
        string: "https://raw.githubusercontent.com/taylorgibb/claudette/main/Sources/ClaudetteCore/Resources/prices.json")!
    public static let latestRelease = URL(
        string: "https://api.github.com/repos/taylorgibb/claudette/releases/latest")!
    public static let releases = URL(string: "https://github.com/taylorgibb/claudette/releases")!
}

public enum Intervals {
    public static let usagePoll: TimeInterval = 300
    public static let authRetry: TimeInterval = 30 * 60
    public static let rateLimitBackoffFloor: TimeInterval = 300
    public static let rateLimitBackoffCeiling: TimeInterval = 3600
    public static let costRescan: TimeInterval = 15 * 60
    public static let costFreshness: TimeInterval = 60
    public static let costRetentionDays = 90
    public static let costReportDays = 30
    public static let priceTableCheck: TimeInterval = 7 * 24 * 3600
    public static let priceTableRetry: TimeInterval = 6 * 3600
    public static let updateCheck: TimeInterval = 24 * 3600
}
