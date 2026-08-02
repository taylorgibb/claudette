import Foundation

/// The API-equivalent cost picture over the report window, entirely from
/// local logs. Nothing here leaves the machine.
public struct CostReport: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public let key: DayKey
        public let dollars: Double
        public var id: DayKey { key }

        public init(key: DayKey, dollars: Double) {
            self.key = key
            self.dollars = dollars
        }
    }

    public struct ModelCost: Sendable, Equatable, Identifiable {
        public let model: ModelID
        public let tally: TokenTally
        /// nil = no price known: tokens counted, excluded from the dollar
        /// figure rather than silently priced at zero.
        public let dollars: Double?
        /// This model's share of `totalDollars`, 0–1.
        public let costShare: Double
        public var id: ModelID { model }

        public init(model: ModelID, tally: TokenTally, dollars: Double?, costShare: Double) {
            self.model = model
            self.tally = tally
            self.dollars = dollars
            self.costShare = costShare
        }
    }

    public let spanDays: Int
    /// Oldest → newest, one entry per calendar day, zero-filled.
    public let days: [Day]
    public let totalDollars: Double
    /// Sorted by dollars descending, unpriced models last.
    public let models: [ModelCost]
    /// Models seen in the logs that the price table has no entry for.
    public let unpricedModels: [ModelID]
    public let generatedAt: Date
    public let scanDurationMs: Int
    /// Every `.jsonl` found, including the ones already fully consumed.
    public let filesDiscovered: Int
    /// Each day as a fraction of the busiest, so every chart drawn from this
    /// report scales identically. Derived once — `days` never changes after
    /// init, and the panel re-renders at 1 Hz.
    public let dailyFractionOfPeak: [Double]

    public init(
        spanDays: Int,
        days: [Day],
        totalDollars: Double,
        models: [ModelCost],
        unpricedModels: [ModelID],
        generatedAt: Date,
        scanDurationMs: Int,
        filesDiscovered: Int
    ) {
        self.spanDays = spanDays
        self.days = days
        self.totalDollars = totalDollars
        self.models = models
        self.unpricedModels = unpricedModels
        self.generatedAt = generatedAt
        self.scanDurationMs = scanDurationMs
        self.filesDiscovered = filesDiscovered
        if let peak = days.map(\.dollars).max(), peak > 0 {
            dailyFractionOfPeak = days.map { $0.dollars / peak }
        } else {
            dailyFractionOfPeak = Array(repeating: 0, count: days.count)
        }
    }

    /// Builds the report from the cache's day → model → tally tallies.
    public static func build(
        dailyTallies: [DayKey: [ModelID: TokenTally]],
        prices: PriceTable,
        spanDays: Int = Intervals.costReportDays,
        now: Date = Date(),
        scanDurationMs: Int = 0,
        filesDiscovered: Int = 0
    ) -> CostReport {
        let calendar = Calendar.current
        var dayKeys: [DayKey] = []
        for back in stride(from: spanDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            dayKeys.append(DayKey(date))
        }
        let window = Set(dayKeys)

        var perModel: [ModelID: TokenTally] = [:]
        var perDayDollars: [DayKey: Double] = [:]
        for (day, modelTallies) in dailyTallies where window.contains(day) {
            for (model, tally) in modelTallies {
                perModel[model, default: TokenTally()] += tally
                if let dollars = prices.dollars(for: tally, model: model) {
                    perDayDollars[day, default: 0] += dollars
                }
            }
        }

        var priced: [(model: ModelID, tally: TokenTally, dollars: Double?)] = []
        var unpriced: [ModelID] = []
        var total = 0.0
        for (model, tally) in perModel {
            let dollars = prices.dollars(for: tally, model: model)
            if let dollars {
                total += dollars
            } else {
                unpriced.append(model)
            }
            priced.append((model, tally, dollars))
        }

        var lines = priced.map { line in
            ModelCost(
                model: line.model,
                tally: line.tally,
                dollars: line.dollars,
                costShare: total > 0 ? (line.dollars ?? 0) / total : 0)
        }
        lines.sort { ($0.dollars ?? -1) > ($1.dollars ?? -1) }

        return CostReport(
            spanDays: spanDays,
            days: dayKeys.map { Day(key: $0, dollars: perDayDollars[$0] ?? 0) },
            totalDollars: total,
            models: lines,
            unpricedModels: unpriced.sorted(),
            generatedAt: now,
            scanDurationMs: scanDurationMs,
            filesDiscovered: filesDiscovered)
    }
}

/// API-equivalent spend vs what the subscription actually costs.
public struct CostComparison: Sendable, Equatable {
    /// API equivalent divided by subscription cost, e.g. 4.7.
    public let subscriptionMultiple: Double?
    /// The day accumulated API-equivalent spend crossed the subscription
    /// price, or nil if it never did inside the window.
    public let breakEvenDay: DayKey?
    public let monthlyPrice: Double

    public init(report: CostReport, monthlyPrice: Double) {
        self.monthlyPrice = monthlyPrice
        guard monthlyPrice > 0 else {
            subscriptionMultiple = nil
            breakEvenDay = nil
            return
        }
        subscriptionMultiple = report.totalDollars / monthlyPrice
        var accumulated = 0.0
        breakEvenDay = report.days.first { day in
            accumulated += day.dollars
            return accumulated >= monthlyPrice
        }?.key
    }
}

/// A subscription tier: how it is named, and what it lists for.
public struct PlanTier: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let monthlyUSD: Double

    public init(id: String, displayName: String, monthlyUSD: Double) {
        self.id = id
        self.displayName = displayName
        self.monthlyUSD = monthlyUSD
    }

    /// The sentinel the settings picker stores when the user wants the tier
    /// taken from their account rather than chosen by hand.
    public static let automaticID = "auto"

    public static let known: [PlanTier] = [
        PlanTier(id: "pro", displayName: "Pro", monthlyUSD: 20),
        PlanTier(id: "max_5x", displayName: "Max 5x", monthlyUSD: 100),
        PlanTier(id: "max_20x", displayName: "Max 20x", monthlyUSD: 200),
        PlanTier(id: "team", displayName: "Team", monthlyUSD: 30),
    ]

    /// Accepts `default_claude_max_5x`-style tier IDs from the usage response
    /// or `max` / `pro` subscription types from the credential store.
    public static func resolve(_ raw: String?) -> PlanTier? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("max_20x") || raw.contains("20x") {
            return known.first { $0.id == "max_20x" }
        }
        if raw.contains("max_5x") || raw.contains("5x") || raw.contains("max") {
            return known.first { $0.id == "max_5x" }
        }
        if raw.contains("team") {
            return known.first { $0.id == "team" }
        }
        if raw.contains("pro") {
            return known.first { $0.id == "pro" }
        }
        return nil
    }

    /// The tier to bill against: an explicit choice wins, otherwise whatever
    /// the account reported. Nil when neither is known.
    public static func effective(override: String, detected: String?) -> PlanTier? {
        if override != automaticID, let chosen = known.first(where: { $0.id == override }) {
            return chosen
        }
        return resolve(detected)
    }
}
