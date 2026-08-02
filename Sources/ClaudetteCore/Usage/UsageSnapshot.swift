import Foundation

/// One rate-limit window as returned by `GET /api/oauth/usage`.
public struct UsageWindow: Codable, Sendable, Equatable {
    /// Percent used, 0–100. Zero when no window is active.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var fractionUsed: Double {
        min(max(utilization / 100.0, 0), 1)
    }
}

public struct ExtraUsage: Codable, Sendable, Equatable {
    public let isEnabled: Bool?
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
    }
}

/// Decoded response of the OAuth usage endpoint. Every window can be null
/// depending on plan; never crash on absent keys.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    public let sevenDayOpus: UsageWindow?
    public let sevenDaySonnet: UsageWindow?
    public let extraUsage: ExtraUsage?
    public let rateLimitTier: String?

    public init(
        fiveHour: UsageWindow?,
        sevenDay: UsageWindow?,
        sevenDayOpus: UsageWindow? = nil,
        sevenDaySonnet: UsageWindow? = nil,
        extraUsage: ExtraUsage? = nil,
        rateLimitTier: String? = nil
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.extraUsage = extraUsage
        self.rateLimitTier = rateLimitTier
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
        case rateLimitTier = "rate_limit_tier"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        sevenDayOpus = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try container.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        extraUsage = try container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        rateLimitTier = try container.decodeIfPresent(String.self, forKey: .rateLimitTier)
    }

    public static func decode(from data: Data) throws -> UsageSnapshot {
        try ISO8601.tolerantDecoder().decode(UsageSnapshot.self, from: data)
    }

    /// The model-scoped weekly window: opus preferred, sonnet fallback.
    public var modelWeekly: (label: String, window: UsageWindow)? {
        if let opus = sevenDayOpus { return ("OPUS", opus) }
        if let sonnet = sevenDaySonnet { return ("SONNET", sonnet) }
        return nil
    }
}

/// Snapshot plus sync time, persisted so the app can render the last known
/// numbers immediately on launch.
public struct PersistedUsage: Codable, Sendable, Equatable {
    public let snapshot: UsageSnapshot
    public let syncedAt: Date

    public init(snapshot: UsageSnapshot, syncedAt: Date) {
        self.snapshot = snapshot
        self.syncedAt = syncedAt
    }

    public static func load(from url: URL) -> PersistedUsage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ISO8601.tolerantDecoder().decode(PersistedUsage.self, from: data)
    }

    public func save(to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
