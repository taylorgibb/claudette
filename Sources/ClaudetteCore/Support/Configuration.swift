import Foundation

/// Every remote address the app talks to, in one place — a fork that wants to
/// point at its own price table changes it here, not in whichever
/// type happens to make the call.
public enum Endpoints {
    /// The usage limits Claude Code itself reads.
    public static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Overrides for the price table bundled in the app.
    public static let priceTable = URL(
        string: "https://raw.githubusercontent.com/taylorgibb/claudette/main/Sources/ClaudetteCore/Resources/prices.json")!
    /// Where the update checker looks, and where the panel's update link goes.
    public static let latestRelease = URL(
        string: "https://api.github.com/repos/taylorgibb/claudette/releases/latest")!
    public static let releases = URL(string: "https://github.com/taylorgibb/claudette/releases")!
}

/// Cadences and horizons. Grouped so the trade-offs are visible next to each
/// other instead of scattered across nine files.
public enum Intervals {
    /// Default usage poll. The endpoint is rate-limit sensitive; the poller
    /// jitters around this so several machines on one account don't sync up.
    public static let usagePoll: TimeInterval = 300
    /// Slow retry after a 401 or 403, in case Claude Code refreshes the token
    /// underneath us.
    public static let authRetry: TimeInterval = 30 * 60
    /// Rate-limit backoff floor and ceiling, doubling in between.
    public static let rateLimitBackoffFloor: TimeInterval = 300
    public static let rateLimitBackoffCeiling: TimeInterval = 3600
    /// How often the log tree is rescanned for new spend.
    public static let costRescan: TimeInterval = 15 * 60
    /// How long a scan result stays fresh enough to reuse when the panel opens.
    public static let costFreshness: TimeInterval = 60
    /// How much history the cost cache keeps. Comfortably wider than the
    /// report window so a month-boundary rebuild isn't needed.
    public static let costRetentionDays = 90
    /// How many days the cost report covers.
    public static let costReportDays = 30
    /// How often to look for a newer price table, and a newer app.
    public static let priceTableCheck: TimeInterval = 7 * 24 * 3600
    /// How long to wait after a *failed* price-table fetch. Much shorter than
    /// the success interval so being briefly offline doesn't cost a week.
    public static let priceTableRetry: TimeInterval = 6 * 3600
    public static let updateCheck: TimeInterval = 24 * 3600
}
