import Foundation

/// How full one rate-limit window is, and when it empties.
public struct LimitWindow: Codable, Sendable, Equatable {
    /// 0–100. Zero when no window is active. The wire calls this
    /// `utilization`; everything downstream calls it `percentUsed`.
    public let percentUsed: Double
    public let resetsAt: Date?

    public init(percentUsed: Double, resetsAt: Date?) {
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case percentUsed = "utilization"
        case resetsAt = "resets_at"
    }

    /// The same quantity as `percentUsed`, clamped to 0–1 — the form the
    /// gauges and the colour ramp want.
    public var fractionUsed: Double {
        min(max(percentUsed / 100.0, 0), 1)
    }

    /// The number Claudette actually shows. Percent *remaining*, not used.
    public var percentRemaining: Int {
        Int((100 - min(max(percentUsed, 0), 100)).rounded())
    }
}

/// One entry of the `limits[]` array — the whole of what the endpoint says
/// about rate limits. Which limits exist depends on the plan.
public struct UsageLimit: Codable, Sendable, Equatable {
    /// Lenient on purpose: an unrecognised kind must not fail the decode and
    /// take the whole array with it.
    public enum Kind: Sendable, Equatable, Codable {
        case session
        case weeklyAllModels
        case weeklyPerModel
        case other(String)

        public var rawValue: String {
            switch self {
            case .session: return "session"
            case .weeklyAllModels: return "weekly_all"
            case .weeklyPerModel: return "weekly_scoped"
            case .other(let raw): return raw
            }
        }

        public init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "session": self = .session
            case "weekly_all": self = .weeklyAllModels
            case "weekly_scoped": self = .weeklyPerModel
            case let raw: self = .other(raw)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        /// How long the window spans, so call sites stop re-deriving it.
        public var windowDuration: TimeInterval {
            self == .session ? 5 * 3600 : 7 * 86_400
        }
    }

    public struct Scope: Codable, Sendable, Equatable {
        public struct Model: Codable, Sendable, Equatable {
            public let displayName: String?

            public init(displayName: String?) {
                self.displayName = displayName
            }

            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
            }
        }
        public let model: Model?

        public init(model: Model?) {
            self.model = model
        }
    }

    public let kind: Kind
    public let percentUsed: Double
    public let resetsAt: Date?
    public let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percentUsed = "percent"
        case resetsAt = "resets_at"
        case scope
    }

    public init(kind: Kind, window: LimitWindow, modelName: String? = nil) {
        self.kind = kind
        self.percentUsed = window.percentUsed
        self.resetsAt = window.resetsAt
        self.scope = modelName.map { Scope(model: Scope.Model(displayName: $0)) }
    }

    public var window: LimitWindow {
        LimitWindow(percentUsed: percentUsed, resetsAt: resetsAt)
    }

    /// Verbatim from the API ("Fable"); the view owns the casing.
    public var modelName: String? {
        guard kind == .weeklyPerModel, let name = scope?.model?.displayName, !name.isEmpty else {
            return nil
        }
        return name
    }

    public var windowDuration: TimeInterval { kind.windowDuration }
}

/// Decoded response of the OAuth usage endpoint. Every window can be absent
/// depending on plan; never crash on missing keys.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public let limits: [UsageLimit]
    public let rateLimitTier: String?

    public init(limits: [UsageLimit], rateLimitTier: String? = nil) {
        self.limits = limits
        self.rateLimitTier = rateLimitTier
    }

    /// The rolling five-hour cap.
    public var session: LimitWindow? {
        limits.first { $0.kind == .session }?.window
    }

    /// The weekly cap across all models.
    public var weekly: LimitWindow? {
        limits.first { $0.kind == .weeklyAllModels }?.window
    }

    /// The model-scoped weekly cap, in the order the API listed it. No local
    /// ranking table — `limits[]` already says which model it is.
    public var weeklyForModel: UsageLimit? {
        limits.first { $0.modelName != nil }
    }

    private enum CodingKeys: String, CodingKey {
        case limits
        case rateLimitTier = "rate_limit_tier"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimitTier = try container.decodeIfPresent(String.self, forKey: .rateLimitTier)
        limits = Self.decodeLimitsLeniently(from: container)
    }

    /// Decodes `limits[]` element by element. Decoding the array in one go
    /// means a single malformed row — a null `percent`, say — throws away
    /// every other limit and leaves a snapshot with no windows and no error.
    private static func decodeLimitsLeniently(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> [UsageLimit] {
        guard var array = try? container.nestedUnkeyedContainer(forKey: .limits) else { return [] }
        var limits: [UsageLimit] = []
        while !array.isAtEnd {
            // A throwing `decode` leaves `currentIndex` where it was, so a bad
            // element has to be stepped over explicitly. Bailing out if even
            // that fails keeps this from spinning.
            if let limit = try? array.decode(UsageLimit.self) {
                limits.append(limit)
            } else if (try? array.decode(SkippedElement.self)) == nil {
                break
            }
        }
        return limits
    }

    /// Consumes one element of any shape, so a bad `limits[]` row can be
    /// skipped without abandoning the rest of the array.
    private struct SkippedElement: Decodable {
        init(from decoder: Decoder) throws {}
    }

    public static func decode(from data: Data) throws -> UsageSnapshot {
        try ISO8601.tolerantDecoder().decode(UsageSnapshot.self, from: data)
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
        guard let data = try? ISO8601.encoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
